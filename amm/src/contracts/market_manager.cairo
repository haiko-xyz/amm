#[starknet::contract]
mod MarketManager {
    ////////////////////////////////
    // IMPORTS
    ////////////////////////////////

    // Core lib imports.
    use cmp::min;
    use dict::Felt252DictTrait;
    use nullable::nullable_from_box;
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::info::{get_caller_address, get_block_timestamp, get_contract_address};
    use starknet::replace_class_syscall;
    use starknet::class_hash::ClassHash;
    use snforge_std::PrintTrait;

    // Local imports.
    use amm::libraries::{tree, id, price_lib, liquidity_lib, swap_lib, order_lib, quote_lib};
    use amm::libraries::math::{math, price_math, fee_math, liquidity_math};
    use amm::libraries::constants::{ONE, MAX_WIDTH, MAX_LIMIT_SHIFTED};
    use amm::interfaces::IMarketManager::IMarketManager;
    use amm::interfaces::IStrategy::{IStrategyDispatcher, IStrategyDispatcherTrait};
    use amm::interfaces::IFeeController::{IFeeControllerDispatcher, IFeeControllerDispatcherTrait};
    use amm::interfaces::ILoanReceiver::{ILoanReceiverDispatcher, ILoanReceiverDispatcherTrait};
    use amm::types::core::{
        MarketInfo, MarketConfigs, MarketState, OrderBatch, Position, LimitInfo, LimitOrder,
        ERC721PositionInfo, SwapParams, ConfigOption, Config
    };
    use amm::types::i128::{i128, I128Zeroable, I128Trait};
    use amm::types::i256::{i256, I256Trait};
    use amm::libraries::store_packing::{
        MarketInfoStorePacking, MarketStateStorePacking, MarketConfigsStorePacking,
        LimitInfoStorePacking, OrderBatchStorePacking, PositionStorePacking, LimitOrderStorePacking
    };

    // External imports.
    use openzeppelin::token::erc20::interface::{
        IERC20Dispatcher, IERC20DispatcherTrait, IERC20MetadataDispatcher,
        IERC20MetadataDispatcherTrait
    };
    use openzeppelin::token::erc721::erc721::ERC721Component;
    use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721MetadataImpl = ERC721Component::ERC721MetadataImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        // Ownable
        owner: ContractAddress,
        queued_owner: ContractAddress,
        // Global information
        // Indexed by asset
        reserves: LegacyMap::<ContractAddress, u256>,
        protocol_fees: LegacyMap::<ContractAddress, u256>,
        flash_loan_fee: LegacyMap::<ContractAddress, u16>,
        // Market information
        // Indexed by market_id = hash(base_token, quote_token, width, strategy, fee_controller)
        market_info: LegacyMap::<felt252, MarketInfo>,
        market_state: LegacyMap::<felt252, MarketState>,
        market_configs: LegacyMap::<felt252, MarketConfigs>,
        whitelist: LegacyMap::<felt252, bool>,
        // Indexed by (market_id: felt252, limit: u32)
        limit_info: LegacyMap::<(felt252, u32), LimitInfo>,
        // Indexed by position id = hash(market_id: felt252, owner: ContractAddress, lower_limit: u32, upper_limit: u32)
        positions: LegacyMap::<felt252, Position>,
        // Indexed by batch_id = hash(market_id: felt252, limit: u32, nonce: u128)
        batches: LegacyMap::<felt252, OrderBatch>,
        // Indexed by order_id = hash(market_id: felt252, nonce: u128, owner: ContractAddress)
        orders: LegacyMap::<felt252, LimitOrder>,
        // Next assignable swap id
        swap_id: u128,
        // Bitmap of initialised limits arranged as 3-level tree.
        // Indexed by market_id
        limit_tree_l0: LegacyMap::<felt252, felt252>,
        // Indexed by (market_id: felt252, seg_index_l1: u32)
        limit_tree_l1: LegacyMap::<(felt252, u32), felt252>,
        // Indexed by (market_id: felt252, seg_index_l2: u32)
        limit_tree_l2: LegacyMap::<(felt252, u32), felt252>,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
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
        Whitelist: Whitelist,
        EnableConcentrated: EnableConcentrated,
        CollectProtocolFee: CollectProtocolFee,
        Sweep: Sweep,
        ChangeOwner: ChangeOwner,
        ChangeFlashLoanFee: ChangeFlashLoanFee,
        ChangeProtocolShare: ChangeProtocolShare,
        SetMarketConfigs: SetMarketConfigs,
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
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
        controller: ContractAddress,
        start_limit: u32,
        start_sqrt_price: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ModifyPosition {
        caller: ContractAddress,
        market_id: felt252,
        lower_limit: u32,
        upper_limit: u32,
        liquidity_delta: i128,
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
        in_token: ContractAddress,
        out_token: ContractAddress,
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
        market_liquidity: u128, // global liquidity after swap
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
    struct Whitelist {
        market_id: felt252
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

    #[derive(Drop, starknet::Event)]
    struct SetMarketConfigs {
        min_lower: u32,
        max_lower: u32,
        min_upper: u32,
        max_upper: u32,
        add_liquidity: ConfigOption,
        remove_liquidity: ConfigOption,
        create_bid: ConfigOption,
        create_ask: ConfigOption,
        collect_order: ConfigOption,
        swap: ConfigOption,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.swap_id.write(1);
        self.erc721.initializer('Sphinx Liquidity Positions', 'SPHINX-LP');

        self
            .emit(
                Event::ChangeOwner(ChangeOwner { old: ContractAddressZeroable::zero(), new: owner })
            );
    }

    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn assert_only_owner(self: @ContractState) {
            assert(self.owner.read() == get_caller_address(), 'OnlyOwner');
        }

        fn enforce_status(
            self: @ContractState, value: ConfigOption, market_info: @MarketInfo, err_msg: felt252,
        ) {
            let caller = get_caller_address();
            match value {
                ConfigOption::Enabled => assert(true, err_msg),
                ConfigOption::Disabled => assert(false, err_msg),
                ConfigOption::OnlyOwner => assert(caller == *market_info.controller, err_msg),
                ConfigOption::OnlyStrategy => assert(caller == *market_info.strategy, err_msg),
            }
        }

        fn enforce_fixed<T, impl TPartialEq: PartialEq<T>, impl TDrop: Drop<T>>(
            self: @ContractState, config: Config<T>, new_config: Config<T>, err_msg: felt252
        ) {
            if config.fixed {
                assert(config == new_config, err_msg);
            }
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

        fn is_whitelisted(self: @ContractState, market_id: felt252) -> bool {
            self.whitelist.read(market_id)
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
            if fee_controller.is_zero() {
                self.market_info.read(market_id).swap_fee_rate
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

        fn position(
            self: @ContractState,
            market_id: felt252,
            owner: felt252,
            lower_limit: u32,
            upper_limit: u32
        ) -> Position {
            let position_id = id::position_id(market_id, owner, lower_limit, upper_limit);
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

        fn market_configs(self: @ContractState, market_id: felt252) -> MarketConfigs {
            self.market_configs.read(market_id)
        }

        fn batch(self: @ContractState, batch_id: felt252) -> OrderBatch {
            self.batches.read(batch_id)
        }

        fn liquidity(self: @ContractState, market_id: felt252) -> u128 {
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

        // Returns total amount of tokens, inclusive of fees, inside of a liquidity position.
        // 
        // # Arguments
        // * `market_id` - market id
        // * `position_id` - position id (see `id` library)
        // * `lower_limit` - lower limit of position
        // * `upper_limit` - upper limit of position
        fn amounts_inside_position(
            self: @ContractState,
            market_id: felt252,
            position_id: felt252,
            lower_limit: u32,
            upper_limit: u32,
        ) -> (u256, u256) {
            liquidity_lib::amounts_inside_position(
                self, market_id, position_id, lower_limit, upper_limit
            )
        }

        // Returns the token amounts to be transferred for creating a liquidity position.
        //
        // # Arguments
        // * `market_id` - market id
        // * `lower_limit` - lower limit of position
        // * `upper_limit` - upper limit of position
        // * `liquidity` - liquidity of position
        //
        // # Returns
        // * `base_amount` - amount of base tokens to transfer
        // * `quote_amount` - amount of quote tokens to transfer
        fn liquidity_to_amounts(
            self: @ContractState,
            market_id: felt252,
            lower_limit: u32,
            upper_limit: u32,
            liquidity_delta: u128,
        ) -> (u256, u256) {
            let market_state = self.market_state.read(market_id);
            let market_info = self.market_info.read(market_id);
            let (base_amount, quote_amount) = liquidity_math::liquidity_to_amounts(
                I128Trait::new(liquidity_delta, false),
                market_state.curr_sqrt_price,
                price_math::limit_to_sqrt_price(lower_limit, market_info.width),
                price_math::limit_to_sqrt_price(upper_limit, market_info.width),
                market_info.width,
            );
            (base_amount.val, quote_amount.val)
        }

        // Convert desired token amount to liquidity for limit orders.
        //
        // # Arguments
        // * `market_id` - market id
        // * `is_buy` - whether order is a bid or ask
        // * `limit` - limit at which limit order is placed
        // * `amount` - amount of tokens to convert
        //
        // # Returns
        // * `liquidity` - equivalent liquidity
        fn amount_to_liquidity(
            self: @ContractState, market_id: felt252, is_bid: bool, limit: u32, amount: u256,
        ) -> u128 {
            let width = self.width(market_id);
            let lower_sqrt_price = price_math::limit_to_sqrt_price(limit, width);
            let upper_sqrt_price = price_math::limit_to_sqrt_price(limit + width, width);
            // Round down to avoid returning a liquidity amount that requires greater token balances
            // than is available to the user.
            if is_bid {
                liquidity_math::quote_to_liquidity(
                    lower_sqrt_price, upper_sqrt_price, amount, false
                )
            } else {
                liquidity_math::base_to_liquidity(lower_sqrt_price, upper_sqrt_price, amount, false)
            }
        }

        // Information corresponding to ERC721 position token.
        //
        // # Arguments
        // * `token_id` - token id (position id)
        //
        // # Returns
        // * `base_token` - base token address
        // * `quote_token` - quote token address
        // * `width` - width of market position is in
        // * `strategy` - strategy contract address of market
        // * `swap_fee_rate` - swap fee denominated in bps
        // * `fee_controller` - fee controller contract address of market
        // * `liquidity` - liquidity of position
        // * `base_amount` - amount of base tokens inside position
        // * `quote_amount` - amount of quote tokens inside position
        // * `lower_limit` - lower limit of position
        // * `upper_limit` - upper limit of position
        fn ERC721_position_info(self: @ContractState, token_id: felt252) -> ERC721PositionInfo {
            let position = self.positions.read(token_id);
            let market_info = self.market_info.read(position.market_id);
            let (base_amount, quote_amount) = liquidity_lib::amounts_inside_position(
                self, position.market_id, token_id, position.lower_limit, position.upper_limit
            );

            ERC721PositionInfo {
                base_token: market_info.base_token,
                quote_token: market_info.quote_token,
                width: market_info.width,
                strategy: market_info.strategy,
                swap_fee_rate: market_info.swap_fee_rate,
                fee_controller: market_info.fee_controller,
                controller: market_info.controller,
                liquidity: position.liquidity,
                base_amount,
                quote_amount,
                lower_limit: position.lower_limit,
                upper_limit: position.upper_limit,
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
        // * `width` - limit width of market
        // * `strategy` - strategy contract address, or 0 if no strategy
        // * `swap_fee_rate` - swap fee denominated in bps
        // * `flash_loan_fee` - flash loan fee denominated in bps
        // * `fee_controller` - fee controller contract address
        // * `protocol_share` - protocol share denominated in 0.01% shares of swap fee (e.g. 500 = 5%)
        // * `start_limit` - initial limit (shifted)
        // * `controller` - market controller for upgrading market configs, or 0 if none
        // * `configs` - (optional) custom market configurations
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
            controller: ContractAddress,
            configs: Option<MarketConfigs>,
        ) -> felt252 {

            // Checkpoint: gas used in validating inputs
            let mut gas_before = testing::get_available_gas();
            // Validate inputs.
            assert(base_token.is_non_zero() && quote_token.is_non_zero(), 'TokensNull');
            assert(width != 0, 'WidthZero');
            assert(width <= MAX_WIDTH, 'WidthOF');
            assert(swap_fee_rate <= fee_math::MAX_FEE_RATE, 'FeeRateOF');
            assert(protocol_share <= fee_math::MAX_FEE_RATE, 'ProtocolShareOF');
            assert(start_limit < MAX_LIMIT_SHIFTED, 'StartLimitOF');

            // Check tokens exist.
            IERC20MetadataDispatcher { contract_address: base_token }.name();
            IERC20MetadataDispatcher { contract_address: quote_token }.name();
            'CM input checks 1'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End   

            // Initialise market info, first checking the market does not already exist.
            // A market is uniquely identified by the base and quote token, market width, swap fee,
            // fee controller and market owner. Duplicate markets are disallowed.
            let new_market_info = MarketInfo {
                base_token, quote_token, width, strategy, swap_fee_rate, fee_controller, controller,
            };
            
            // Checkpoint: gas used in validating market
            gas_before = testing::get_available_gas();

            let market_id = id::market_id(new_market_info);
            'CM market id gen 2'.print();
            (gas_before - testing::get_available_gas()).print();

            let market_info = self.market_info.read(market_id);
            assert(market_info.base_token.is_zero(), 'MarketExists');
            assert(self.whitelist.read(market_id), 'NotWhitelisted');
            self.market_info.write(market_id, new_market_info);

            // Initialise market settings.
            if configs.is_some() {
                let configs_uw = configs.unwrap();
                assert(controller.is_non_zero(), 'NoController');
                self.market_configs.write(market_id, configs_uw);
            }

            // Checkpoint End   

            // Checkpoint: gas used in finding sqrt price from limit
            gas_before = testing::get_available_gas();
            // Initialise market state.
            let start_sqrt_price = price_math::limit_to_sqrt_price(start_limit, width);
            'CM limit->price 3'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End   

            let mut market_state: MarketState = Default::default();
            market_state.curr_limit = start_limit;
            market_state.curr_sqrt_price = start_sqrt_price;
            market_state.protocol_share = protocol_share;

            // Checkpoint: gas used in commiting state
            gas_before = testing::get_available_gas();
            // Commit state.
            self.market_info.write(market_id, new_market_info);

            self.market_state.write(market_id, market_state);
            'CM update state 4'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End   

            // Emit events.
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
                            controller,
                            start_limit,
                            start_sqrt_price,
                        }
                    )
                );
            if protocol_share != 0 {
                self
                    .emit(
                        Event::ChangeProtocolShare(
                            ChangeProtocolShare { market_id, protocol_share }
                        )
                    );
            }
            if configs.is_some() {
                let configs = configs.unwrap();
                self
                    .emit(
                        Event::SetMarketConfigs(
                            SetMarketConfigs {
                                min_lower: configs.limits.value.min_lower,
                                max_lower: configs.limits.value.max_lower,
                                min_upper: configs.limits.value.min_upper,
                                max_upper: configs.limits.value.max_upper,
                                add_liquidity: configs.add_liquidity.value,
                                remove_liquidity: configs.remove_liquidity.value,
                                create_bid: configs.create_bid.value,
                                create_ask: configs.create_ask.value,
                                collect_order: configs.collect_order.value,
                                swap: configs.swap.value,
                            }
                        )
                    );
            }

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
            liquidity_delta: i128,
        ) -> (i256, i256, u256, u256) {
            let gas_before = testing::get_available_gas();
            // Run checks.
            let market_info = self.market_info.read(market_id);
            let market_configs = self.market_configs.read(market_id);
            let (config, err_msg) = if liquidity_delta.sign {
                (market_configs.remove_liquidity.value, 'RemLiqDisabled')
            } else {
                (market_configs.add_liquidity.value, 'AddLiqDisabled')
            };
            'MP: initial checks'.print();
            (gas_before - testing::get_available_gas()).print();
            self.enforce_status(config, @market_info, err_msg);

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
            liquidity_delta: u128,
        ) -> felt252 {

            // Checkpoint: gas used in reading state
            let mut gas_before = testing::get_available_gas();
            // Retrieve market info.
            let market_state = self.market_state.read(market_id);
            let market_info = self.market_info.read(market_id);
            let market_configs = self.market_configs.read(market_id);
            'CO read state 1'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End   

            // Checkpoint: gas used input checks
            gas_before = testing::get_available_gas();
            // Run checks.
            assert(market_info.width != 0, 'MarketNull');
            let (config, err_msg) = if is_bid {
                (market_configs.create_bid.value, 'CreateBidDisabled')
            } else {
                (market_configs.create_ask.value, 'CreateAskDisabled')
            };
            self.enforce_status(config, @market_info, err_msg);
            if is_bid {
                assert(limit < market_state.curr_limit, 'NotLimitOrder');
            } else {
                assert(limit > market_state.curr_limit, 'NotLimitOrder');
            }
            assert(liquidity_delta != 0, 'OrderAmtZero');
            'CO checks 2'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End  

            // Fetch order and batch info.
            let mut limit_info = self.limit_info.read((market_id, limit));
            let caller = get_caller_address();

            // Checkpoint: gas used in creating order id
            gas_before = testing::get_available_gas();
            let order_id = id::order_id(market_id, limit, limit_info.nonce, caller);
            'CO order_id create 3'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End   
            
            // Checkpoint: gas used in creating batch id
            gas_before = testing::get_available_gas();
            let mut batch_id = id::batch_id(market_id, limit, limit_info.nonce);
            'CO batch_id create 3'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End   

            let mut batch = self.batches.read(batch_id);

            // Checkpoint: gas used in modify position for order batch
            gas_before = testing::get_available_gas();
            // Create liquidity position. 
            // Note this step also transfers tokens from caller to contract.
            let (base_amount, quote_amount, _, _) = self
                ._modify_position(
                    batch_id,
                    market_id,
                    limit,
                    limit + market_info.width,
                    I128Trait::new(liquidity_delta, false),
                    true,
                );
            'CO _mp 4'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End   

            // Update or create order.
            let mut order = self.orders.read(order_id);

            // Checkpoint: gas used in updating order and batch
            gas_before = testing::get_available_gas();
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
                batch.quote_amount += quote_amount.val.try_into().expect('BatchQuoteAmtOF');
            } else {
                batch.base_amount += base_amount.val.try_into().expect('BatchBaseAmtOF');
            };
            'CO update order/batch 5'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End   

            // Checkpoint: gas used in contract state update
            gas_before = testing::get_available_gas();
            // Commit state updates.
            self.batches.write(batch_id, batch);
            self.orders.write(order_id, order);
            'CO update state 6'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End   

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

            // Checkpoint: gas used in reading contract state
            let mut gas_before = testing::get_available_gas();
            // Fetch market info, order and batch.
            let market_info = self.market_info.read(market_id);
            let market_state = self.market_state.read(market_id);
            let market_configs = self.market_configs.read(market_id);
            let mut order = self.orders.read(order_id);
            let mut batch = self.batches.read(order.batch_id);
            'COO read state 1'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End  

            // Run checks.
            self
                .enforce_status(
                    market_configs.collect_order.value, @market_info, 'CollectOrderDisabled'
                );
            assert(order.liquidity != 0, 'OrderCollected');

            // Calculate withdraw amounts. User's share of batch is calculated based on
            // the liquidity of their order relative to the total liquidity of the batch.
            // If we are collecting from the batch and it has not yet been filled, we need to 
            // first remove our share of batch liquidity from the pool. However, if the batch
            // has accrued fees (e.g. through partial fills), it will also withdraw all fees
            // from the position. To discourage this, fees are forfeited and not paid out to
            // the user if they collect from an unfilled batch.
            gas_before = testing::get_available_gas();
            let mut batch = self.batches.read(order.batch_id);
            let (base_amount, quote_amount) = if !batch.filled {
                let (base_amount, quote_amount, base_fees, quote_fees) = self
                    ._modify_position(
                        order.batch_id,
                        market_id,
                        batch.limit,
                        batch.limit + market_info.width,
                        I128Trait::new(order.liquidity, true),
                        true
                    );
                (base_amount.val - base_fees, quote_amount.val - quote_fees)
            } else {
                // Round down token amounts when withdrawing.
                let base_amount = math::mul_div(
                    batch.base_amount.into(), order.liquidity.into(), batch.liquidity.into(), false
                );
                let quote_amount = math::mul_div(
                    batch.quote_amount.into(), order.liquidity.into(), batch.liquidity.into(), false
                );
                (base_amount, quote_amount)
            };
            'COO _mp 3'.print();
            (gas_before - testing::get_available_gas()).print();

            // Checkpoint: gas used in updating order
            gas_before = testing::get_available_gas();

            // Update order and batch.
            batch.liquidity -= order.liquidity;
            batch.base_amount -= base_amount.try_into().expect('BatchBaseAmtOF');
            batch.quote_amount -= quote_amount.try_into().expect('BatchQuoteAmtOF');
            order.liquidity = 0;

            // Commit state updates.
            self.batches.write(order.batch_id, batch);
            self.orders.write(order_id, order);
            'COO update order/batch 4'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End  

            // Checkpoint: gas used in updating market state
            gas_before = testing::get_available_gas();
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
            'COO update market 5'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End  

            // Checkpoint: gas used in transferring tokens
            gas_before = testing::get_available_gas();
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
            'COO transfer token 6'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End 

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
        // * `threshold_amount` - minimum amount out for exact input, or max amount in for exact output
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
            threshold_amount: Option<u256>,
            deadline: Option<u64>,
        ) -> (u256, u256, u256) {
            // Checkpoint: gas used in updating swap_id
            let mut gas_before = testing::get_available_gas();
            // Assign and update swap id.
            // Swap id is used to identify swaps that are part of a multi-hop route.
            let swap_id = self.swap_id.read();
            self.swap_id.write(swap_id + 1);
            'SW update s_id 1'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End 

            // Checkpoint: gas used in _swap function execution
            gas_before = testing::get_available_gas();
            let (in, out, fee) = self
                ._swap(
                    market_id,
                    is_buy,
                    amount,
                    exact_input,
                    threshold_sqrt_price,
                    threshold_amount,
                    swap_id,
                    deadline,
                    false
                );
            'SW _SW 2'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End 
            (in, out, fee)
        }

        // Swap tokens across multiple markets in a multi-hop route.
        // 
        // # Arguments
        // * `in_token` - in token address
        // * `out_token` - out token address
        // * `amount` - amount of tokens to swap in
        // * `route` - list of market ids defining the route to swap through
        // * `threshold_amount` - minimum amount out
        // * `deadline` - deadline for swap to be executed by
        //
        // # Returns
        // * `amount_out` - amount of tokens swapped out net of fees
        fn swap_multiple(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            amount: u256,
            route: Span<felt252>,
            threshold_amount: Option<u256>,
            deadline: Option<u64>,
        ) -> u256 {

            // Checkpoint: gas used in _swap_multiple function execution
            let mut gas_before = testing::get_available_gas();
            // Execute swap.
            let amount_out = self
                ._swap_multiple(in_token, out_token, amount, route, deadline, false);
            'SM _SM 1'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End 

            // Check amount against threshold.
            if threshold_amount.is_some() {
                assert(amount_out >= threshold_amount.unwrap(), 'ThresholdAmount');
            }

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
                            in_token,
                            out_token,
                            amount_in: amount,
                            amount_out,
                        }
                    )
                );

            // Return amount out.
            amount_out
        }

        // Obtain quote for a swap between tokens (returned as error message).
        // This is the safest way to obtain a quote as it does not rely on the strategy to
        // correctly report its queued and placed positions.
        //
        // # Arguments
        // * `market_id` - market id
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap
        // * `exact_input` - true if `amount` is exact input, or false if exact output
        // * `threshold_sqrt_price` - maximum sqrt price to swap at for buys, minimum for sells
        // 
        // # Returns (as error message)
        // * `amount` - amount out (if exact input) or amount in (if exact output)
        fn quote(
            ref self: ContractState,
            market_id: felt252,
            is_buy: bool,
            amount: u256,
            exact_input: bool,
            threshold_sqrt_price: Option<u256>,
        ) {
            let (amount_in, amount_out, _) = self
                ._swap(
                    market_id,
                    is_buy,
                    amount,
                    exact_input,
                    threshold_sqrt_price,
                    Option::None(()),
                    1, // mock swap id - unused
                    Option::None(()),
                    true,
                );
            let quote = if exact_input {
                amount_out
            } else {
                amount_in
            };
            // Return amount as error message.
            assert(false, quote.try_into().unwrap());
        }

        // Obtain quote for a swap across multiple markets in a multi-hop route.
        // Returned as error message. This is the safest way to obtain a quote as it does not rely on
        // the strategy to correctly report its queued and placed positions.
        // 
        // # Arguments
        // * `in_token` - in token address
        // * `out_token` - out token address
        // * `amount` - amount of tokens to swap in
        // * `route` - list of market ids defining the route to swap through
        //
        // # Returns (as error message)
        // * `amount_out` - amount of tokens swapped out net of fees
        fn quote_multiple(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            amount: u256,
            route: Span<felt252>,
        ) {
            let amount_out = self
                ._swap_multiple(in_token, out_token, amount, route, Option::None(()), true);
            assert(false, amount_out.try_into().unwrap());
        }

        // Obtain quote for a single swap.
        // Caution: this function returns a correct quote only so long as the strategy correctly
        // reports its queued and placed positions. This function is intended for use by on-chain
        // callers that cannot retrieve `quote` via error message. Alternatively, it can be used 
        // to obtain guaranteed correct quotes for non-strategy markets.
        //
        // # Arguments
        // * `market_id` - market id
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap
        // * `exact_input` - true if `amount` is exact input, or false if exact output
        // * `threshold_sqrt_price` - maximum sqrt price to swap at for buys, minimum for sells
        // * `ignore_strategy` - whether to ignore strategy positions when fetching quote
        //
        // # Returns
        // * `amount` - amount out (if exact input) or amount in (if exact output)
        fn unsafe_quote(
            self: @ContractState,
            market_id: felt252,
            is_buy: bool,
            amount: u256,
            exact_input: bool,
            threshold_sqrt_price: Option<u256>,
            ignore_strategy: bool,
        ) -> u256 {
            // Fetch market info and state.
            let market_info = self.market_info.read(market_id);
            let mut market_state = self.market_state.read(market_id);
            let market_configs = self.market_configs.read(market_id);

            // Run checks.
            self.enforce_status(market_configs.swap.value, @market_info, 'SwapDisabled');
            assert(market_info.quote_token.is_non_zero(), 'MarketNull');
            assert(amount > 0, 'AmtZero');
            if threshold_sqrt_price.is_some() {
                price_lib::check_threshold(
                    threshold_sqrt_price.unwrap(), market_state.curr_sqrt_price, is_buy
                );
            }

            // Fetch strategy positions and simulate updates.
            // To account for queued position updates, we update in-memory market liquidity by 
            // removing liquidity from in-range placed positions and adding liquidity to in-range 
            // queued positions. Simultaneously, we extract a set of liquidity deltas and initialised
            // limits from the positions, which we use to augment liquidity when traversing limits. 
            let mut queued_deltas: Felt252Dict<Nullable<i128>> = Default::default();
            let mut target_limits = ArrayTrait::<u32>::new();
            if market_info.strategy.is_non_zero() && !ignore_strategy {
                let strategy = IStrategyDispatcher { contract_address: market_info.strategy };
                let placed_positions = strategy.placed_positions();
                let queued_positions = strategy.queued_positions();
                quote_lib::populate_limits(
                    ref queued_deltas, ref target_limits, ref market_state, placed_positions, true
                );
                quote_lib::populate_limits(
                    ref queued_deltas, ref target_limits, ref market_state, queued_positions, false
                );
            }

            // Get swap fee. 
            // This is either a fixed swap fee or a variable one set by the external fee controller.
            let fee_rate = if market_info.fee_controller.is_zero() {
                market_info.swap_fee_rate
            } else {
                let rate = IFeeControllerDispatcher { contract_address: market_info.fee_controller }
                    .swap_fee_rate();
                assert(rate <= fee_math::MAX_FEE_RATE, 'FeeRateOF');
                rate
            };

            // Initialise trackers for swap state.
            let mut amount_rem = amount;
            let mut amount_calc = 0;
            let mut swap_fees = 0;
            let mut protocol_fees = 0;

            // Simulate swap.
            quote_lib::quote_iter(
                self,
                market_id,
                ref market_state,
                ref amount_rem,
                ref amount_calc,
                ref swap_fees,
                ref queued_deltas,
                target_limits.span(),
                threshold_sqrt_price,
                fee_rate,
                market_info.width,
                is_buy,
                exact_input,
            );

            // Return quote.
            amount_calc
        }

        // Obtain quote for a multi-market swap.
        // Caution: this function returns a correct quote only so long as the strategy correctly
        // reports its queued and placed positions. This function is intended for use by on-chain
        // callers that cannot retrieve `quote_multiple` via error message. Alternatively, it can 
        // be used to obtain guaranteed correct quotes for non-strategy markets.
        //
        // # Arguments
        // * `in_token` - in token address
        // * `out_token` - out token address
        // * `amount` - amount of tokens to swap in
        // * `route` - list of market ids defining the route to swap through
        // * `ignore_strategy` - whether to ignore strategy positions when fetching quote
        //
        // # Returns
        // * `amount_out` - amount of tokens swapped out net of fees
        fn unsafe_quote_multiple(
            self: @ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            amount: u256,
            route: Span<felt252>,
            ignore_strategy: bool,
        ) -> u256 {
            assert(route.len() > 1, 'NotMultiSwap');

            // Initialise swap values.
            let mut i = 0;
            let mut in_token_iter = in_token;
            let mut amount_out = amount;

            loop {
                if i == route.len() {
                    break;
                }

                // Fetch market for current swap iteration.
                let market_id = *route.at(i);
                let market_info = self.market_info.read(market_id);

                // Check that route is valid.
                let is_buy_iter = in_token_iter == market_info.quote_token;
                if !is_buy_iter {
                    assert(in_token_iter == market_info.base_token, 'RouteMismatch');
                }

                // Execute swap and update values.
                let amount_out_iter = self
                    .unsafe_quote(
                        market_id, is_buy_iter, amount_out, true, Option::None(()), ignore_strategy,
                    );
                amount_out = amount_out_iter;
                in_token_iter =
                    if is_buy_iter {
                        market_info.base_token
                    } else {
                        market_info.quote_token
                    };

                i += 1;
            };

            // Check that final token is out token.
            assert(in_token_iter == out_token, 'RouteMismatch');

            // Return amount out.
            amount_out
        }

        // Initiates a flash loan.
        //
        // # Arguments
        // * `token` - contract address of the token borrowed
        // * `amount` - borrow amount requested
        fn flash_loan(ref self: ContractState, token: ContractAddress, amount: u256,) {
            // Check amount non-zero.
            assert(amount > 0, 'LoanAmtZero');


            // Checkpoint: gas used in calculating fee for flash loan
            let mut gas_before = testing::get_available_gas();
            // Calculate flash loan fee.
            let fee_rate = self.flash_loan_fee.read(token);
            let fees = fee_math::calc_fee(amount, fee_rate);
            'FL calc fee 1'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End 

            // Checkpoint: gas used in taking balance snapshot and checks
            gas_before = testing::get_available_gas();
            // Snapshot balance before. Check sufficient tokens to finance loan.
            let token_contract = IERC20Dispatcher { contract_address: token };
            let contract = get_contract_address();
            let balance_before = token_contract.balance_of(contract);
            assert(amount <= balance_before, 'LoanInsufficient');
            'FL snapshot 2'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End 

            // Transfer tokens to caller.
            let borrower = get_caller_address();
            token_contract.transfer(borrower, amount);

            // Checkpoint: gas used in calling loan reciever contract
            gas_before = testing::get_available_gas();
            // Ping callback function to return tokens.
            // Borrower must be smart contract that implements `ILoanReceiver` interface.
            ILoanReceiverDispatcher { contract_address: borrower }
                .on_flash_loan(token, amount, fees);
            'FL loan_receiver 3'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End 

            // Check balances correctly returned.
            let balance_after = token_contract.balance_of(contract);
            assert(balance_after >= balance_before + fees, 'LoanNotReturned');

            // Checkpoint: gas used in updating reserves
            gas_before = testing::get_available_gas();
            // Update reserves.
            let mut reserves = self.reserves.read(token);
            reserves += fees;
            self.reserves.write(token, reserves);
            'FL update reserves 4'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End 

            // Update protocol fees.
            let protocol_fees = self.protocol_fees.read(token);
            self.protocol_fees.write(token, protocol_fees + fees);

            // Emit event.
            self.emit(Event::FlashLoan(FlashLoan { borrower, token, amount }));
        }

        // Mint ERC721 to represent an open liquidity position.
        //
        // # Arguments
        // * `position_id` - id of position mint
        fn mint(ref self: ContractState, position_id: felt252) {
            let position = self.positions.read(position_id);

            // Check caller is owner.
            let caller = get_caller_address();

            // Checkpoint: gas used in calculating position id and checks
            let mut gas_before = testing::get_available_gas();
            let expected_position_id = id::position_id(
                position.market_id, caller.into(), position.lower_limit, position.upper_limit
            );
            assert(position_id == expected_position_id, 'NotOwnerOrNull');
            'MT calc p_id / checks 1'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End 

            // Checkpoint: gas used in minting erc721
            gas_before = testing::get_available_gas();
            // Mint ERC721 token.
            self.erc721._mint(caller, position_id.into());
            'MT _MT 2'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End 
        }

        // Burn ERC721 to unlock capital from open liquidity positions.
        //
        // # Arguments
        // * `position_id` - id of position to burn
        fn burn(ref self: ContractState, position_id: felt252) {
            // Verify caller.
            let caller = get_caller_address();

            // Checkpoint: gas used in checking erc721 ownership and position info
            let mut gas_before = testing::get_available_gas();
            assert(
                self.erc721._is_approved_or_owner(caller, position_id.into()), 'NotApprovedOrOwner'
            );

            // Check position is empty.
            let position_info = self.ERC721_position_info(position_id);
            assert(
                position_info.liquidity == 0
                    && position_info.base_amount == 0
                    && position_info.quote_amount == 0,
                'NotCleared'
            );
            'BN checks 1'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End

            // Checkpoint: gas used in burning erc721 token
            let mut gas_before = testing::get_available_gas();
            // Burn ERC721 token.
            self.erc721._burn(position_id.into());
            'BN _BN 2'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End
        }

        // Whitelist a token for market creation.
        // Callable by owner only.
        //
        // # Arguments
        // * `market_id` - market id
        fn whitelist(ref self: ContractState, market_id: felt252) {
            // Validate caller and inputs.
            self.assert_only_owner();

            // Check not already whitelisted.
            let whitelisted = self.whitelist.read(market_id);
            assert(!whitelisted, 'AlreadyWhitelisted');

            // Update whitelist.
            self.whitelist.write(market_id, true);

            // Emit event.
            self.emit(Event::Whitelist(Whitelist { market_id }));
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

            // Return if no fees to collect.
            if capped == 0 {
                return 0;
            }

            // Update reserves.
            let reserves = self.reserves.read(token);
            self.reserves.write(token, reserves - capped);

            // Transfer tokens to recipient.
            let token_contract = IERC20Dispatcher { contract_address: token };
            token_contract.transfer(receiver, capped);

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

            if amount_collected > 0 {
                // Transfer tokens to receiver.
                token_contract.transfer(receiver, amount_collected);

                // Emit event.
                self.emit(Event::Sweep(Sweep { receiver, token, amount: amount_collected }));
            }

            // Return amount collected.
            amount_collected
        }

        // Request transfer ownership of the contract.
        // Part 1 of 2 step process to transfer ownership.
        //
        // # Arguments
        // * `new_owner` - New owner of the contract
        fn transfer_owner(ref self: ContractState, new_owner: ContractAddress) {
            self.assert_only_owner();
            let old_owner = self.owner.read();
            assert(new_owner != old_owner, 'SameOwner');
            self.queued_owner.write(new_owner);
        }

        // Called by new owner to accept ownership of the contract.
        // Part 2 of 2 step process to transfer ownership.
        fn accept_owner(ref self: ContractState) {
            let queued_owner = self.queued_owner.read();
            assert(get_caller_address() == queued_owner, 'OnlyNewOwner');
            let old_owner = self.owner.read();
            self.owner.write(queued_owner);
            self.queued_owner.write(ContractAddressZeroable::zero());
            self.emit(Event::ChangeOwner(ChangeOwner { old: old_owner, new: queued_owner }));
        }

        // Set flash loan fee.
        // Callable by owner only.
        //
        // # Arguments
        // * `token` - contract address of the token borrowed
        // * `fee` - flash loan fee denominated in bps
        fn set_flash_loan_fee(ref self: ContractState, token: ContractAddress, fee: u16,) {
            self.assert_only_owner();
            assert(fee <= fee_math::MAX_FEE_RATE, 'FeeOF');
            self.flash_loan_fee.write(token, fee);
            self.emit(Event::ChangeFlashLoanFee(ChangeFlashLoanFee { token, fee }));
        }

        // Set protocol share for a given market.
        // Callable by owner only.
        // 
        // # Arguments
        // * `market_id` - market id
        // * `protocol_share` - protocol share
        fn set_protocol_share(ref self: ContractState, market_id: felt252, protocol_share: u16,) {
            self.assert_only_owner();
            assert(protocol_share <= fee_math::MAX_FEE_RATE, 'ProtocolShareOF');

            let mut market_state = self.market_state.read(market_id);
            market_state.protocol_share = protocol_share;
            self.market_state.write(market_id, market_state);

            self
                .emit(
                    Event::ChangeProtocolShare(ChangeProtocolShare { market_id, protocol_share })
                );
        }

        // Set market configs.
        // Callable by market owner only. Enforces checks that each config is upgradeable.
        // 
        // # Arguments
        // * `market_id` - market id'
        // * `new_configs` - new market configs
        fn set_market_configs(
            ref self: ContractState, market_id: felt252, new_configs: MarketConfigs
        ) {
            // Fetch market info and configs.
            let market_info = self.market_info.read(market_id);
            let configs = self.market_configs.read(market_id);

            // Check inputs.
            if market_info.controller.is_non_zero() {
                assert(get_caller_address() == market_info.controller, 'OnlyController');
            } else {
                assert(false, 'MarketUnowned');
            }
            self.enforce_fixed(configs.limits, new_configs.limits, 'LimitsFixed');
            self.enforce_fixed(configs.add_liquidity, new_configs.add_liquidity, 'AddLiqFixed');
            self
                .enforce_fixed(
                    configs.remove_liquidity, new_configs.remove_liquidity, 'RemLiqFixed'
                );
            self.enforce_fixed(configs.create_bid, new_configs.create_bid, 'CreateBidFixed');
            self.enforce_fixed(configs.create_ask, new_configs.create_ask, 'CreateAskFixed');
            self
                .enforce_fixed(
                    configs.collect_order, new_configs.collect_order, 'CollectOrderFixed'
                );
            assert(configs != new_configs, 'NoChange');

            // Update configs.
            self.market_configs.write(market_id, new_configs);

            // Emit event.
            self
                .emit(
                    Event::SetMarketConfigs(
                        SetMarketConfigs {
                            min_lower: new_configs.limits.value.min_lower,
                            max_lower: new_configs.limits.value.max_lower,
                            min_upper: new_configs.limits.value.min_upper,
                            max_upper: new_configs.limits.value.max_upper,
                            add_liquidity: new_configs.add_liquidity.value,
                            remove_liquidity: new_configs.remove_liquidity.value,
                            create_bid: new_configs.create_bid.value,
                            create_ask: new_configs.create_ask.value,
                            collect_order: new_configs.collect_order.value,
                            swap: new_configs.swap.value,
                        }
                    )
                );
        }

        // Upgrade contract class.
        // Callable by owner only.
        // TODO: add timelock
        //
        // # Arguments
        // * `new_class_hash` - new class hash of contract
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.assert_only_owner();
            replace_class_syscall(new_class_hash);
        }
    }

    #[generate_trait]
    impl MarketManagerInternalImpl of MarketManagerInternalTrait {
        // Internal function to modify liquidity from a position.
        // Called by `modify_position`, `create_order`, `collect_order` and `fill_limits`.
        //
        // # Arguments
        // * `market_id` - market ID
        // * `owner` - owner of position (or batch id if limit order)
        // * `lower_limit` - lower limit at which position starts
        // * `upper_limit` - higher limit at which position ends
        // * `liquidity_delta` - amount of liquidity to add or remove
        // * `is_limit_order` - whether `modify_position` is being called as part of a limit order
        //
        // # Returns
        // * `base_amount` - amount of base tokens transferred in (+ve) or out (-ve), including fees
        // * `quote_amount` - amount of quote tokens transferred in (+ve) or out (-ve), including fees
        // * `base_fees` - amount of base tokens collected in fees
        // * `quote_fees` - amount of quote tokens collected in fees
        fn _modify_position(
            ref self: ContractState,
            owner: felt252,
            market_id: felt252,
            lower_limit: u32,
            upper_limit: u32,
            liquidity_delta: i128,
            is_limit_order: bool,
        ) -> (i256, i256, u256, u256) {
            let mut gas_before = testing::get_available_gas();

            // Fetch market info and caller.
            let market_info = self.market_info.read(market_id);
            let market_state = self.market_state.read(market_id);
            let valid_limits = self.market_configs.read(market_id).limits.value;
            let caller = get_caller_address();

            'MP: read state'.print();
            (gas_before - testing::get_available_gas()).print(); 
            gas_before = testing::get_available_gas();

            // Check inputs.
            assert(market_info.quote_token.is_non_zero(), 'MarketNull');
            price_lib::check_limits(
                lower_limit, upper_limit, market_info.width, valid_limits, liquidity_delta.sign
            );

            'MP: input checks'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Update liquidity (without transferring tokens).
            // Gas benchmarks take place inside this function so we exclude it here.
            let (base_amount, quote_amount, base_fees, quote_fees) =
                liquidity_lib::update_liquidity(
                ref self, owner, @market_info, market_id, lower_limit, upper_limit, liquidity_delta
            );

            'MP: update_liquidity [T]'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

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

            'MP: update fees'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Update reserves and transfer tokens.
            // That is, unless modifying liquidity as part of a limit order. In this case, do nothing
            // because tokens are transferred only when the order is collected.
            if !is_limit_order || !liquidity_delta.sign {
                // Update reserves.
                if base_amount.val != 0 {
                    let mut base_reserves = self.reserves.read(market_info.base_token);
                    if base_amount.sign {
                        assert(base_reserves >= base_amount.val, 'ModifyPosBaseReserves');
                    }
                    liquidity_math::add_delta_u256(ref base_reserves, base_amount);
                    self.reserves.write(market_info.base_token, base_reserves);
                }
                if quote_amount.val != 0 {
                    let mut quote_reserves = self.reserves.read(market_info.quote_token);
                    if quote_amount.sign {
                        assert(quote_reserves >= quote_amount.val, 'ModifyPosQuoteReserves');
                    }
                    liquidity_math::add_delta_u256(ref quote_reserves, quote_amount);
                    self.reserves.write(market_info.quote_token, quote_reserves);
                }

                'MP: update reserves'.print();
                (gas_before - testing::get_available_gas()).print();
                gas_before = testing::get_available_gas();

                // Transfer tokens from payer to contract.
                let contract = get_contract_address();

                // Checkpoint: gas used in transferring tokens from payer to contract
                if base_amount.val > 0 {
                    let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
                    if base_amount.sign {
                        assert(
                            base_token.balance_of(contract) >= base_amount.val,
                            'ModifyPosBaseTransfer'
                        );
                        base_token.transfer(caller, base_amount.val);
                    } else {
                        assert(
                            base_token.balance_of(caller) >= base_amount.val,
                            'ModifyPosBaseTransferFrom'
                        );
                        base_token.transfer_from(caller, contract, base_amount.val);
                    }
                }
                if quote_amount.val > 0 {
                    let quote_token = IERC20Dispatcher {
                        contract_address: market_info.quote_token
                    };
                    if quote_amount.sign {
                        assert(
                            quote_token.balance_of(contract) >= quote_amount.val,
                            'ModifyPosQuoteTransfer'
                        );
                        quote_token.transfer(caller, quote_amount.val);
                    } else {
                        assert(
                            quote_token.balance_of(caller) >= quote_amount.val,
                            'ModifyPosQuoteTransferFrom'
                        );
                        quote_token.transfer_from(caller, contract, quote_amount.val);
                    }
                }
                'MP: transfer tokens'.print();
                (gas_before - testing::get_available_gas()).print();
                gas_before = testing::get_available_gas();
            }

            // Emit event if position was modified or fees collected.
            if base_amount.val != 0 || quote_amount.val != 0 || base_fees != 0 || quote_fees != 0 {
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
            }

            'MP: emit event'.print();
            (gas_before - testing::get_available_gas()).print();

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
        // * `threshold_amount` - minimum amount out for exact input, or max amount in for exact output
        // * `swap_id` - unique swap id
        // * `deadline` - deadline for swap to be executed by
        // * `quote_mode` - if true, does not try to transfer token balances
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
            threshold_amount: Option<u256>,
            swap_id: u128,
            deadline: Option<u64>,
            quote_mode: bool,
        ) -> (u256, u256, u256) {
            // Checkpoint: gas used in validating inputs
            let mut gas_before = testing::get_available_gas();

            // Fetch market info and state.
            let market_info = self.market_info.read(market_id);
            let mut market_state = self.market_state.read(market_id);
            let market_configs = self.market_configs.read(market_id);
            let curr_sqrt_price_start = market_state.curr_sqrt_price;

            'SW: read state'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Run checks.
            self.enforce_status(market_configs.swap.value, @market_info, 'SwapDisabled');
            assert(market_info.quote_token.is_non_zero(), 'MarketNull');
            assert(amount > 0, 'AmtZero');
            if threshold_sqrt_price.is_some() {
                price_lib::check_threshold(
                    threshold_sqrt_price.unwrap(), market_state.curr_sqrt_price, is_buy
                );
            }
            if deadline.is_some() {
                assert(deadline.unwrap() >= get_block_timestamp(), 'Expired');
            }

            'SW: run checks'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Snapshot sqrt price before swap.
            // Execute strategy if it exists.
            // Strategy positions are updated before the swap occurs.
            let caller = get_caller_address();
            if market_info.strategy.is_non_zero() {
                IStrategyDispatcher { contract_address: market_info.strategy }
                    .update_positions(
                        SwapParams { is_buy, amount, exact_input, threshold_sqrt_price, deadline }
                    );
            }

            'SW: update strategy [T]'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Get swap fee. 
            // This is either a fixed swap fee or a variable one set by the external fee controller.
            let fee_rate = if market_info.fee_controller.is_zero() {
                market_info.swap_fee_rate
            } else {
                let rate = IFeeControllerDispatcher { contract_address: market_info.fee_controller }
                    .swap_fee_rate();
                assert(rate <= fee_math::MAX_FEE_RATE, 'FeeRateOF');
                rate
            };

            'SW: fetch fee rate'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

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

            'SW: init swap state'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            let partial_fill_info = swap_lib::swap_iter(
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
            );

            'SW: swap iter [T]'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Calculate swap amounts.
            assert(amount >= amount_rem, 'SwapAmtSubAmtRem');
            let (amount_in, amount_out) = if exact_input {
                (amount - amount_rem, amount_calc)
            } else {
                (amount_calc, amount - amount_rem)
            };

            // Check swap amount against amount threshold.
            if threshold_amount.is_some() {
                let threshold_amount_val = threshold_amount.unwrap();
                assert(
                    if exact_input {
                        amount_out >= threshold_amount_val
                    } else {
                        amount_in <= threshold_amount_val
                    },
                    'ThresholdAmount'
                );
            }

            'SW: calc swap amts'.print();
            (gas_before - testing::get_available_gas()).print();
            // Checkpoint End

            // Return amounts if quote mode.
            if quote_mode {
                return (amount_in, amount_out, swap_fees + protocol_fees);
            }

            // Checkpoint: gas used in calculating and updating fee balances and commit state
            gas_before = testing::get_available_gas();

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

            'SW: update fee'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Commit update to market state.
            self.market_state.write(market_id, market_state);

            'SW: update market state'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Identify in and out tokens.
            let (in_token, out_token) = if is_buy {
                (market_info.quote_token, market_info.base_token)
            } else {
                (market_info.base_token, market_info.quote_token)
            };
            // Update reserves.
            let in_reserves = self.reserves.read(in_token);
            let out_reserves = self.reserves.read(out_token);
            self.reserves.write(in_token, in_reserves + amount_in);
            assert(out_reserves >= amount_out, 'SwapOutReservesSubAmtOut');
            self.reserves.write(out_token, out_reserves - amount_out);

            'SW: update reserves'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Handle fully filled limit orders. Must be done after state updates above.
            order_lib::fill_limits(
                ref self, market_id, market_info.width, fee_rate, filled_limits.span(),
            );

            'SW: fill full limits [T]'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Handle partially filled limit order. Must be done after state updates above.
            if partial_fill_info.is_some() {
                let partial_fill_info = partial_fill_info.unwrap();
                order_lib::fill_partial_limit(
                    ref self,
                    market_id,
                    partial_fill_info.limit,
                    partial_fill_info.amount_in,
                    partial_fill_info.amount_out,
                    partial_fill_info.is_buy,
                );
            }

            'SW: fill partial limits [T]'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Transfer tokens between payer, receiver and contract.
            let contract = get_contract_address();
            IERC20Dispatcher { contract_address: in_token }
                .transfer_from(caller, contract, amount_in);
            IERC20Dispatcher { contract_address: out_token }.transfer(caller, amount_out);

            'SW: transfer tokens'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

            // Execute strategy cleanup.
            if market_info.strategy.is_non_zero() {
                IStrategyDispatcher { contract_address: market_info.strategy }.cleanup();
            }

            'SW: strategy cleanup'.print();
            (gas_before - testing::get_available_gas()).print();
            gas_before = testing::get_available_gas();

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

            'SW: emit event'.print();
            (gas_before - testing::get_available_gas()).print();

            // Return amounts.
            (amount_in, amount_out, swap_fees + protocol_fees)
        }

        // Internal function to swap tokens across multiple markets in a multi-hop route.
        // Called by `swap_multiple` and `quote_multiple`.
        // 
        // # Arguments
        // * `in_token` - in token address
        // * `out_token` - out token address
        // * `amount` - amount of tokens to swap in
        // * `route` - list of market ids defining the route to swap through
        // * `threshold_amount` - minimum amount out for exact input, or max amount in for exact output
        // * `deadline` - deadline for swap to be executed by
        // * `quote_mode` - if true, does not try to transfer token balances
        //
        // # Returns
        // * `amount_out` - amount of tokens swapped out net of fees
        fn _swap_multiple(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
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
            let mut in_token_iter = in_token;
            let mut amount_out = amount;

            loop {
                if i == route.len() {
                    break;
                }

                // Fetch market for current swap iteration.
                let market_id = *route.at(i);
                let market_info = self.market_info.read(market_id);

                // Check that route is valid.
                let is_buy_iter = in_token_iter == market_info.quote_token;
                if !is_buy_iter {
                    assert(in_token_iter == market_info.base_token, 'RouteMismatch');
                }

                // Execute swap and update values.
                let (_, amount_out_iter, _) = self
                    ._swap(
                        market_id,
                        is_buy_iter,
                        amount_out,
                        true,
                        Option::None(()),
                        Option::None(()),
                        swap_id,
                        deadline,
                        quote_mode
                    );
                amount_out = amount_out_iter;
                in_token_iter =
                    if is_buy_iter {
                        market_info.base_token
                    } else {
                        market_info.quote_token
                    };

                i += 1;
            };

            // Check that final token is out token.
            assert(in_token_iter == out_token, 'RouteMismatch');

            // Return amount out.
            amount_out
        }
    }
}
