// Core lib imports.
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy, Serde, starknet::Store)]
struct StrategyParams {
    // default spread between reference price and bid/ask price (TODO: replace with volatility)
    min_spread: u32,
    // slippage parameter (width, in limits, of bid and ask liquidity positions)
    slippage: u32,
    // delta parameter (additional single-sided spread based on portfolio imbalance)
    delta: u32,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
struct OracleParams {
    // Pragma base currency id
    base_currency_id: felt252,
    // Pragma quote currency id
    quote_currency_id: felt252,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
struct PositionInfo {
    lower_limit: u32,
    upper_limit: u32,
    liquidity: u256,
}

impl DefaultPositionInfo of Default<PositionInfo> {
    fn default() -> PositionInfo {
        PositionInfo { lower_limit: 0, upper_limit: 0, liquidity: 0, }
    }
}

////////////////////////////////
// INTERFACE
////////////////////////////////

#[starknet::interface]
trait IReplicatingStrategy<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn oracle(self: @TContractState) -> ContractAddress;
    fn is_paused(self: @TContractState) -> bool;
    fn bid(self: @TContractState) -> PositionInfo;
    fn ask(self: @TContractState) -> PositionInfo;
    fn base_reserves(self: @TContractState) -> u256;
    fn quote_reserves(self: @TContractState) -> u256;
    fn get_oracle_price(self: @TContractState) -> u128;
    fn get_token_amounts(self: @TContractState) -> (u256, u256, u256, u256);
    fn get_bid_ask(self: @TContractState) -> (u32, u32);

    fn initialise(
        ref self: TContractState,
        name: felt252,
        symbol: felt252,
        market_manager: ContractAddress,
        market_id: felt252,
        oracle: ContractAddress,
        base_currency_id: felt252,
        quote_currency_id: felt252,
        scaling_factor: u256,
        min_spread: u32,
        slippage: u32,
        delta: u32,
    );
    fn deposit_initial(
        ref self: TContractState, base_amount: u256, quote_amount: u256
    ) -> (u256, u256, u256);
    fn deposit(
        ref self: TContractState, base_amount: u256, quote_amount: u256
    ) -> (u256, u256, u256);
    fn withdraw(ref self: TContractState, shares: u256) -> (u256, u256);
    fn collect_and_pause(ref self: TContractState);
    fn change_strategy_params(ref self: TContractState, min_spread: u32, slippage: u32, delta: u32);
    fn change_oracle(
        ref self: TContractState,
        oracle: ContractAddress,
        base_currency_id: felt252,
        quote_currency_id: felt252
    );
    fn set_owner(ref self: TContractState, owner: ContractAddress);
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}

////////////////////////////////
// CONTRACT
////////////////////////////////

#[starknet::contract]
mod ReplicatingStrategy {
    // Core lib imports.
    use array::SpanTrait;
    use zeroable::Zeroable;
    use integer::BoundedU256;
    use cmp::{min, max};
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::info::{get_caller_address, get_contract_address, get_block_number};
    use starknet::class_hash::ClassHash;
    use starknet::replace_class_syscall;

    // Local imports.
    use super::IReplicatingStrategy;
    use super::{PositionInfo, StrategyParams, OracleParams};
    use amm::contracts::market_manager::MarketManager;
    use amm::contracts::market_manager::MarketManager::ContractState as MMContractState;
    use amm::types::core::{MarketState, SwapParams};
    use amm::libraries::math::{math, price_math, liquidity_math, fee_math};
    use amm::libraries::constants::ONE;
    use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
    use amm::interfaces::IStrategy::IStrategy;
    use amm::types::i256::{I256Trait, i256};
    use strategies::strategies::replicating::pragma_interfaces::{
        IOracleABIDispatcher, IOracleABIDispatcherTrait, AggregationMode, DataType, SimpleDataType,
        PragmaPricesResponse
    };

    // External imports.
    use openzeppelin::token::erc20::erc20::ERC20;
    use openzeppelin::token::erc20::interface::{ERC20ABI, IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        // Immutables
        owner: ContractAddress,
        market_manager: ContractAddress,
        market_id: felt252,
        is_initialised: bool,

        // Oracle info
        oracle: ContractAddress,
        oracle_params: OracleParams,
        // conversion factor to convert oracle price to 28 decimals
        scaling_factor: u256,
        strategy_params: StrategyParams,
        // whether pool is paused
        is_paused: bool,

        // Strategy state
        base_reserves: u256,
        quote_reserves: u256,
        bid: PositionInfo, // liquidity = 0 if no bid position set
        ask: PositionInfo, // liquidity = 0 if no ask position set
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        UpdatePositions: UpdatePositions,
        Deposit: Deposit,
        Withdraw: Withdraw,
        ChangeParams: ChangeParams,
        ChangeOracle: ChangeOracle,
        ChangeOwner: ChangeOwner,
        Pause: Pause,
        Unpause: Unpause,
    }

    #[derive(Drop, starknet::Event)]
    struct UpdatePositions {
        bid_lower_limit: u32,
        bid_upper_limit: u32,
        bid_liquidity: u256,
        ask_lower_limit: u32,
        ask_upper_limit: u32,
        ask_liquidity: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        owner: ContractAddress,
        base_amount: u256,
        quote_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        owner: ContractAddress,
        base_amount: u256,
        quote_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ChangeParams {
        min_spread: u32,
        slippage: u32,
        delta: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct ChangeOracle {
        oracle: ContractAddress,
        base_currency_id: felt252,
        quote_currency_id: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct ChangeOwner {
        new_owner: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct Pause {}

    #[derive(Drop, starknet::Event)]
    struct Unpause {}

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.is_initialised.write(false);
    }

    ////////////////////////////////
    // FUNCTIONS
    ////////////////////////////////

    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn assert_only_owner(self: @ContractState) {
            assert(self.owner.read() == get_caller_address(), 'OnlyOwner');
        }
    }

    #[external(v0)]
    impl Strategy of IStrategy<ContractState> {
        // Get market manager contract address
        fn market_manager(self: @ContractState) -> ContractAddress {
            self.market_manager.read()
        }

        // Get market id
        fn market_id(self: @ContractState) -> felt252 {
            self.market_id.read()
        }

        // Get strategy name
        fn strategy_name(self: @ContractState) -> felt252 {
            let unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::name(@unsafe_state)
        }

        // Get strategy symbol
        fn strategy_symbol(self: @ContractState) -> felt252 {
            let unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::symbol(@unsafe_state)
        }

        // Updates positions. Called by MarketManager upon swap.
        fn update_positions(ref self: ContractState, params: SwapParams) {
            // Run checks
            assert(get_caller_address() == self.market_manager.read(), 'OnlyMarketManager');
            assert(self.is_initialised.read(), 'NotInitialised');
            if self.is_paused.read() {
                return ();
            }

            let (bid, ask) = self._update_positions();
        }

        fn cleanup(ref self: ContractState) {
            return ();
        }
    }

    #[external(v0)]
    impl ReplicatingStrategy of IReplicatingStrategy<ContractState> {
        // Contract owner
        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        // Whether strategy is paused
        fn is_paused(self: @ContractState) -> bool {
            self.is_paused.read()
        }

        // Contract address of oracle feed.
        fn oracle(self: @ContractState) -> ContractAddress {
            self.oracle.read()
        }

        // Bid position of strategy
        fn bid(self: @ContractState) -> PositionInfo {
            self.bid.read()
        }

        // Ask position of strategy
        fn ask(self: @ContractState) -> PositionInfo {
            self.ask.read()
        }

        // Base reserves of strategy
        fn base_reserves(self: @ContractState) -> u256 {
            self.base_reserves.read()
        }

        // Quote reserves of strategy
        fn quote_reserves(self: @ContractState) -> u256 {
            self.quote_reserves.read()
        }

        // Get price from oracle feed.
        // 
        // # Returns
        // * `price` - oracle price
        fn get_oracle_price(self: @ContractState) -> u128 {
            let oracle_dispatcher = IOracleABIDispatcher { contract_address: self.oracle.read() };
            let oracle_params = self.oracle_params.read();
            let output: PragmaPricesResponse = oracle_dispatcher
                .get_data_with_USD_hop(
                    oracle_params.base_currency_id,
                    oracle_params.quote_currency_id,
                    AggregationMode::Median(()),
                    SimpleDataType::SpotEntry(()),
                    Option::None(())
                );
            return output.price;
        }

        // Get total tokens held in strategy, whether in reserves or in positions.
        // 
        // # Returns
        // * `base_amount` - total base tokens owned
        // * `quote_amount` - total quote tokens owned
        // * `base_fees` - total base fees accrued
        // * `quote_fees` - total quote fees accrued
        fn get_token_amounts(self: @ContractState) -> (u256, u256, u256, u256) {
            // Fetch strategy state.
            let base_reserves = self.base_reserves.read();
            let quote_reserves = self.quote_reserves.read();
            let bid = self.bid.read();
            let ask = self.ask.read();

            // Fetch position info from market manager.
            let market_id = self.market_id.read();
            let market_manager = IMarketManagerDispatcher {
                contract_address: self.market_manager.read()
            };
            let market_state = market_manager.market_state(market_id);
            let market_info = market_manager.market_info(market_id);
            let contract = get_contract_address();
            let bid_position = market_manager
                .position(market_id, contract.into(), bid.lower_limit, bid.upper_limit);
            let ask_position = market_manager
                .position(market_id, contract.into(), ask.lower_limit, ask.upper_limit);

            // Calculate base and quote amounts inside strategy, either in reserves or in positions.
            let (bid_base, bid_quote, bid_base_fees, bid_quote_fees) =
                liquidity_math::amounts_inside_position(
                @market_state,
                market_info.width,
                @bid_position,
                market_manager.limit_info(market_id, bid.lower_limit),
                market_manager.limit_info(market_id, bid.upper_limit),
            );
            let (ask_base, ask_quote, ask_base_fees, ask_quote_fees) =
                liquidity_math::amounts_inside_position(
                @market_state,
                market_info.width,
                @ask_position,
                market_manager.limit_info(market_id, ask.lower_limit),
                market_manager.limit_info(market_id, ask.upper_limit),
            );

            // Return total amounts.
            let base_amount = base_reserves + bid_base + ask_base;
            let quote_amount = quote_reserves + bid_quote + ask_quote;
            let base_fees = bid_base_fees + ask_base_fees;
            let quote_fees = bid_quote_fees + ask_quote_fees;

            (base_amount, quote_amount, base_fees, quote_fees)
        }

        // Calculate new optimal positions.
        // 
        // Given reference price R: 
        // - Bid range position will be placed from R - S - Db to B - Db
        // - Ask range position will be placed from R + S + Da to B + Da
        // where: 
        //   S is the slippage parameter (controls how volume affects price)
        //   D is the delta parameter (controls how portfolio imbalance affects price)
        //
        // # Returns
        // * `bid` - new bid limit
        // * `ask` - new ask limit
        fn get_bid_ask(self: @ContractState) -> (u32, u32) {
            // Fetch strategy and market info.
            let strategy_params = self.strategy_params.read();
            let market_manager = IMarketManagerDispatcher {
                contract_address: self.market_manager.read()
            };
            let market_id = self.market_id.read();
            let market_info = market_manager.market_info(market_id);
            let curr_limit = market_manager.curr_limit(market_id);

            // Calculate new optimal price.
            let price: u256 = self.get_oracle_price().into() * self.scaling_factor.read();
            let limit = price_math::price_to_limit(price, market_info.width, false);

            // Calculate portfolio imbalance and delta.
            let (base_amount, quote_amount, base_fees, quote_fees) = self.get_token_amounts();
            let quote_amount_i256 = I256Trait::new(quote_amount + quote_fees, false);
            let base_amount_in_quote_i256 = I256Trait::new(
                math::mul_div(base_amount + base_fees, price, ONE, false), false
            );
            let delta_is_bid = base_amount_in_quote_i256 < quote_amount_i256;
            let imbalance_pct = math::mul_div(
                (base_amount_in_quote_i256 - quote_amount_i256).val,
                10000,
                (base_amount_in_quote_i256 + quote_amount_i256).val,
                false
            );
            let delta: u32 = math::mul_div(
                strategy_params.delta.into(), imbalance_pct, 10000, false
            )
                .try_into()
                .unwrap();

            // Calculate optimal bid and ask limits.
            let bid_spread = strategy_params.min_spread + if delta_is_bid {
                delta
            } else {
                0
            };
            let ask_spread = strategy_params.min_spread + if delta_is_bid {
                0
            } else {
                delta
            };
            let raw_bid_limit = if bid_spread > limit || curr_limit < market_info.width {
                0
            } else {
                min(limit - bid_spread, curr_limit - market_info.width)
            };
            let raw_ask_limit = min(
                max(limit + market_info.width + ask_spread, curr_limit + market_info.width),
                price_math::max_limit(market_info.width)
            );

            // At this point, bid and ask limits may not respect market width.
            let bid_limit = raw_bid_limit / market_info.width * market_info.width;
            let ask_limit = raw_ask_limit / market_info.width * market_info.width;

            (bid_limit, ask_limit)
        }


        // Initialise strategy. Only callable by contract owner.
        //
        // # Arguments
        // * `name` - name of strategy (also used as token name)
        // * `symbol` - symbol of strategy erc20 token
        // * `market_manager` - contract address of market manager
        // * `market_id` - market id
        // * `oracle` - contract address of oracle feed
        // * `base_currency_id` - base currency id for oracle
        // * `quote_currency_id` - quote currency id for oracle
        // * `scaling_factor` - conversion factor to convert oracle price to 28 decimals
        // * `min_spread` - minimum spread to between reference price and bid/ask price
        // * `slippage` - slippage parameter (width, in limits, of bid and ask liquidity positions)
        // * `delta` - delta parameter (additional single-sided spread based on portfolio imbalance)
        fn initialise(
            ref self: ContractState,
            name: felt252,
            symbol: felt252,
            market_manager: ContractAddress,
            market_id: felt252,
            oracle: ContractAddress,
            base_currency_id: felt252,
            quote_currency_id: felt252,
            scaling_factor: u256,
            min_spread: u32,
            slippage: u32,
            delta: u32,
        ) {
            self.assert_only_owner();
            assert(!self.is_initialised.read(), 'Initialised');

            let mut unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::InternalImpl::initializer(ref unsafe_state, name, symbol);

            self.market_manager.write(market_manager);
            self.market_id.write(market_id);
            self.oracle.write(oracle);
            self.oracle_params.write(OracleParams { base_currency_id, quote_currency_id });
            self.scaling_factor.write(scaling_factor);

            let market_manager_contract = IMarketManagerDispatcher {
                contract_address: market_manager
            };
            let width = market_manager_contract.market_info(market_id).width;
            assert(min_spread % width == 0 && slippage % width == 0, 'NotMultipleOfWidth');
            assert(slippage > 0, 'SlippageZero');
            self.strategy_params.write(StrategyParams { min_spread, slippage, delta });

            self.is_initialised.write(true);
            self
                .emit(
                    Event::ChangeOracle(
                        ChangeOracle { oracle, base_currency_id, quote_currency_id }
                    )
                );
            self.emit(Event::ChangeParams(ChangeParams { min_spread, slippage, delta }));
        }

        // Deposit initial liquidity to strategy and place first positions.
        //
        // # Arguments
        // * `base_amount` - base asset to deposit
        // * `quote_amount` - quote asset to deposit
        //
        // # Returns
        // * `base_amount` - base asset requested
        // * `quote_amount` - quote asset requested
        // * `shares` - pool shares minted in the form of liquidity, which is always denominated in base asset
        fn deposit_initial(
            ref self: ContractState, base_amount: u256, quote_amount: u256
        ) -> (u256, u256, u256) {
            // Run checks
            let unsafe_state = ERC20::unsafe_new_contract_state();
            let total_supply = ERC20::IERC20::total_supply(@unsafe_state);
            assert(total_supply == 0, 'UseDeposit');
            assert(base_amount != 0 && quote_amount != 0, 'AmountZero');
            assert(!self.is_paused.read(), 'Paused');
            assert(self.is_initialised.read(), 'NotInitialised');

            // Initialise state
            let market_id = self.market_id.read();
            let market_manager = IMarketManagerDispatcher {
                contract_address: self.market_manager.read()
            };
            let market_info = market_manager.market_info(market_id);
            let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
            let quote_token = IERC20Dispatcher { contract_address: market_info.quote_token };

            // Deposit tokens to reserves
            let caller = get_caller_address();
            let contract = get_contract_address();
            base_token.transfer_from(caller, contract, base_amount);
            quote_token.transfer_from(caller, contract, quote_amount);

            // Update reserves.
            let mut base_reserves = self.base_reserves.read();
            let mut quote_reserves = self.quote_reserves.read();
            base_reserves += base_amount;
            quote_reserves += quote_amount;
            self.base_reserves.write(base_reserves);
            self.quote_reserves.write(quote_reserves);

            // Approve max spend by market manager. Place initial positions.
            base_token.approve(market_manager.contract_address, BoundedU256::max());
            quote_token.approve(market_manager.contract_address, BoundedU256::max());
            let (bid, ask) = self._update_positions();

            // Deduct leftover to find amount deposited
            let base_leftover = self.base_reserves.read();
            let quote_leftover = self.quote_reserves.read();

            // Transfer leftover back to caller
            if base_leftover != 0 {
                assert(base_token.balance_of(contract) >= base_leftover, 'BaseLeftoverTransfer');
                base_token.transfer(caller, base_leftover);
                self.base_reserves.write(0);
            }
            if quote_leftover != 0 {
                assert(quote_token.balance_of(contract) >= quote_leftover, 'QuoteLeftoverTransfer');
                quote_token.transfer(caller, quote_leftover);
                self.quote_reserves.write(0);
            }

            // Mint liquidity
            let liquidity = bid.liquidity + ask.liquidity;
            let mut unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::InternalImpl::_mint(ref unsafe_state, caller, liquidity);

            assert(base_amount >= base_leftover, 'BaseLeftover');
            assert(quote_amount >= quote_leftover, 'QuoteLeftover');

            // Emit event
            self.emit(Event::Deposit(Deposit { owner: caller, base_amount, quote_amount }));

            (base_amount - base_leftover, quote_amount - quote_leftover, liquidity)
        }

        // Deposit liquidity to strategy.
        //
        // # Arguments
        // * `base_amount` - base asset to deposit
        // * `quote_amount` - quote asset to deposit
        //
        // # Returns
        // * `base_amount` - base asset requested
        // * `quote_amount` - quote asset requested
        // * `shares` - pool shares minted in the form of liquidity, which is always denominated in base asset
        fn deposit(
            ref self: ContractState, base_amount: u256, quote_amount: u256
        ) -> (u256, u256, u256) {
            // Run checks
            let mut unsafe_state = ERC20::unsafe_new_contract_state();
            let total_supply = ERC20::IERC20::total_supply(@unsafe_state);
            assert(total_supply != 0, 'UseDepositInitial');
            assert(base_amount != 0 || quote_amount != 0, 'AmountZero');
            assert(!self.is_paused.read(), 'Paused');

            // Fetch current market state
            let market_manager_addr = self.market_manager.read();
            let market_manager = IMarketManagerDispatcher { contract_address: market_manager_addr };
            let market_id = self.market_id.read();
            let market_state = market_manager.market_state(market_id);
            let market_info = market_manager.market_info(market_id);
            let mut base_reserves = self.base_reserves.read();
            let mut quote_reserves = self.quote_reserves.read();

            // Calculate token amounts (including accrued fees) in active positions
            let contract = get_contract_address();
            let bid = self.bid.read();
            let bid_position = market_manager
                .position(market_id, contract.into(), bid.lower_limit, bid.upper_limit);
            let (bid_base, bid_quote, bid_base_fees, bid_quote_fees) =
                liquidity_math::amounts_inside_position(
                @market_state,
                market_info.width,
                @bid_position,
                market_manager.limit_info(market_id, bid.lower_limit),
                market_manager.limit_info(market_id, bid.upper_limit),
            );

            let ask = self.ask.read();
            let ask_position = market_manager
                .position(market_id, contract.into(), ask.lower_limit, ask.upper_limit);
            let (ask_base, ask_quote, ask_base_fees, ask_quote_fees) =
                liquidity_math::amounts_inside_position(
                @market_state,
                market_info.width,
                @ask_position,
                market_manager.limit_info(market_id, ask.lower_limit),
                market_manager.limit_info(market_id, ask.upper_limit),
            );

            // Calculate liquidity minted.
            let total_base_reserves = base_reserves
                + bid_base
                + bid_base_fees
                + ask_base
                + ask_base_fees;
            let total_quote_reserves = quote_reserves
                + bid_quote
                + bid_quote_fees
                + ask_quote
                + ask_quote_fees;
            let base_deposit = min(
                base_amount,
                math::mul_div(quote_amount, total_base_reserves, total_quote_reserves, false)
            );
            let quote_deposit = min(
                quote_amount,
                math::mul_div(base_amount, total_quote_reserves, total_base_reserves, false)
            );

            let base_liquidity = liquidity_math::base_amount_to_liquidity(
                price_math::limit_to_sqrt_price(ask.lower_limit, market_info.width),
                price_math::limit_to_sqrt_price(ask.upper_limit, market_info.width),
                base_deposit
            );
            let quote_liquidity = liquidity_math::quote_amount_to_liquidity(
                price_math::limit_to_sqrt_price(bid.lower_limit, market_info.width),
                price_math::limit_to_sqrt_price(bid.upper_limit, market_info.width),
                quote_deposit
            );
            let liquidity = base_liquidity + quote_liquidity;

            // Transfer tokens into contract
            let caller = get_caller_address();
            if base_deposit != 0 {
                let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
                assert(base_token.balance_of(caller) >= base_deposit, 'DepositBase');
                base_token.transfer_from(caller, contract, base_deposit);
            }
            if quote_deposit != 0 {
                let quote_token = IERC20Dispatcher { contract_address: market_info.quote_token };
                assert(quote_token.balance_of(caller) >= quote_deposit, 'DepositQuote');
                quote_token.transfer_from(caller, contract, quote_deposit);
            }

            // Update reserves
            base_reserves += base_deposit;
            quote_reserves += quote_deposit;

            // Commit state updates.
            self.base_reserves.write(base_reserves);
            self.quote_reserves.write(quote_reserves);

            // Mint liquidity
            ERC20::InternalImpl::_mint(ref unsafe_state, caller, liquidity);

            // Emit event
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            owner: caller, base_amount: base_deposit, quote_amount: quote_deposit
                        }
                    )
                );

            (base_deposit, quote_deposit, liquidity)
        }

        // Burn pool shares and withdraw funds from strategy.
        //
        // # Arguments
        // * `shares` - pool shares to burn
        //
        // # Returns
        // * `base_amount` - base asset withdrawn
        // * `quote_amount` - quote asset withdrawn
        fn withdraw(ref self: ContractState, shares: u256) -> (u256, u256) {
            // Run checks
            let mut unsafe_state = ERC20::unsafe_new_contract_state();
            let total_supply = ERC20::IERC20::total_supply(@unsafe_state);
            assert(total_supply != 0, 'NoSupply');
            assert(shares != 0, 'SharesZero');
            assert(shares <= total_supply, 'SharesOverflow');
            let caller = get_caller_address();
            let caller_balance = ERC20::IERC20::balance_of(@unsafe_state, caller);
            assert(caller_balance >= shares, 'InsufficientShares');

            // Fetch current market state
            let market_id = self.market_id.read();
            let market_manager = IMarketManagerDispatcher {
                contract_address: self.market_manager.read()
            };
            let market_state = market_manager.market_state(market_id);
            let market_info = market_manager.market_info(market_id);
            let mut base_reserves = self.base_reserves.read();
            let mut quote_reserves = self.quote_reserves.read();

            // Calculate share of reserves to withdraw
            let mut base_withdraw = math::mul_div(base_reserves, shares, total_supply, false);
            let mut quote_withdraw = math::mul_div(quote_reserves, shares, total_supply, false);
            base_reserves -= base_withdraw;
            quote_reserves -= quote_withdraw;

            // Calculate share of position liquidity to withdraw.
            let mut bid = self.bid.read();
            let mut ask = self.ask.read();
            let bid_liquidity_delta = math::mul_div(bid.liquidity, shares, total_supply, false);
            bid.liquidity -= bid_liquidity_delta;
            let (bid_base_rem, bid_quote_rem, bid_base_fees, bid_quote_fees) = market_manager
                .modify_position(
                    market_id,
                    bid.lower_limit,
                    bid.upper_limit,
                    I256Trait::new(bid_liquidity_delta, true)
                );
            // Withdrawal includes all fees in position, not only those belonging to caller.
            let bid_base_fees_excess = math::mul_div(
                bid_base_fees, total_supply - shares, total_supply, true
            );
            let bid_quote_fees_excess = math::mul_div(
                bid_quote_fees, total_supply - shares, total_supply, true
            );

            let ask_liquidity_delta = math::mul_div(ask.liquidity, shares, total_supply, false);
            ask.liquidity -= ask_liquidity_delta;
            let (ask_base_rem, ask_quote_rem, ask_base_fees, ask_quote_fees) = market_manager
                .modify_position(
                    market_id,
                    ask.lower_limit,
                    ask.upper_limit,
                    I256Trait::new(ask_liquidity_delta, true)
                );
            let ask_base_fees_excess = math::mul_div(
                ask_base_fees, total_supply - shares, total_supply, true
            );
            let ask_quote_fees_excess = math::mul_div(
                ask_quote_fees, total_supply - shares, total_supply, true
            );

            base_withdraw += bid_base_rem.val
                + ask_base_rem.val
                - bid_base_fees_excess
                - ask_base_fees_excess;
            quote_withdraw += bid_quote_rem.val
                + ask_quote_rem.val
                - bid_quote_fees_excess
                - ask_quote_fees_excess;
            base_reserves += bid_base_fees_excess + ask_base_fees_excess;
            quote_reserves += bid_quote_fees_excess + ask_quote_fees_excess;

            // Burn shares
            ERC20::InternalImpl::_burn(ref unsafe_state, caller, shares);

            // Transfer tokens to caller
            let contract = get_contract_address();
            if base_withdraw != 0 {
                let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
                base_token.transfer(caller, base_withdraw);
            }
            if quote_withdraw != 0 {
                let quote_token = IERC20Dispatcher { contract_address: market_info.quote_token };
                quote_token.transfer(caller, quote_withdraw);
            }

            // Commit state updates
            self.base_reserves.write(base_reserves);
            self.quote_reserves.write(quote_reserves);
            self.bid.write(bid);
            self.ask.write(ask);

            // Emit event
            self
                .emit(
                    Event::Withdraw(
                        Withdraw {
                            owner: caller, base_amount: base_withdraw, quote_amount: quote_withdraw
                        }
                    )
                );

            (base_withdraw, quote_withdraw)
        }

        // Manually trigger contract to collect all outstanding positions and pause the contract.
        // Only callable by contract owner.
        fn collect_and_pause(ref self: ContractState) {
            self.assert_only_owner();
            assert(self.is_initialised.read(), 'NotInitialised');

            let market_manager = IMarketManagerDispatcher {
                contract_address: self.market_manager.read()
            };
            let market_id = self.market_id.read();
            let mut base_reserves = self.base_reserves.read();
            let mut quote_reserves = self.quote_reserves.read();
            let mut bid = self.bid.read();
            let mut ask = self.ask.read();

            if bid.liquidity != 0 {
                let (bid_base, bid_quote, _, _) = market_manager
                    .modify_position(
                        market_id,
                        bid.lower_limit,
                        bid.upper_limit,
                        I256Trait::new(bid.liquidity, true)
                    );
                base_reserves += bid_base.val;
                quote_reserves += bid_quote.val;
                bid = Default::default();
            }
            if ask.liquidity != 0 {
                let (ask_base, ask_quote, _, _) = market_manager
                    .modify_position(
                        market_id,
                        ask.lower_limit,
                        ask.upper_limit,
                        I256Trait::new(ask.liquidity, true)
                    );
                base_reserves += ask_base.val;
                quote_reserves += ask_quote.val;
                ask = Default::default();
            }

            // Commit state updates
            self.base_reserves.write(base_reserves);
            self.quote_reserves.write(quote_reserves);
            self.bid.write(bid);
            self.ask.write(ask);
            self.is_paused.write(true);

            self.emit(Event::Pause(Pause {}));
        }

        // Change the parameters of the strategy.
        //
        // # Arguments
        // * `min_spread` - minimum spread between reference price and bid/ask price
        // * `slippage` - slippage parameter (width, in limits, of bid and ask liquidity positions)
        // * `delta` - delta parameter (additional single-sided spread based on portfolio imbalance)
        fn change_strategy_params(
            ref self: ContractState, min_spread: u32, slippage: u32, delta: u32,
        ) {
            self.assert_only_owner();
            let market_manager_contract = IMarketManagerDispatcher {
                contract_address: self.market_manager.read()
            };
            let width = market_manager_contract.market_info(self.market_id.read()).width;
            assert(min_spread % width == 0 && slippage % width == 0, 'NotMultipleOfWidth');
            assert(slippage > 0, 'SlippageZero');
            self.strategy_params.write(StrategyParams { min_spread, slippage, delta });
        }

        // Change the oracle feed contract and / or pair id.
        //
        // # Arguments
        // * `oracle` - contract address of oracle feed
        // * `base_currency_id` - base currency id for oracle
        // * `quote_currency_id` - quote currency id for oracle
        fn change_oracle(
            ref self: ContractState,
            oracle: ContractAddress,
            base_currency_id: felt252,
            quote_currency_id: felt252
        ) {
            self.assert_only_owner();
            self.oracle.write(oracle);
            self.oracle_params.write({
                OracleParams { base_currency_id, quote_currency_id }
            });
            self
                .emit(
                    Event::ChangeOracle(
                        ChangeOracle { oracle, base_currency_id, quote_currency_id }
                    )
                );
        }

        // Change contract owner.
        //
        // # Arguments
        // * `owner` - new owner address
        fn set_owner(ref self: ContractState, owner: ContractAddress) {
            self.assert_only_owner();
            self.owner.write(owner);
            self.emit(Event::ChangeOwner(ChangeOwner { new_owner: owner }));
        }

        // Pause strategy.
        fn pause(ref self: ContractState) {
            self.assert_only_owner();
            self.is_paused.write(true);
            self.emit(Event::Pause(Pause {}));
        }

        // Unpause strategy.
        fn unpause(ref self: ContractState) {
            self.assert_only_owner();
            self.is_paused.write(false);
            self.emit(Event::Unpause(Unpause {}));
        }

        // Temporary function to allow upgrading while deployed on testnet.
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
    impl ERC20Impl of ERC20ABI<ContractState> {
        ////////////////////////////////
        // VIEW FUNCTIONS
        ////////////////////////////////

        fn name(self: @ContractState) -> felt252 {
            let unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::name(@unsafe_state)
        }

        fn symbol(self: @ContractState) -> felt252 {
            let unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::symbol(@unsafe_state)
        }

        fn decimals(self: @ContractState) -> u8 {
            let unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::decimals(@unsafe_state)
        }

        fn total_supply(self: @ContractState) -> u256 {
            let unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::total_supply(@unsafe_state)
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            let unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::balance_of(@unsafe_state, account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            let unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::allowance(@unsafe_state, owner, spender)
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let mut unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::transfer(ref unsafe_state, recipient, amount)
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let mut unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::transfer_from(ref unsafe_state, sender, recipient, amount)
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let mut unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::IERC20::approve(ref unsafe_state, spender, amount)
        }

        fn increase_allowance(
            ref self: ContractState, spender: ContractAddress, added_value: u256
        ) -> bool {
            let mut unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::increase_allowance(ref unsafe_state, spender, added_value)
        }

        fn decrease_allowance(
            ref self: ContractState, spender: ContractAddress, subtracted_value: u256
        ) -> bool {
            let mut unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::decrease_allowance(ref unsafe_state, spender, subtracted_value)
        }
    }

    ////////////////////////////////
    // INTERNAL FUNCTIONS
    ////////////////////////////////

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // Internal function to update for new optimal bid and ask positions.
        //
        // # Returns
        // * `bid` - new optimal bid position
        // * `ask` - new optimal ask position
        fn _update_positions(ref self: ContractState) -> (PositionInfo, PositionInfo) {
            // Fetch current market state
            let market_manager_addr = self.market_manager.read();
            let market_manager = IMarketManagerDispatcher { contract_address: market_manager_addr };
            let market_id = self.market_id.read();
            let market_info = market_manager.market_info(market_id);
            let market_state = market_manager.market_state(market_id);
            let curr_limit = market_manager.curr_limit(market_id);

            // Fetch strategy state
            let strategy_params = self.strategy_params.read();
            let mut base_reserves = self.base_reserves.read();
            let mut quote_reserves = self.quote_reserves.read();
            let mut bid = self.bid.read();
            let mut ask = self.ask.read();

            // Fetch new optimal bid and ask positions.
            let (next_bid_limit, next_ask_limit) = self.get_bid_ask();

            // Update positions.
            // If old positions exist at different price ranges, first remove them.
            if bid.liquidity != 0 && next_bid_limit != bid.upper_limit {
                let (base_amount, quote_amount, _, _) = market_manager
                    .modify_position(
                        market_id,
                        bid.lower_limit,
                        bid.upper_limit,
                        I256Trait::new(bid.liquidity, true)
                    );
                base_reserves += base_amount.val;
                quote_reserves += quote_amount.val;
                bid.liquidity = 0;
            }
            if ask.liquidity != 0 && next_ask_limit != ask.lower_limit {
                let (base_amount, quote_amount, _, _) = market_manager
                    .modify_position(
                        market_id,
                        ask.lower_limit,
                        ask.upper_limit,
                        I256Trait::new(ask.liquidity, true)
                    );
                base_reserves += base_amount.val;
                quote_reserves += quote_amount.val;
                ask.liquidity = 0;
            }

            // Calculate amount of new liquidity to add.
            if next_bid_limit < strategy_params.slippage {
                bid = Default::default();
            } else if quote_reserves != 0 {
                let lower_limit = next_bid_limit - strategy_params.slippage;
                let liquidity_delta = liquidity_math::quote_amount_to_liquidity(
                    price_math::limit_to_sqrt_price(lower_limit, market_info.width),
                    price_math::limit_to_sqrt_price(next_bid_limit, market_info.width),
                    quote_reserves
                );
                let (_, quote_amount, _, _) = market_manager
                    .modify_position(
                        market_id,
                        lower_limit,
                        next_bid_limit,
                        I256Trait::new(liquidity_delta, false)
                    );
                quote_reserves -= quote_amount.val;
                bid.lower_limit = lower_limit;
                bid.upper_limit = next_bid_limit;
                bid.liquidity += liquidity_delta;
            };
            if next_ask_limit
                + strategy_params.slippage > price_math::max_limit(market_info.width) {
                bid = Default::default();
            } else if base_reserves != 0 {
                let upper_limit = next_ask_limit + strategy_params.slippage;
                let liquidity_delta = liquidity_math::base_amount_to_liquidity(
                    price_math::limit_to_sqrt_price(next_ask_limit, market_info.width),
                    price_math::limit_to_sqrt_price(upper_limit, market_info.width),
                    base_reserves
                );
                let (base_amount, _, _, _) = market_manager
                    .modify_position(
                        market_id,
                        next_ask_limit,
                        upper_limit,
                        I256Trait::new(liquidity_delta, false)
                    );
                base_reserves -= base_amount.val;
                ask.lower_limit = next_ask_limit;
                ask.upper_limit = upper_limit;
                ask.liquidity += liquidity_delta;
            }

            // Commit state updates
            self.base_reserves.write(base_reserves);
            self.quote_reserves.write(quote_reserves);
            self.bid.write(bid);
            self.ask.write(ask);
            
            if next_bid_limit != bid.upper_limit || next_ask_limit != ask.lower_limit {
                self
                    .emit(
                        Event::UpdatePositions(
                            UpdatePositions {
                                bid_lower_limit: bid.lower_limit,
                                bid_upper_limit: bid.upper_limit,
                                bid_liquidity: bid.liquidity,
                                ask_lower_limit: ask.lower_limit,
                                ask_upper_limit: ask.upper_limit,
                                ask_liquidity: ask.liquidity,
                            }
                        )
                    );
            }

            (bid, ask)
        }
    }
}
