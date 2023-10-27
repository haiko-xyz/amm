#[starknet::contract]
mod MarketManager {
    ////////////////////////////////
    // IMPORTS
    ////////////////////////////////

    // Core lib imports.
    use cmp::min;
    use traits::Into;
    use traits::TryInto;
    use option::OptionTrait;
    use zeroable::Zeroable;
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::info::{get_caller_address, get_block_timestamp, get_contract_address};
    use starknet::replace_class_syscall;
    use starknet::class_hash::ClassHash;

    // Local imports.
    use amm::contracts::tokens::erc721::ERC721;
    use amm::libraries::tree;
    use amm::libraries::id;
    use amm::libraries::limit_prices;
    use amm::libraries::liquidity as liquidity_helpers;
    use amm::libraries::swap as swap_helpers;
    use amm::libraries::order as order_helpers;
    use amm::libraries::math::{math, price_math, fee_math, liquidity_math};
    use amm::libraries::constants::{ONE, MAX, MAX_WIDTH, MAX_LIMIT_SHIFTED};
    use amm::interfaces::IMarketManager::IMarketManager;
    use amm::interfaces::IStrategy::{IStrategyDispatcher, IStrategyDispatcherTrait};
    use amm::interfaces::IFeeController::{IFeeControllerDispatcher, IFeeControllerDispatcherTrait};
    use amm::interfaces::ILoanReceiver::{ILoanReceiverDispatcher, ILoanReceiverDispatcherTrait};
    use amm::interfaces::IERC20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use amm::interfaces::IERC721::IERC721;
    use amm::types::core::{
        MarketInfo, MarketState, OrderBatch, Position, LimitInfo, LimitOrder, PositionInfo, SwapParams
    };
    use amm::types::i256::{i256, I256Zeroable, I256Trait};
    use amm::libraries::store_packing::{
        MarketInfoStorePacking, MarketStateStorePacking, LimitInfoStorePacking,
        OrderBatchStorePacking, PositionStorePacking, LimitOrderStorePacking
    };

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        // Ownable
        owner: ContractAddress,
        // Global information
        // Indexed by asset
        reserves: LegacyMap::<ContractAddress, u256>,
        // Indexed by asset
        protocol_fees: LegacyMap::<ContractAddress, u256>,
        // Indexed by asset
        flash_loan_fee: LegacyMap::<ContractAddress, u16>,
        // Next assignable swap id
        swap_id: u128,
        // Market information
        // Indexed by market_id = hash(base_token, quote_token, width, strategy, fee_controller)
        market_info: LegacyMap::<felt252, MarketInfo>,
        // Indexed by market_id
        market_state: LegacyMap::<felt252, MarketState>,
        // Indexed by (market_id: felt252, limit: u32)
        limit_info: LegacyMap::<(felt252, u32), LimitInfo>,
        // Indexed by position id = hash(market_id: felt252, owner: ContractAddress, lower_limit: u32, upper_limit: u32)
        positions: LegacyMap::<felt252, Position>,
        // Indexed by batch_id = hash(market_id: felt252, limit: u32, nonce: u128)
        batches: LegacyMap::<felt252, OrderBatch>,
        // Indexed by order_id = hash(market_id: felt252, nonce: u128, owner: ContractAddress)
        orders: LegacyMap::<felt252, LimitOrder>,
        // Bitmap of initialised limits arranged as 3-level tree.
        // Indexed by market_id
        limit_tree_l0: LegacyMap::<felt252, u256>,
        // Indexed by (market_id: felt252, seg_index_l1: u32)
        limit_tree_l1: LegacyMap::<(felt252, u32), u256>,
        // Indexed by (market_id: felt252, seg_index_l2: u32)
        limit_tree_l2: LegacyMap::<(felt252, u32), u256>,
    }

    ////////////////////////////////
    // EVENTS
    ////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CreateMarket: CreateMarket,
        ModifyPosition: ModifyPosition,
        CreateOrder: CreateOrder,
        CollectOrder: CollectOrder,
        Swap: Swap,
        MultiSwap: MultiSwap,
        FlashLoan: FlashLoan,
        EnableConcentrated: EnableConcentrated,
        CollectProtocolFee: CollectProtocolFee,
        Sweep: Sweep,
        ChangeOwner: ChangeOwner,
        ChangeFlashLoanFee: ChangeFlashLoanFee,
        ChangeProtocolShare: ChangeProtocolShare,
    }

    #[derive(Drop, starknet::Event)]
    struct CreateMarket {
        market_id: felt252,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        width: u32,
        strategy: ContractAddress,
        swap_fee_rate: u16,
        fee_controller: ContractAddress,
        start_limit: u32,
        start_sqrt_price: u256,
        allow_orders: bool,
        allow_positions: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct ModifyPosition {
        caller: ContractAddress,
        market_id: felt252,
        lower_limit: u32,
        upper_limit: u32,
        liquidity_delta: i256,
        base_amount: i256,
        quote_amount: i256,
        base_fees: u256,
        quote_fees: u256,
        is_limit_order: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct CreateOrder {
        caller: ContractAddress,
        market_id: felt252,
        order_id: felt252,
        limit: u32, // start limit
        batch_id: felt252,
        is_bid: bool,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct CollectOrder {
        caller: ContractAddress,
        market_id: felt252,
        order_id: felt252,
        limit: u32,
        batch_id: felt252,
        is_bid: bool,
        base_amount: u256,
        quote_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct MultiSwap {
        caller: ContractAddress,
        swap_id: u128,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        is_buy: bool,
        amount_in: u256,
        amount_out: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Swap {
        caller: ContractAddress,
        market_id: felt252,
        is_buy: bool,
        exact_input: bool,
        amount_in: u256,
        amount_out: u256,
        fees: u256,
        end_limit: u32, // final limit reached after swap
        end_sqrt_price: u256, // final sqrt price reached after swap
        market_liquidity: u256, // global liquidity after swap
        swap_id: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct FlashLoan {
        borrower: ContractAddress,
        token: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct CollectProtocolFee {
        receiver: ContractAddress,
        token: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct EnableConcentrated {
        market_id: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct Sweep {
        receiver: ContractAddress,
        token: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ChangeOwner {
        old: ContractAddress,
        new: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct ChangeFlashLoanFee {
        token: ContractAddress,
        fee: u16,
    }

    #[derive(Drop, starknet::Event)]
    struct ChangeProtocolShare {
        market_id: felt252,
        protocol_share: u16,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.swap_id.write(1);

        let mut unsafe_state = ERC721::unsafe_new_contract_state();
        ERC721::InternalImpl::initializer(
            ref unsafe_state, 'Sphinx Liquidity Positions', 'SPHINX-LP'
        );

        self
            .emit(
                Event::ChangeOwner(ChangeOwner { old: ContractAddressZeroable::zero(), new: owner })
            );
    }

    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn assert_only_owner(self: @ContractState) {
            assert(self.owner.read() == get_caller_address(), 'OnlyOwner')
        }
    }

    #[external(v0)]
    impl MarketManager of IMarketManager<ContractState> {
        ////////////////////////////////
        // VIEW FUNCTIONS
        ////////////////////////////////

        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn base_token(self: @ContractState, market_id: felt252) -> ContractAddress {
            self.market_info.read(market_id).base_token
        }

        fn quote_token(self: @ContractState, market_id: felt252) -> ContractAddress {
            self.market_info.read(market_id).quote_token
        }

        fn width(self: @ContractState, market_id: felt252) -> u32 {
            self.market_info.read(market_id).width
        }

        fn strategy(self: @ContractState, market_id: felt252) -> ContractAddress {
            self.market_info.read(market_id).strategy
        }

        fn fee_controller(self: @ContractState, market_id: felt252) -> ContractAddress {
            self.market_info.read(market_id).fee_controller
        }

        fn swap_fee_rate(self: @ContractState, market_id: felt252) -> u16 {
            let fee_controller = self.market_info.read(market_id).fee_controller;
            if fee_controller == ContractAddressZeroable::zero() {
                0
            } else {
                IFeeControllerDispatcher { contract_address: fee_controller }.swap_fee_rate()
            }
        }

        fn flash_loan_fee(self: @ContractState, token: ContractAddress) -> u16 {
            self.flash_loan_fee.read(token)
        }

        fn protocol_share(self: @ContractState, market_id: felt252) -> u16 {
            self.market_state.read(market_id).protocol_share
        }

        fn position(self: @ContractState, position_id: felt252) -> Position {
            self.positions.read(position_id)
        }

        fn order(self: @ContractState, order_id: felt252) -> LimitOrder {
            self.orders.read(order_id)
        }

        fn market_info(self: @ContractState, market_id: felt252) -> MarketInfo {
            self.market_info.read(market_id)
        }

        fn market_state(self: @ContractState, market_id: felt252) -> MarketState {
            self.market_state.read(market_id)
        }

        fn batch(self: @ContractState, batch_id: felt252) -> OrderBatch {
            self.batches.read(batch_id)
        }

        fn liquidity(self: @ContractState, market_id: felt252) -> u256 {
            self.market_state.read(market_id).liquidity
        }

        fn curr_limit(self: @ContractState, market_id: felt252) -> u32 {
            self.market_state.read(market_id).curr_limit
        }

        fn curr_sqrt_price(self: @ContractState, market_id: felt252) -> u256 {
            self.market_state.read(market_id).curr_sqrt_price
        }

        fn limit_info(self: @ContractState, market_id: felt252, limit: u32) -> LimitInfo {
            self.limit_info.read((market_id, limit))
        }

        fn is_limit_init(self: @ContractState, market_id: felt252, width: u32, limit: u32) -> bool {
            tree::get(self, market_id, width, limit)
        }

        fn next_limit(
            self: @ContractState, market_id: felt252, is_buy: bool, width: u32, start_limit: u32
        ) -> Option<u32> {
            tree::next_limit(self, market_id, is_buy, width, start_limit)
        }

        fn reserves(self: @ContractState, asset: ContractAddress) -> u256 {
            self.reserves.read(asset)
        }

        fn protocol_fees(self: @ContractState, asset: ContractAddress) -> u256 {
            self.protocol_fees.read(asset)
        }

        // Get base and quote fees accrued inside a position.
        fn position_fees(
            self: @ContractState,
            owner: ContractAddress,
            market_id: felt252,
            lower_limit: u32,
            upper_limit: u32
        ) -> (u256, u256) {
            // Fetch state.
            let position_id = id::position_id(market_id, owner.into(), lower_limit, upper_limit);
            let position = self.positions.read(position_id);
            let market_state = self.market_state.read(market_id);
            let lower_limit_info = self.limit_info.read((market_id, lower_limit));
            let upper_limit_info = self.limit_info.read((market_id, upper_limit));

            // Get fee factors and calculate accrued fees.
            let (base_fee_factor, quote_fee_factor) = fee_math::get_fee_inside(
                lower_limit_info,
                upper_limit_info,
                lower_limit,
                upper_limit,
                market_state.curr_limit,
                market_state.base_fee_factor,
                market_state.quote_fee_factor,
            );
            let base_fees = math::mul_div(
                (base_fee_factor.into() - position.base_fee_factor_last),
                position.liquidity.into(),
                ONE,
                false
            );
            let quote_fees = math::mul_div(
                (quote_fee_factor.into() - position.quote_fee_factor_last),
                position.liquidity.into(),
                ONE,
                false
            );

            (base_fees, quote_fees)
        }

        // Information corresponding to ERC721 position token.
        fn ERC721_position_info(self: @ContractState, token_id: felt252) -> PositionInfo {
            let position = self.positions.read(token_id);
            let market_info = self.market_info.read(position.market_id);
            let market_state = self.market_state.read(position.market_id);
            let lower_limit = self.limit_info.read((position.market_id, position.lower_limit));
            let upper_limit = self.limit_info.read((position.market_id, position.upper_limit));
            let (base_amount, quote_amount, base_fees, quote_fees) =
                liquidity_math::amounts_inside_position(
                @market_state, market_info.width, @position, lower_limit, upper_limit,
            );

            PositionInfo {
                base_token: market_info.base_token,
                quote_token: market_info.quote_token,
                width: market_info.width,
                strategy: market_info.strategy,
                swap_fee_rate: market_info.swap_fee_rate,
                fee_controller: market_info.fee_controller,
                liquidity: position.liquidity,
                base_amount: base_amount + base_fees,
                quote_amount: quote_amount + quote_fees,
                base_fee_factor_last: position.base_fee_factor_last,
                quote_fee_factor_last: position.quote_fee_factor_last,
            }
        }


        ////////////////////////////////
        // EXTERNAL FUNCTIONS
        ////////////////////////////////

        // Create a new market. 
        // 
        // # Arguments
        // * `base_token` - base token address
        // * `quote_token` - quote token address
        // * `width` - Limit width of market
        // * `strategy` - Strategy contract address
        // * `swap_fee_rate` - Swap fee denominated in bps
        // * `flash_loan_fee` - Flash loan fee denominated in bps
        // * `fee_controller` - Fee controller contract address
        // * `protocol_share` - Protocol share denominated in 0.01% shares of swap fee (e.g. 500 = 5%)
        // * `start_limit` - Initial limit (shifted)
        // * `allow_positions` - Whether market allows liquidity positions
        // * `allow_orders` - Whether market allows limit orders
        // * `is_concentrated` - Whether market allows concentrated liquidity positions
        //
        // # Returns
        // * `market_id` - Market ID
        fn create_market(
            ref self: ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            width: u32,
            strategy: ContractAddress,
            swap_fee_rate: u16,
            fee_controller: ContractAddress,
            protocol_share: u16,
            start_limit: u32,
            allow_positions: bool,
            allow_orders: bool,
            is_concentrated: bool,
        ) -> felt252 {
            // Validate inputs.
            assert(base_token.is_non_zero() && quote_token.is_non_zero(), 'TokensNull');
            assert(width != 0, 'WidthZero');
            assert(width <= MAX_WIDTH, 'WidthOverflow');
            assert(swap_fee_rate <= fee_math::MAX_FEE_RATE, 'SwapFeeOverflow');
            assert(protocol_share <= fee_math::MAX_FEE_RATE, 'PShareOverflow');
            assert(start_limit < MAX_LIMIT_SHIFTED, 'StartLimitOverflow');

            // Check tokens exist.
            IERC20Dispatcher { contract_address: base_token }.name();
            IERC20Dispatcher { contract_address: quote_token }.name();

            // Check market does not already exist.
            // A market is uniquely identified by the base and quote token, market width, swap fee,
            // and market type configurations. Duplicate markets are disallowed.
            let new_market_info = MarketInfo {
                base_token,
                quote_token,
                width,
                strategy,
                swap_fee_rate,
                fee_controller,
                allow_positions,
                allow_orders,
            };
            let market_id = id::market_id(new_market_info);
            let market_info = self.market_info.read(market_id);
            assert(market_info.base_token.is_zero(), 'MarketExists');

            // Initialise market state.
            let start_sqrt_price = price_math::limit_to_sqrt_price(start_limit, width);
            let market_state = MarketState {
                liquidity: Zeroable::zero(),
                curr_limit: start_limit,
                curr_sqrt_price: start_sqrt_price,
                protocol_share,
                is_concentrated,
                base_fee_factor: Zeroable::zero(),
                quote_fee_factor: Zeroable::zero(),
            };

            // Commit state.
            self.market_info.write(market_id, new_market_info);
            self.market_state.write(market_id, market_state);

            // Emit event.
            self
                .emit(
                    Event::CreateMarket(
                        CreateMarket {
                            market_id,
                            base_token,
                            quote_token,
                            width,
                            strategy,
                            swap_fee_rate,
                            fee_controller,
                            start_limit,
                            start_sqrt_price,
                            allow_orders,
                            allow_positions,
                        }
                    )
                );
            self
                .emit(
                    Event::ChangeProtocolShare(ChangeProtocolShare { market_id, protocol_share })
                );

            market_id
        }

        // Add or remove liquidity from a position, or collect fees by passing 0 as liquidity delta.
        //
        // # Arguments
        // * `market_id` - Market ID
        // * `lower_limit` - Lower limit at which position starts
        // * `upper_limit` - Higher limit at which position ends
        // * `liquidity_delta` - Amount of liquidity to add or remove
        //
        // # Returns
        // * `base_amount` - Amount of base tokens transferred in (+ve) or out (-ve), including fees
        // * `quote_amount` - Amount of quote tokens transferred in (+ve) or out (-ve), including fees
        // * `base_fees` - Amount of base tokens collected in fees
        // * `quote_fees` - Amount of quote tokens collected in fees
        fn modify_position(
            ref self: ContractState,
            market_id: felt252,
            lower_limit: u32,
            upper_limit: u32,
            liquidity_delta: i256,
        ) -> (i256, i256, u256, u256) {
            // The caller of `_modify_position` can either be a user address (formatted as felt252) or 
            // a `batch_id` if it is being modified as part of a limit order. Here, we are dealing with
            // regular positions, so we simply pass in the caller address.
            let caller: felt252 = get_caller_address().into();
            self
                ._modify_position(
                    caller, market_id, lower_limit, upper_limit, liquidity_delta, false
                )
        }

        // Create a new limit order.
        // Must be placed below the current limit for bids, or above the current limit for asks.
        // 
        // # Arguments
        // * `market_id` - market id
        // * `is_bid` - whether bid order
        // * `limit` - limit at which order is placed
        // * `liquidity_delta` - amount of liquidity to add or remove
        //
        // # Returns
        // * `order_id` - order id
        fn create_order(
            ref self: ContractState,
            market_id: felt252,
            is_bid: bool,
            limit: u32,
            liquidity_delta: u256,
        ) -> felt252 {
            // Retrieve market info.
            let market_state = self.market_state.read(market_id);
            let market_info = self.market_info.read(market_id);

            // Run checks.
            assert(market_info.width != 0, 'MarketNull');
            assert(market_info.allow_orders, 'OrdersDisabled');
            assert(
                if is_bid {
                    limit < market_state.curr_limit
                } else {
                    limit > market_state.curr_limit
                },
                'NotLimitOrder'
            );
            assert(liquidity_delta != 0, 'OrderAmtZero');

            // Fetch order and batch info.
            let mut limit_info = self.limit_info.read((market_id, limit));
            let caller = get_caller_address();
            let order_id = id::order_id(market_id, limit, limit_info.nonce, caller);
            let mut batch_id = id::batch_id(market_id, limit, limit_info.nonce);
            let mut batch = self.batches.read(batch_id);

            // Create liquidity position. 
            // Note this step also transfers tokens from caller to contract.
            let (base_amount, quote_amount, _, _) = self
                ._modify_position(
                    batch_id,
                    market_id,
                    limit,
                    limit + market_info.width,
                    I256Trait::new(liquidity_delta, false),
                    true,
                );

            // Update or create order.
            let mut order = self.orders.read(order_id);
            // If this is a new order, initialise batch id.
            if order.batch_id == 0 {
                order.batch_id = batch_id;
            }
            order.liquidity += liquidity_delta;

            // Prevent depositing if partially filled.
            // This shouldn't happen as we run checks on the limit above.
            assert(batch.base_amount == 0 || batch.quote_amount == 0, 'PartialFill');

            // If this is the first order of batch, initialise immutables.
            if batch.limit == 0 {
                batch.limit = limit;
                batch.is_bid = is_bid;
            }

            // Update batch amounts.
            batch.liquidity += liquidity_delta;
            if is_bid {
                batch.quote_amount += quote_amount.val
            } else {
                batch.base_amount += base_amount.val
            };

            // Commit state updates.
            self.batches.write(batch_id, batch);
            self.orders.write(order_id, order);

            // Emit event.
            self
                .emit(
                    Event::CreateOrder(
                        CreateOrder {
                            caller,
                            market_id,
                            order_id,
                            limit,
                            batch_id,
                            is_bid,
                            amount: if is_bid {
                                quote_amount
                            } else {
                                base_amount
                            }.val
                        }
                    )
                );

            // Return order id.
            order_id
        }

        // Collect a limit order.
        // Collects filled amount and refunds unfilled portion.
        // 
        // # Arguments
        // * `market_id` - market id
        // * `order_id` - order id
        //
        // # Returns
        // * `base_amount` - amount of base tokens collected
        // * `quote_amount` - amount of quote tokens collected
        fn collect_order(
            ref self: ContractState, market_id: felt252, order_id: felt252,
        ) -> (u256, u256) {
            // Fetch market info, order and batch.
            let market_info = self.market_info.read(market_id);
            let market_state = self.market_state.read(market_id);
            let mut order = self.orders.read(order_id);
            let mut batch = self.batches.read(order.batch_id);

            // Run checks.
            assert(market_info.allow_orders, 'OrdersDisabled');
            assert(order.liquidity != 0, 'OrderCollected');

            // Calculate withdraw amounts. User's share of batch is calculated based on
            // the liquidity of their order relative to the total liquidity of the batch.
            let base_amount = math::mul_div(
                batch.base_amount, order.liquidity, batch.liquidity, false
            );
            let quote_amount = math::mul_div(
                batch.quote_amount, order.liquidity, batch.liquidity, false
            );

            // Update order and batch.
            // If we are collecting from the batch and it has not yet been filled, we need to 
            // remove our share of batch liquidity from the pool.
            if !batch.filled {
                self
                    ._modify_position(
                        order.batch_id,
                        market_id,
                        batch.limit,
                        batch.limit + market_info.width,
                        I256Trait::new(order.liquidity, true),
                        true
                    );
            }

            // Update order and batch.
            batch.liquidity -= order.liquidity;
            batch.base_amount -= base_amount;
            batch.quote_amount -= quote_amount;
            order.liquidity = 0;

            // Commit state updates.
            self.batches.write(order.batch_id, batch);
            self.orders.write(order_id, order);

            // Update reserves.
            let market_info = self.market_info.read(market_id);
            if base_amount > 0 {
                let mut base_reserves = self.reserves.read(market_info.base_token);
                base_reserves -= base_amount;
                self.reserves.write(market_info.base_token, base_reserves);
            }
            if quote_amount > 0 {
                let mut quote_reserves = self.reserves.read(market_info.quote_token);
                quote_reserves -= quote_amount;
                self.reserves.write(market_info.quote_token, quote_reserves);
            }

            // Transfer tokens to caller.
            let market_info = self.market_info.read(market_id);
            let caller = get_caller_address();
            if base_amount > 0 {
                let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
                base_token.transfer(caller, base_amount);
            }
            if quote_amount > 0 {
                let quote_token = IERC20Dispatcher { contract_address: market_info.quote_token };
                quote_token.transfer(caller, quote_amount);
            }

            // Emit event.
            self
                .emit(
                    Event::CollectOrder(
                        CollectOrder {
                            caller,
                            market_id,
                            order_id,
                            limit: batch.limit,
                            batch_id: order.batch_id,
                            is_bid: batch.is_bid,
                            base_amount,
                            quote_amount,
                        }
                    )
                );

            // Return collected token amounts.
            (base_amount, quote_amount)
        }


        // Swap tokens through a market.
        //
        // # Arguments
        // * `market_id` - ID of market to execute swap through
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap
        // * `exact_input` - true if `amount` is exact input, false if exact output
        // * `threshold_sqrt_price` - maximum sqrt price to swap at for buys, minimum for sells
        // * `deadline` - deadline for swap to be executed by
        //
        // # Returns
        // * `amount_in` - amount of tokens swapped in gross of fees
        // * `amount_out` - amount of tokens swapped out net of fees
        // * `fees` - fees paid in token swapped in
        fn swap(
            ref self: ContractState,
            market_id: felt252,
            is_buy: bool,
            amount: u256,
            exact_input: bool,
            threshold_sqrt_price: Option<u256>,
            deadline: Option<u64>,
        ) -> (u256, u256, u256) {
            // Assign and update swap id.
            // Swap id is used to identify swaps that are part of a multi-hop route.
            let swap_id = self.swap_id.read();
            self.swap_id.write(swap_id + 1);

            self
                ._swap(
                    market_id,
                    is_buy,
                    amount,
                    exact_input,
                    threshold_sqrt_price,
                    swap_id,
                    deadline,
                    false
                )
        }

        // Swap tokens across multiple markets in a multi-hop route.
        // 
        // # Arguments
        // * `base_token` - base token address
        // * `quote_token` - quote token address
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap in
        // * `route` - list of market ids defining the route to swap through
        // * `deadline` - deadline for swap to be executed by
        //
        // # Returns
        // * `amount_out` - amount of tokens swapped out net of fees
        fn swap_multiple(
            ref self: ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            is_buy: bool,
            amount: u256,
            route: Span<felt252>,
            deadline: Option<u64>,
        ) -> u256 {
            // Execute swap.
            let amount_out = self
                ._swap_multiple(base_token, quote_token, is_buy, amount, route, deadline, false);

            // Increment swap id.
            let swap_id = self.swap_id.read();
            self.swap_id.write(swap_id + 1);

            // Emit event.
            self
                .emit(
                    Event::MultiSwap(
                        MultiSwap {
                            caller: get_caller_address(),
                            swap_id,
                            base_token,
                            quote_token,
                            is_buy,
                            amount_in: amount,
                            amount_out,
                        }
                    )
                );

            // Return amount out.
            amount_out
        }

        // Obtain quote for a swap between tokens.
        //
        // # Arguments
        // * `market_id` - market id
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap
        // * `exact_input` - true if `amount` is exact input, or false if exact output
        // * `threshold_sqrt_price` - maximum sqrt price to swap at for buys, minimum for sells
        // 
        // # Returns
        // * `amount` - amount out (if exact input) or amount in (if exact output)
        fn quote(
            ref self: ContractState,
            market_id: felt252,
            is_buy: bool,
            amount: u256,
            exact_input: bool,
            threshold_sqrt_price: Option<u256>,
        ) -> u256 {
            let (amount_in, amount_out, _) = self
                ._swap(
                    market_id,
                    is_buy,
                    amount,
                    exact_input,
                    threshold_sqrt_price,
                    1,
                    Option::None(()),
                    true
                );
            let return_amount = if exact_input {
                amount_out
            } else {
                amount_in
            };
            return return_amount;
        }

        // Obtain quote for a swap across multiple markets in a multi-hop route.
        // 
        // # Arguments
        // * `base_token` - base token address
        // * `quote_token` - quote token address
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap in
        // * `route` - list of market ids defining the route to swap through
        // * `deadline` - deadline for swap to be executed by
        //
        // # Returns
        // * `amount_out` - amount of tokens swapped out net of fees
        fn quote_multiple(
            ref self: ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            is_buy: bool,
            amount: u256,
            route: Span<felt252>,
            deadline: Option<u64>,
        ) -> u256 {
            self._swap_multiple(base_token, quote_token, is_buy, amount, route, deadline, true)
        }

        // Initiates a flash loan.
        //
        // # Arguments
        // * `token` - contract address of the token borrowed
        // * `amount` - borrow amount requested
        fn flash_loan(ref self: ContractState, token: ContractAddress, amount: u256,) {
            // Check amount non-zero.
            assert(amount > 0, 'LoanAmtZero');

            // Calculate flash loan fee.
            let fee_rate = self.flash_loan_fee.read(token);
            let fees = fee_math::calc_fee(amount, fee_rate);

            // Snapshot balance before. Check sufficient tokens to finance loan.
            let token_contract = IERC20Dispatcher { contract_address: token };
            let contract = get_contract_address();
            let balance_before = token_contract.balance_of(contract);
            assert(amount <= balance_before, 'LoanInsufficient');

            // Transfer tokens to caller.
            let borrower = get_caller_address();
            token_contract.transfer(borrower, amount);

            // Ping callback function to return tokens.
            // Borrower must be smart contract that implements `ILoanReceiver` interface.
            ILoanReceiverDispatcher { contract_address: borrower }.on_flash_loan(amount);

            // Check balances correctly returned.
            let balance_after = token_contract.balance_of(contract);
            assert(balance_after >= balance_before + fees, 'LoanNotReturned');

            // Update reserves.
            let mut reserves = self.reserves.read(token);
            reserves += fees;
            self.reserves.write(token, reserves);

            // Update protocol fees.
            let mut protocol_fees = self.protocol_fees.read(token);
            protocol_fees += fees;
            self.protocol_fees.write(token, protocol_fees);

            // Emit event.
            self.emit(Event::FlashLoan(FlashLoan { borrower, token, amount }));
        }

        // Mint ERC721 to represent capital locked in open liquidity positions.
        //
        // # Arguments
        // * `position_id` - id of position mint
        fn mint(ref self: ContractState, position_id: felt252) {
            // Validate caller and inputs.
            let position = self.positions.read(position_id);
            let caller = get_caller_address();
            let expected_position_id = id::position_id(
                position.market_id, caller.into(), position.lower_limit, position.upper_limit
            );
            assert(position_id == expected_position_id, 'OnlyOwner');

            // Mint ERC721 token.
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::InternalImpl::_mint(ref unsafe_state, caller, position_id.into());
        }

        // Burn ERC721 to unlock capital from open liquidity positions.
        //
        // # Arguments
        // * `position_id` - id of position to burn
        fn burn(ref self: ContractState, position_id: felt252) {
            // Verify caller.
            let caller = get_caller_address();
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            assert(
                ERC721::InternalImpl::_is_approved_or_owner(
                    @unsafe_state, caller, position_id.into()
                ),
                'NotApprovedNorOwner'
            );

            // Check position exists and is empty.
            let position_info = self.ERC721_position_info(position_id);
            assert(position_info.base_token.is_non_zero(), 'PositionNull');
            assert(
                position_info.liquidity == 0
                    && position_info.base_amount == 0
                    && position_info.quote_amount == 0,
                'PositionNotEmpty'
            );

            // Burn ERC721 token.
            ERC721::InternalImpl::_burn(ref unsafe_state, position_id.into());
        }

        // Upgrades Linear Market to Concentrated Market by enabling concentrated liquidity positions.
        // Callable by owner only.
        //
        // # Arguments
        // * `market_id` - market id
        fn enable_concentrated(ref self: ContractState, market_id: felt252) {
            // Validate caller and check not already upgraded.
            self.assert_only_owner();
            let mut market_state = self.market_state.read(market_id);
            assert(!market_state.is_concentrated, 'AlreadyConcentrated');

            // Update market state.
            market_state.is_concentrated = true;
            self.market_state.write(market_id, market_state);

            // Emit event.
            self.emit(Event::EnableConcentrated(EnableConcentrated { market_id }));
        }

        // Collect protocol fees.
        // Callable by owner only.
        //
        // # Arguments
        // * `receiver` - Recipient of collected fees
        // * `token` - Token to collect fees in
        // * `amount` - Amount of fees requested
        // 
        // # Returns
        // * `amount` - Amount of fees collected
        fn collect_protocol_fees(
            ref self: ContractState,
            receiver: ContractAddress,
            token: ContractAddress,
            amount: u256,
        ) -> u256 {
            // Verify caller.
            self.assert_only_owner();

            // Cap amount requested at available. Update protocol fee balance.
            let protocol_fees = self.protocol_fees.read(token);
            let capped = min(amount, protocol_fees);
            self.protocol_fees.write(token, protocol_fees - capped);

            if capped > 0 {
                // Update reserves.
                let reserves = self.reserves.read(token);
                self.reserves.write(token, reserves - capped);

                // Transfer tokens to recipient.
                let token_contract = IERC20Dispatcher { contract_address: token };
                token_contract.transfer(receiver, capped);
            }

            // Emit event.
            self
                .emit(
                    Event::CollectProtocolFee(
                        CollectProtocolFee { receiver, token, amount: capped }
                    )
                );

            // Return amount collected.
            capped
        }

        // Sweeps excess tokens from contract.
        // Used to collect tokens sent to contract by mistake.
        //
        // # Arguments
        // * `receiver` - Recipient of swept tokens
        // * `token` - Token to sweep
        // * `amount` - Requested amount of token to sweep
        //
        // # Returns
        // * `amount_collected` - Amount of base token swept
        fn sweep(
            ref self: ContractState,
            receiver: ContractAddress,
            token: ContractAddress,
            amount: u256,
        ) -> u256 {
            // Validate caller and inputs.
            self.assert_only_owner();
            assert(receiver.is_non_zero(), 'ReceiverNull');
            assert(token.is_non_zero(), 'MarketNull');
            assert(amount != 0, 'AmountZero');

            // Initialise variables.
            let contract = get_contract_address();
            let token_contract = IERC20Dispatcher { contract_address: token };

            // Calculate amounts.
            let reserves = self.reserves.read(token);
            let balance = token_contract.balance_of(contract);
            let amount_collected = if balance > reserves {
                min(amount, balance - reserves)
            } else {
                0
            };

            // Transfer tokens to receiver.
            if amount_collected > 0 {
                token_contract.transfer(receiver, amount_collected);
            }

            // Emit event.
            self.emit(Event::Sweep(Sweep { receiver, token, amount: amount_collected }));

            // Return amount collected.
            amount_collected
        }

        // Transfer ownership of the contract.
        //
        // # Arguments
        // * `new_owner` - New owner of the contract
        fn set_owner(ref self: ContractState, new_owner: ContractAddress) {
            self.assert_only_owner();
            let old_owner = self.owner.read();
            self.owner.write(new_owner);

            self.emit(Event::ChangeOwner(ChangeOwner { old: old_owner, new: new_owner }));
        }

        // Set flash loan fee.
        // Callable by owner only.
        //
        // # Arguments
        // * `token` - contract address of the token borrowed
        // * `fee` - flash loan fee denominated in bps
        fn set_flash_loan_fee(ref self: ContractState, token: ContractAddress, fee: u16,) {
            self.assert_only_owner();
            assert(fee <= fee_math::MAX_FEE_RATE, 'FeeOverflow');
            self.flash_loan_fee.write(token, fee);
            self.emit(Event::ChangeFlashLoanFee(ChangeFlashLoanFee { token, fee }));
        }

        // Set fee parameters for a given market.
        // Callable by owner only.
        // 
        // # Arguments
        // * `market_id` - market id
        // * `protocol_share` - protocol share
        fn set_protocol_share(ref self: ContractState, market_id: felt252, protocol_share: u16,) {
            self.assert_only_owner();
            assert(protocol_share <= fee_math::MAX_FEE_RATE, 'PShareOverflow');

            let mut market_state = self.market_state.read(market_id);
            market_state.protocol_share = protocol_share;
            self.market_state.write(market_id, market_state);

            self
                .emit(
                    Event::ChangeProtocolShare(ChangeProtocolShare { market_id, protocol_share })
                );
        }

        // Upgrade contract class.
        // Callable by owner only.
        //
        // # Arguments
        // # `new_class_hash` - New class hash of the contract
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.assert_only_owner();
            replace_class_syscall(new_class_hash);
        }
    }

    #[external(v0)]
    impl ERC721Impl of IERC721<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::IERC721::balance_of(@unsafe_state, account)
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::IERC721::owner_of(@unsafe_state, token_id)
        }

        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::IERC721::transfer_from(ref unsafe_state, from, to, token_id)
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::IERC721::safe_transfer_from(ref unsafe_state, from, to, token_id, data)
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::IERC721::approve(ref unsafe_state, to, token_id)
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::IERC721::set_approval_for_all(ref unsafe_state, operator, approved)
        }

        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::IERC721::get_approved(@unsafe_state, token_id)
        }

        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::IERC721::is_approved_for_all(@unsafe_state, owner, operator)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // Internal function to modify liquidity from a position.
        // Called by `modify_position`, `create_order`, `collect_order` and `fill_limits`.
        //
        // # Arguments
        // * `market_id` - Market ID
        // * `owner` - Owner of position (or batch id if limit order)
        // * `lower_limit` - Lower limit at which position starts
        // * `upper_limit` - Higher limit at which position ends
        // * `liquidity_delta` - Amount of liquidity to add or remove
        // * `is_limit_order` - Whether `modify_position` is being called as part of a limit order
        //
        // # Returns
        // * `base_amount` - Amount of base tokens transferred in (+ve) or out (-ve), including fees
        // * `quote_amount` - Amount of quote tokens transferred in (+ve) or out (-ve), including fees
        // * `base_fees` - Amount of base tokens collected in fees
        // * `quote_fees` - Amount of quote tokens collected in fees
        fn _modify_position(
            ref self: ContractState,
            owner: felt252,
            market_id: felt252,
            lower_limit: u32,
            upper_limit: u32,
            liquidity_delta: i256,
            is_limit_order: bool,
        ) -> (i256, i256, u256, u256) {
            // Fetch market info and caller.
            let market_info = self.market_info.read(market_id);
            let market_state = self.market_state.read(market_id);
            let caller = get_caller_address();

            // Check inputs.
            assert(market_info.quote_token.is_non_zero(), 'MarketNull');
            if caller != market_info.strategy {
                assert(market_info.allow_positions, 'PositionsDisabled');
            }
            assert(liquidity_delta.val <= MAX, 'LiqDeltaOverflow');
            limit_prices::check_limits(
                lower_limit, upper_limit, market_info.width, market_state.is_concentrated
            );

            // Update liquidity (without transferring tokens).
            let (base_amount, quote_amount, base_fees, quote_fees) =
                liquidity_helpers::update_liquidity(
                ref self, owner, @market_info, market_id, lower_limit, upper_limit, liquidity_delta
            );

            // Calculate and update protocol fee amounts.
            if base_fees > 0 || quote_fees > 0 {
                let protocol_share: u256 = market_state.protocol_share.into();
                let max_fee_rate: u256 = fee_math::MAX_FEE_RATE.into();
                if base_fees > 0 {
                    let mut base_protocol_fees = self.protocol_fees.read(market_info.base_token);
                    base_protocol_fees +=
                        math::mul_div(base_fees, protocol_share, max_fee_rate, false);
                    self.protocol_fees.write(market_info.base_token, base_protocol_fees);
                }
                if quote_fees > 0 {
                    let mut quote_protocol_fees = self.protocol_fees.read(market_info.quote_token);
                    quote_protocol_fees +=
                        math::mul_div(quote_fees, protocol_share, max_fee_rate, false);
                    self.protocol_fees.write(market_info.quote_token, quote_protocol_fees);
                }
            }

            // Update reserves and transfer tokens.
            // That is, unless modifying liquidity as part of a limit order. In this case, do nothing
            // because tokens are transferred only when the order is collected.
            if !is_limit_order || !liquidity_delta.sign {
                // Update reserves.
                if base_amount.val != 0 {
                    let mut base_reserves = self.reserves.read(market_info.base_token);
                    liquidity_math::add_delta(ref base_reserves, base_amount);
                    self.reserves.write(market_info.base_token, base_reserves);
                }
                if quote_amount.val != 0 {
                    let mut quote_reserves = self.reserves.read(market_info.quote_token);
                    liquidity_math::add_delta(ref quote_reserves, quote_amount);
                    self.reserves.write(market_info.quote_token, quote_reserves);
                }

                // Transfer tokens from payer to contract.
                let contract = get_contract_address();
                if base_amount.val > 0 {
                    let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
                    if base_amount.sign {
                        base_token.transfer(caller, base_amount.val);
                    } else {
                        base_token.transfer_from(caller, contract, base_amount.val);
                    }
                }
                if quote_amount.val > 0 {
                    let quote_token = IERC20Dispatcher {
                        contract_address: market_info.quote_token
                    };
                    if quote_amount.sign {
                        quote_token.transfer(caller, quote_amount.val);
                    } else {
                        quote_token.transfer_from(caller, contract, quote_amount.val);
                    }
                }
            }

            // Emit event.
            self
                .emit(
                    Event::ModifyPosition(
                        ModifyPosition {
                            caller: owner.try_into().unwrap(),
                            market_id,
                            lower_limit,
                            upper_limit,
                            liquidity_delta,
                            base_amount,
                            quote_amount,
                            base_fees,
                            quote_fees,
                            is_limit_order,
                        }
                    )
                );

            // Return amounts.
            (base_amount, quote_amount, base_fees, quote_fees)
        }

        // Internal function to swap tokens.
        // Called by `swap`, `swap_multiple` and `quote`.
        //
        // # Arguments
        // * `market_id` - market ID
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap in
        // * `exact_input` - true if `amount` is exact input, otherwise exact output
        // * `threshold_sqrt_price` - maximum sqrt price to swap at for buys, minimum for sells
        // * `swap_id` - unique swap id
        // * `deadline` - deadline for swap to be executed by
        // * `quote_mode` - if enabled, does not perform any state updates
        //
        // # Returns
        // * `amount_in` - amount of tokens swapped in gross of fees
        // * `amount_out` - amount of tokens swapped out net of fees
        // * `fees` - fees paid in token swapped in
        fn _swap(
            ref self: ContractState,
            market_id: felt252,
            is_buy: bool,
            amount: u256,
            exact_input: bool,
            threshold_sqrt_price: Option<u256>,
            swap_id: u128,
            deadline: Option<u64>,
            quote_mode: bool,
        ) -> (u256, u256, u256) {
            // Fetch market info and state.
            let market_info = self.market_info.read(market_id);
            let mut market_state = self.market_state.read(market_id);

            // Validate inputs.
            assert(market_info.quote_token.is_non_zero(), 'MarketNull');
            assert(amount > 0, 'FlashAmtZero');
            if threshold_sqrt_price.is_some() {
                limit_prices::check_threshold(
                    threshold_sqrt_price.unwrap(), market_state.curr_sqrt_price, is_buy
                );
            }
            if deadline.is_some() {
                assert(deadline.unwrap() >= get_block_timestamp(), 'Expired');
            }

            // Snapshot sqrt price before swap.
            let curr_sqrt_price_start = market_state.curr_sqrt_price;

            // Execute strategy if it exists.
            // Strategy positions are updated before the swap occurs.
            let caller = get_caller_address();
            if market_info.strategy.is_non_zero() && caller != market_info.strategy {
                IStrategyDispatcher { contract_address: market_info.strategy }.update_positions(
                    SwapParams { is_buy, amount, exact_input, threshold_sqrt_price, deadline }
                );
            }

            // Get swap fee. 
            // This is either a fixed swap fee or a variable one set by the external fee controller.
            let fee_rate = if market_info.fee_controller.is_zero() {
                market_info.swap_fee_rate
            } else {
                IFeeControllerDispatcher { contract_address: market_info.fee_controller }
                    .swap_fee_rate()
            };

            // Initialise trackers for swap state.
            let mut amount_rem = amount;
            let mut amount_calc = 0;
            let mut swap_fees = 0;
            let mut protocol_fees = 0;
            let mut filled_limits: Array<u32> = array![];

            // Execute swap.
            // Market state must be fetched here after strategy execution.
            // If the final limit is partially filled, details of this are returned to correctly
            // update the limit order batch.
            market_state = self.market_state.read(market_id);
            let partial_fill_info = swap_helpers::swap_iter(
                ref self,
                market_id,
                ref market_state,
                ref amount_rem,
                ref amount_calc,
                ref swap_fees,
                ref protocol_fees,
                ref filled_limits,
                threshold_sqrt_price,
                fee_rate,
                market_info.width,
                is_buy,
                exact_input,
                quote_mode,
            );

            // Calculate swap amounts.
            let amount_in = if exact_input {
                amount - amount_rem
            } else {
                amount_calc
            };
            let amount_out = if exact_input {
                amount_calc
            } else {
                amount - amount_rem
            };

            // No state updates performed up to this point. Return quoted amount if quote mode enabled. 
            if quote_mode {
                return (amount_in, amount_out, swap_fees + protocol_fees);
            }

            // Calculate protocol fee and update fee balances. Write updates to storage.
            if is_buy {
                let mut quote_protocol_fees = self.protocol_fees.read(market_info.quote_token);
                quote_protocol_fees += protocol_fees;
                self.protocol_fees.write(market_info.quote_token, quote_protocol_fees);
            } else {
                let mut base_protocol_fees = self.protocol_fees.read(market_info.base_token);
                base_protocol_fees += protocol_fees;
                self.protocol_fees.write(market_info.base_token, base_protocol_fees);
            }

            // Commit update to market state.
            self.market_state.write(market_id, market_state);

            // Identify in and out tokens.
            let in_token = if is_buy {
                market_info.quote_token
            } else {
                market_info.base_token
            };
            let out_token = if is_buy {
                market_info.base_token
            } else {
                market_info.quote_token
            };

            // Update reserves.
            let in_reserves = self.reserves.read(in_token);
            let out_reserves = self.reserves.read(out_token);
            self.reserves.write(in_token, in_reserves + amount_in);
            self.reserves.write(out_token, out_reserves - amount_out);

            // Handle fully filled limit orders. Must be done after state updates above.
            order_helpers::fill_limits(
                ref self, market_id, market_info.width, fee_rate, filled_limits.span(),
            );

            // Handle partially filled limit order. Must be done after state updates above.
            if partial_fill_info.is_some() {
                let partial_fill_info = partial_fill_info.unwrap();
                order_helpers::fill_partial_limit(
                    ref self,
                    market_id,
                    partial_fill_info.limit,
                    partial_fill_info.amount_in,
                    partial_fill_info.amount_out,
                    partial_fill_info.is_buy,
                );
            }

            // Transfer tokens between payer, receiver and contract.
            let contract = get_contract_address();
            IERC20Dispatcher { contract_address: in_token }
                .transfer_from(caller, contract, amount_in);
            IERC20Dispatcher { contract_address: out_token }.transfer(caller, amount_out);

            // Execute strategy cleanup.
            if market_info.strategy.is_non_zero() && caller != market_info.strategy {
                IStrategyDispatcher { contract_address: market_info.strategy }.cleanup();
            }

            // Emit event.
            self
                .emit(
                    Event::Swap(
                        Swap {
                            caller,
                            market_id,
                            is_buy,
                            exact_input,
                            amount_in,
                            amount_out,
                            fees: swap_fees + protocol_fees,
                            end_limit: market_state.curr_limit,
                            end_sqrt_price: market_state.curr_sqrt_price,
                            market_liquidity: market_state.liquidity,
                            swap_id,
                        }
                    )
                );

            // Return amounts.
            (amount_in, amount_out, swap_fees + protocol_fees)
        }

        // Internal function to swap tokens across multiple markets in a multi-hop route.
        // Called by `swap_multiple` and `quote_multiple`.
        // 
        // # Arguments
        // * `base_token` - base token address
        // * `quote_token` - quote token address
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap in
        // * `route` - list of market ids defining the route to swap through
        // * `deadline` - deadline for swap to be executed by
        // * `quote_mode` - if enabled, does not perform any state updates
        //
        // # Returns
        // * `amount_out` - amount of tokens swapped out net of fees
        fn _swap_multiple(
            ref self: ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            is_buy: bool,
            amount: u256,
            route: Span<felt252>,
            deadline: Option<u64>,
            quote_mode: bool,
        ) -> u256 {
            assert(route.len() > 1, 'NotMultiSwap');

            // Fetch swap id.
            let swap_id = self.swap_id.read();

            // Initialise swap values.
            let mut i = 0;
            let mut in_token = if is_buy {
                quote_token
            } else {
                base_token
            };
            let mut amount_out = amount;

            loop {
                if i == route.len() {
                    break;
                }

                // Fetch market for current swap iteration.
                let market_id = *route.at(i);
                let market_info = self.market_info.read(market_id);

                // Check that route is valid.
                let is_buy_iter = in_token == market_info.quote_token;
                if !is_buy_iter {
                    assert(in_token == market_info.base_token, 'RouteMismatch');
                }

                // Execute swap and update values.
                let (_, amount_out_iter, _) = self
                    ._swap(
                        market_id,
                        is_buy_iter,
                        amount_out,
                        true,
                        Option::None(()),
                        swap_id,
                        deadline,
                        quote_mode,
                    );
                amount_out = amount_out_iter;
                in_token =
                    if is_buy_iter {
                        market_info.base_token
                    } else {
                        market_info.quote_token
                    };

                i += 1;
            };

            amount_out
        }
    }
}
