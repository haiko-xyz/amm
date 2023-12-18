#[starknet::contract]
mod ReplicatingStrategy {
    // Core lib imports.
    use core::traits::TryInto;
    use integer::BoundedU256;
    use cmp::{min, max};
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::info::{
        get_caller_address, get_contract_address, get_block_number, get_block_timestamp
    };
    use starknet::class_hash::ClassHash;
    use starknet::replace_class_syscall;

    // Local imports.
    use amm::contracts::market_manager::MarketManager;
    use amm::contracts::market_manager::MarketManager::ContractState as MMContractState;
    use amm::types::core::{MarketState, SwapParams, PositionInfo};
    use amm::libraries::{
        id, math::{math, price_math, liquidity_math, fee_math},
        constants::{ONE, LOG2_1_00001, MAX_FEE_RATE},
    };
    use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
    use amm::interfaces::IStrategy::IStrategy;
    use amm::types::i128::{I128Trait, i128};
    use strategies::strategies::replicating::{
        spread_math, interface::IReplicatingStrategy,
        types::{StrategyParams, OracleParams, StrategyState},
        pragma::{
            IOracleABIDispatcher, IOracleABIDispatcherTrait, AggregationMode, DataType,
            SimpleDataType, PragmaPricesResponse, ISummaryStatsABIDispatcher,
            ISummaryStatsABIDispatcherTrait
        },
    };

    // External imports.
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    ////////////////////////////////
    // STORAGE
    ///////////////////////////////

    #[storage]
    struct Storage {
        // OWNABLE
        // contract owner
        owner: ContractAddress,
        // queued contract owner (for ownership transfers)
        queued_owner: ContractAddress,
        // IMMUTABLES
        // strategy name
        name: felt252,
        // strategy symbol (for short representation)
        symbol: felt252,
        // strategy version
        version: felt252,
        // market manager
        market_manager: IMarketManagerDispatcher,
        // oracle for price and volatility feeds
        oracle: IOracleABIDispatcher,
        // oracle summary stats contract
        oracle_summary: ISummaryStatsABIDispatcher,
        // STRATEGY
        // Indexed by market id
        strategy_owner: LegacyMap::<felt252, ContractAddress>,
        // Indexed by market id
        queued_strategy_owner: LegacyMap::<felt252, ContractAddress>,
        // Indexed by market id
        strategy_params: LegacyMap::<felt252, StrategyParams>,
        // Indexed by market id
        oracle_params: LegacyMap::<felt252, OracleParams>,
        // Indexed by market id
        strategy_state: LegacyMap::<felt252, StrategyState>,
        // Indexed by market id
        total_deposits: LegacyMap::<felt252, u256>,
        // Indexed by (market_id: felt252, depositor: ContractAddress)
        user_deposits: LegacyMap::<(felt252, ContractAddress), u256>,
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AddMarket: AddMarket,
        Deposit: Deposit,
        Withdraw: Withdraw,
        UpdatePositions: UpdatePositions,
        SetStrategyParams: SetStrategyParams,
        SetOracleParams: SetOracleParams,
        ChangeOwner: ChangeOwner,
        ChangeStrategyOwner: ChangeStrategyOwner,
        ChangeOracle: ChangeOracle,
        Pause: Pause,
        Unpause: Unpause,
    }

    #[derive(Drop, starknet::Event)]
    struct AddMarket {
        market_id: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        caller: ContractAddress,
        market_id: felt252,
        base_amount: u256,
        quote_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        caller: ContractAddress,
        market_id: felt252,
        base_amount: u256,
        quote_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct UpdatePositions {
        market_id: felt252,
        bid_lower_limit: u32,
        bid_upper_limit: u32,
        bid_liquidity: u128,
        ask_lower_limit: u32,
        ask_upper_limit: u32,
        ask_liquidity: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct SetStrategyParams {
        market_id: felt252,
        min_spread: u32,
        range: u32,
        max_delta: u32,
        allow_deposits: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct SetOracleParams {
        market_id: felt252,
        base_currency_id: felt252,
        quote_currency_id: felt252,
        pair_id: felt252,
        min_sources: u32,
        max_age: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct ChangeOracle {
        oracle: ContractAddress,
        oracle_summary: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct ChangeOwner {
        old: ContractAddress,
        new: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct ChangeStrategyOwner {
        old: ContractAddress,
        new: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct Pause {
        market_id: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct Unpause {
        market_id: felt252,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        name: felt252,
        symbol: felt252,
        version: felt252,
        market_manager: ContractAddress,
        oracle: ContractAddress,
        oracle_summary: ContractAddress,
    ) {
        self.owner.write(owner);
        self.name.write(name);
        self.symbol.write(symbol);
        self.version.write(version);
        let manager_dispatcher = IMarketManagerDispatcher { contract_address: market_manager };
        self.market_manager.write(manager_dispatcher);
        let oracle_dispatcher = IOracleABIDispatcher { contract_address: oracle };
        self.oracle.write(oracle_dispatcher);
        let oracle_summary_dispatcher = ISummaryStatsABIDispatcher {
            contract_address: oracle_summary
        };
        self.oracle_summary.write(oracle_summary_dispatcher);
    }

    ////////////////////////////////
    // FUNCTIONS
    ////////////////////////////////

    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn assert_owner(self: @ContractState) {
            assert(self.owner.read() == get_caller_address(), 'OnlyOwner');
        }

        fn assert_strategy_owner(self: @ContractState, market_id: felt252) {
            assert(
                self.strategy_owner.read(market_id) == get_caller_address(), 'OnlyStrategyOwner'
            );
        }
    }

    #[external(v0)]
    impl Strategy of IStrategy<ContractState> {
        // Get market manager contract address.
        fn market_manager(self: @ContractState) -> ContractAddress {
            self.market_manager.read().contract_address
        }

        // Get strategy name.
        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }

        // Get strategy symbol.
        fn symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }

        // Get strategy version.
        fn version(self: @ContractState) -> felt252 {
            self.version.read()
        }

        // Get list of positions currently placed by strategy.
        //
        // # Returns
        // * `positions` - list of positions
        fn placed_positions(self: @ContractState, market_id: felt252) -> Span<PositionInfo> {
            let state = self.strategy_state.read(market_id);
            array![state.bid, state.ask].span()
        }

        // Get list of positions queued to be placed by strategy on next `swap` update. If no updates
        // are queued, the returned list will match the list returned by `placed_positions`.
        // 
        // # Returns
        // * `positions` - list of positions
        fn queued_positions(self: @ContractState, market_id: felt252) -> Span<PositionInfo> {
            // Fetch market info.
            let market_manager = self.market_manager.read();
            let market_info = market_manager.market_info(market_id);

            // Fetch strategy info.
            let params = self.strategy_params.read(market_id);
            let state = self.strategy_state.read(market_id);
            let bid = state.bid;
            let ask = state.ask;

            // Fetch amounts in existing position.
            let contract: felt252 = get_contract_address().into();
            let bid_pos_id = id::position_id(market_id, contract, bid.lower_limit, bid.upper_limit);
            let ask_pos_id = id::position_id(market_id, contract, ask.lower_limit, ask.upper_limit);
            let (bid_base, bid_quote) = market_manager.amounts_inside_position(bid_pos_id);
            let (ask_base, ask_quote) = market_manager.amounts_inside_position(ask_pos_id);

            // Fetch new optimal bid and ask positions.
            let (next_bid_lower, next_bid_upper, next_ask_lower, next_ask_upper) = self
                .get_bid_ask(market_id);

            // Calculate amount of new liquidity to add.
            // Token amounts rounded down as per convention when depositing liquidity.
            let base_amount = state.base_reserves + bid_base + ask_base;
            let base_liquidity = if base_amount == 0 || next_ask_lower == 0 || next_ask_upper == 0 {
                0
            } else {
                liquidity_math::base_to_liquidity(
                    price_math::limit_to_sqrt_price(next_ask_lower, market_info.width),
                    price_math::limit_to_sqrt_price(next_ask_upper, market_info.width),
                    base_amount,
                    false
                )
            };
            let quote_amount = state.quote_reserves + bid_quote + ask_quote;
            let quote_liquidity = if quote_amount == 0
                || next_bid_lower == 0
                || next_bid_upper == 0 {
                0
            } else {
                liquidity_math::quote_to_liquidity(
                    price_math::limit_to_sqrt_price(next_bid_lower, market_info.width),
                    price_math::limit_to_sqrt_price(next_bid_upper, market_info.width),
                    quote_amount,
                    false
                )
            };

            // Return new positions.
            let next_bid = PositionInfo {
                lower_limit: next_bid_lower,
                upper_limit: next_bid_upper,
                liquidity: quote_liquidity,
            };
            let next_ask = PositionInfo {
                lower_limit: next_ask_lower, upper_limit: next_ask_upper, liquidity: base_liquidity,
            };
            array![next_bid, next_ask].span()
        }

        // Called by `MarketManager` before swap to replace `placed_positions` with `queued_positions`.
        // If the two are identical, no positions will be updated.
        fn update_positions(ref self: ContractState, market_id: felt252, params: SwapParams) {
            // Run checks
            let market_manager = self.market_manager.read();
            assert(get_caller_address() == market_manager.contract_address, 'OnlyMarketManager');
            let state = self.strategy_state.read(market_id);
            assert(state.is_initialised, 'NotInitialised');
            if state.is_paused {
                return ();
            }

            // Fetch oracle price.
            // If oracle price is invalid, collect positions and pause strategy. Return early.
            let (price, is_valid) = self.get_oracle_price(market_id);
            if !is_valid {
                self._collect_and_pause(market_id);
                return;
            }

            // Fetch strategy info.
            let width = market_manager.width(market_id);
            let curr_limit = market_manager.curr_limit(market_id);
            let oracle_limit = price_math::price_to_limit(price, width, true);

            // Run rebalancing condition. 
            // If expected LVR from filling the swap at current price is lower than expected fees, 
            // then do not update position. We evaluate LVR at the inside quote to simplify calculations.
            // The inside quote is:
            //   - For buys:
            //      - max(curr price, ask lower price) if curr price > bid upper price
            //      - max(curr price, bid lower price) if curr price <= bid upper price
            //   - For sells:
            //      - min(curr price, bid upper price) if curr price < ask lower price
            //      - min(curr price, ask upper price) if curr price < ask lower price
            // LVR is calculated as:
            //   - (oracle price / inside quote - 1) * amount if buying
            //   - (inside quote / oracle price - 1) * amount if selling
            // We rebalance only if LVR is greater than expected fees.
            let fee_rate = market_manager.swap_fee_rate(market_id);
            let fee_rate_scaled = math::mul_div(fee_rate.into(), ONE, MAX_FEE_RATE.into(), false);
            let log2: u256 = price_math::_log2(ONE + fee_rate_scaled);
            let threshold_limits: u32 = (log2 / LOG2_1_00001).try_into().unwrap();
            let rebalance = if params.is_buy {
                let exec_price = if curr_limit > state.bid.upper_limit {
                    max(curr_limit, state.ask.lower_limit)
                } else {
                    max(curr_limit, state.bid.lower_limit)
                };
                oracle_limit > exec_price + threshold_limits
            } else {
                let exec_price = if curr_limit < state.ask.lower_limit {
                    min(curr_limit, state.bid.upper_limit)
                } else {
                    min(curr_limit, state.ask.upper_limit)
                };
                exec_price > oracle_limit + threshold_limits
            };
            if rebalance {
                self._update_positions(market_id);
            }
        }
    }

    #[external(v0)]
    impl ReplicatingStrategy of IReplicatingStrategy<ContractState> {
        // Contract owner
        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        // Queued contract owner, used for ownership transfers
        fn queued_owner(self: @ContractState) -> ContractAddress {
            self.queued_owner.read()
        }

        // Strategy owner
        fn strategy_owner(self: @ContractState, market_id: felt252) -> ContractAddress {
            self.strategy_owner.read(market_id)
        }
        // Queued strategy owner, used for ownership transfers
        fn queued_strategy_owner(self: @ContractState, market_id: felt252) -> ContractAddress {
            self.queued_strategy_owner.read(market_id)
        }

        // Strategy parameters
        fn strategy_params(self: @ContractState, market_id: felt252) -> StrategyParams {
            self.strategy_params.read(market_id)
        }

        // Strategy state
        fn strategy_state(self: @ContractState, market_id: felt252) -> StrategyState {
            self.strategy_state.read(market_id)
        }

        // Whether strategy is paused
        fn is_paused(self: @ContractState, market_id: felt252) -> bool {
            self.strategy_state.read(market_id).is_paused
        }

        // Contract address of oracle feed.
        fn oracle(self: @ContractState) -> ContractAddress {
            self.oracle.read().contract_address
        }

        // Bid position of strategy
        fn bid(self: @ContractState, market_id: felt252) -> PositionInfo {
            self.strategy_state.read(market_id).bid
        }

        // Ask position of strategy
        fn ask(self: @ContractState, market_id: felt252) -> PositionInfo {
            self.strategy_state.read(market_id).ask
        }

        // Base reserves of strategy
        fn base_reserves(self: @ContractState, market_id: felt252) -> u256 {
            self.strategy_state.read(market_id).base_reserves
        }

        // Quote reserves of strategy
        fn quote_reserves(self: @ContractState, market_id: felt252) -> u256 {
            self.strategy_state.read(market_id).quote_reserves
        }

        // Get user deposits for a given market.
        fn user_deposits(self: @ContractState, market_id: felt252, owner: ContractAddress) -> u256 {
            self.user_deposits.read((market_id, owner))
        }

        // Get total deposits for a given market.
        fn total_deposits(self: @ContractState, market_id: felt252) -> u256 {
            self.total_deposits.read(market_id)
        }

        // Get price from oracle feed.
        // 
        // # Returns
        // * `price` - oracle price
        // * `is_valid` - whether oracle price passes validity checks re number of sources and age
        fn get_oracle_price(self: @ContractState, market_id: felt252) -> (u256, bool) {
            // Get oracle parameters.
            let oracle = self.oracle.read();
            let oracle_params = self.oracle_params.read(market_id);

            // Fetch oracle price.
            let output: PragmaPricesResponse = oracle
                .get_data_with_USD_hop(
                    oracle_params.base_currency_id,
                    oracle_params.quote_currency_id,
                    AggregationMode::Median(()),
                    SimpleDataType::SpotEntry(()),
                    Option::None(())
                );

            // Validate number of sources and age of oracle price.
            // If either is invalid, collect positions and pause strategy.
            let now = get_block_timestamp();
            let is_valid = (output.num_sources_aggregated >= oracle_params.min_sources)
                && (output.last_updated_timestamp + oracle_params.max_age >= now);

            // Calculate and return scaled price.
            let scaling_factor = math::pow(10, 28 - output.decimals.into());
            (output.price.into() * scaling_factor, is_valid)
        }

        // Get volatility from oracle feed.
        // Note: checkpoints are not currently set by Pragma, so this will fail if called.
        // For now, use fixed strategy params rather than variable ones.
        // 
        // # Arguments
        // * `market_id` - market id
        // 
        // # Returns
        // * `volatility` - oracle volatility
        // fn get_oracle_vol(self: @ContractState, market_id: felt252) -> u256 {
        //     let oracle_params = self.oracle_params.read(market_id);
        //     let strategy_params = self.strategy_params.read(market_id);
        //     let num_samples = 200; // limited by Starknet computation
        //     let now = get_block_timestamp();
        //     let start_tick = now - strategy_params.vol_period;
        //     let end_tick = now;
        //     let data_type = DataType::SpotEntry(oracle_params.pair_id);
        //     let aggregation_mode = AggregationMode::Median(());

        //     let oracle_summary = self.oracle_summary.read();
        //     let (volatility, decimals) = oracle_summary
        //         .calculate_volatility(
        //             data_type, start_tick, end_tick, num_samples, aggregation_mode
        //         );

        //     let scaling_factor = math::pow(10, 28 - decimals.into());
        //     volatility.into() * scaling_factor
        // }

        // Get total tokens held in strategy, whether in reserves or in positions.
        // 
        // # Arguments
        // * `market_id` - market id
        //
        // # Returns
        // * `base_amount` - total base tokens owned
        // * `quote_amount` - total quote tokens owned
        fn get_balances(self: @ContractState, market_id: felt252) -> (u256, u256) {
            // Fetch strategy state.
            let state = self.strategy_state.read(market_id);
            let bid = state.bid;
            let ask = state.ask;

            // Fetch position info from market manager.
            let market_manager = self.market_manager.read();
            let contract: felt252 = get_contract_address().into();
            let bid_pos_id = id::position_id(market_id, contract, bid.lower_limit, bid.upper_limit);
            let ask_pos_id = id::position_id(market_id, contract, ask.lower_limit, ask.upper_limit);

            // Calculate base and quote amounts inside strategy, either in reserves or in positions.
            let (bid_base, bid_quote) = market_manager.amounts_inside_position(bid_pos_id);
            let (ask_base, ask_quote) = market_manager.amounts_inside_position(ask_pos_id);

            // Return total amounts.
            let base_amount = state.base_reserves + bid_base + ask_base;
            let quote_amount = state.quote_reserves + bid_quote + ask_quote;

            (base_amount, quote_amount)
        }

        // Calculate new optimal positions.
        // 
        // Given reference price R: 
        // - Bid range position will be placed from P - R - Db to B - Db
        // - Ask range position will be placed from P + R + Da to B + Da
        // where: 
        //   P is the 
        //   R is the range parameter (controls how volume affects price)
        //   D is the inv_delta parameter (controls how portfolio imbalance affects price)
        //
        // # Returns
        // * `bid_lower` - new bid lower limit
        // * `bid_upper` - new bid upper limit
        // * `ask_lower` - new ask lower limit
        // * `ask_upper` - new ask upper limit
        fn get_bid_ask(self: @ContractState, market_id: felt252) -> (u32, u32, u32, u32) {
            // Fetch strategy and market info.
            let params = self.strategy_params.read(market_id);
            let market_manager = self.market_manager.read();
            let width = market_manager.width(market_id);
            let curr_limit = market_manager.curr_limit(market_id);

            // Calculate new optimal price.
            let (price, is_valid) = self.get_oracle_price(market_id);

            // If oracle price is invalid, return null positions.
            if !is_valid {
                return (0, 0, 0, 0);
            }

            // Calculate new bid and ask limits.
            let limit = price_math::price_to_limit(price, width, false);
            let (base_amount, quote_amount) = self.get_balances(market_id);
            let inv_delta = spread_math::delta_spread(
                params.max_delta, base_amount, quote_amount, price
            );
            spread_math::calc_bid_ask(
                curr_limit, limit, params.min_spread, params.range, inv_delta, width
            )
        }

        // Initialise strategy for market.
        // At the moment, only callable by contract owner to prevent unwanted claiming of strategies. 
        //
        // # Arguments
        // * `market_id` - market id
        // * `owner` - nominated owner for strategy
        // * `base_currency_id` - base currency id for oracle
        // * `quote_currency_id` - quote currency id for oracle
        // * `pair_id` - pair id for oracle
        // * `min_sources` - minimum number of sources required for oracle price (automatically paused if fails)
        // * `max_age` - maximum age of oracle price in seconds (automatically paused if fails)
        // * `min_spread` - minimum spread to between reference price and bid/ask price
        // * `range` - range parameter (width, in limits, of bid and ask liquidity positions)
        // * `max_delta` - max inv_delta parameter (additional single-sided spread based on portfolio imbalance)
        // * `allow_deposits` - whether deposits are allowed
        fn add_market(
            ref self: ContractState,
            market_id: felt252,
            owner: ContractAddress,
            base_currency_id: felt252,
            quote_currency_id: felt252,
            pair_id: felt252,
            min_sources: u32,
            max_age: u64,
            min_spread: u32,
            range: u32,
            max_delta: u32,
            allow_deposits: bool,
        ) {
            // Run checks.
            self.assert_owner();
            let state = self.strategy_state.read(market_id);
            assert(!state.is_initialised, 'Initialised');
            assert(range > 0, 'RangeZero');

            // Set strategy owner.
            self.strategy_owner.write(market_id, get_caller_address());

            // Set strategy params.
            let strategy_params = StrategyParams { min_spread, range, max_delta, allow_deposits };
            self.strategy_params.write(market_id, strategy_params);

            // Set oracle params.
            let oracle_params = OracleParams {
                base_currency_id, quote_currency_id, pair_id, min_sources, max_age
            };
            self.oracle_params.write(market_id, oracle_params);

            // Initialise strategy state.
            let mut state: StrategyState = Default::default();
            state.is_initialised = true;
            self.strategy_state.write(market_id, state);

            // Emit events.
            self.emit(Event::AddMarket(AddMarket { market_id }));

            self
                .emit(
                    Event::SetOracleParams(
                        SetOracleParams {
                            market_id,
                            base_currency_id,
                            quote_currency_id,
                            pair_id,
                            min_sources,
                            max_age
                        }
                    )
                );
            self
                .emit(
                    Event::SetStrategyParams(
                        SetStrategyParams {
                            market_id, min_spread, range, max_delta, allow_deposits
                        }
                    )
                );
        }

        // Deposit initial liquidity to strategy and place first positions.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_amount` - base asset to deposit
        // * `quote_amount` - quote asset to deposit
        //
        // # Returns
        // * `shares` - pool shares minted in the form of liquidity
        fn deposit_initial(
            ref self: ContractState, market_id: felt252, base_amount: u256, quote_amount: u256
        ) -> u256 {
            // Run checks
            assert(self.total_deposits.read(market_id) == 0, 'UseDeposit');
            assert(base_amount != 0 && quote_amount != 0, 'AmountZero');
            let mut state = self.strategy_state.read(market_id);
            assert(!state.is_paused, 'Paused');
            assert(state.is_initialised, 'NotInitialised');
            let params = self.strategy_params.read(market_id);
            // If deposits are disabled, only the strategy owner can deposit.
            let caller = get_caller_address();
            if caller != self.strategy_owner.read(market_id) {
                assert(params.allow_deposits, 'DepositDisabled');
            }

            // Initialise state
            let market_manager = self.market_manager.read();
            let market_info = market_manager.market_info(market_id);
            let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
            let quote_token = IERC20Dispatcher { contract_address: market_info.quote_token };

            // Deposit tokens to reserves
            let contract = get_contract_address();
            base_token.transfer_from(caller, contract, base_amount);
            quote_token.transfer_from(caller, contract, quote_amount);

            // Update reserves.
            state.base_reserves += base_amount;
            state.quote_reserves += quote_amount;
            self.strategy_state.write(market_id, state);

            // Approve max spend by market manager. Place initial positions.
            base_token.approve(market_manager.contract_address, BoundedU256::max());
            quote_token.approve(market_manager.contract_address, BoundedU256::max());
            let (bid, ask) = self._update_positions(market_id);

            // Check that both positions are placed. If neither position is placed, for example if the
            // oracle price is invalid, this will cause `deposit` to fail. Further, if the oracle price
            // is too high or low, only single-sided liquidity may be placed. This is extremely unlikely
            // and would cause severe portfolio skew, so we simply revert the transaction.
            assert(bid.liquidity != 0 && ask.liquidity != 0, 'DepositInitialZero');

            // Refetch strategy state after placing positions to find shares.
            state = self.strategy_state.read(market_id);

            // Mint liquidity
            let shares: u256 = (state.bid.liquidity + state.ask.liquidity).into();
            self.user_deposits.write((market_id, caller), shares);
            self.total_deposits.write(market_id, shares);

            // Emit event
            self.emit(Event::Deposit(Deposit { market_id, caller, base_amount, quote_amount }));

            shares
        }

        // Deposit liquidity to strategy.
        //
        // # Arguments
        // * `base_amount` - base asset desired
        // * `quote_amount` - quote asset desired
        //
        // # Returns
        // * `base_amount` - base asset deposited
        // * `quote_amount` - quote asset deposited
        // * `shares` - pool shares minted
        fn deposit(
            ref self: ContractState, market_id: felt252, base_amount: u256, quote_amount: u256
        ) -> (u256, u256, u256) {
            // Run checks.
            let total_deposits = self.total_deposits.read(market_id);
            assert(total_deposits != 0, 'UseDepositInitial');
            assert(base_amount != 0 || quote_amount != 0, 'AmountZero');
            let mut state = self.strategy_state.read(market_id);
            assert(!state.is_paused, 'Paused');
            let params = self.strategy_params.read(market_id);
            // If deposits are disabled, only the strategy owner can deposit.
            let caller = get_caller_address();
            if caller != self.strategy_owner.read(market_id) {
                assert(params.allow_deposits, 'DepositDisabled');
            }

            // Fetch market info and strategy state.
            let market_manager = self.market_manager.read();
            let market_info = market_manager.market_info(market_id);
            let (base_balance, quote_balance) = self.get_balances(market_id);

            // Calculate shares to mint.
            let base_deposit = if quote_amount == 0 || quote_balance == 0 {
                base_amount
            } else {
                min(base_amount, math::mul_div(quote_amount, base_balance, quote_balance, false))
            };
            let quote_deposit = if base_amount == 0 || base_balance == 0 {
                quote_amount
            } else {
                min(quote_amount, math::mul_div(base_amount, quote_balance, base_balance, false))
            };
            let shares = if base_balance == 0 {
                math::mul_div(total_deposits, quote_deposit, quote_balance, false)
            } else {
                math::mul_div(total_deposits, base_deposit, base_balance, false)
            };

            // Transfer tokens into contract.
            let contract = get_contract_address();
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

            // Update reserves.
            state.base_reserves += base_deposit;
            state.quote_reserves += quote_deposit;
            self.strategy_state.write(market_id, state);

            // Update deposits.
            let user_deposits = self.user_deposits.read((market_id, caller));
            self.user_deposits.write((market_id, caller), user_deposits + shares);
            self.total_deposits.write(market_id, total_deposits + shares);

            // Emit event.
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            market_id,
                            caller,
                            base_amount: base_deposit,
                            quote_amount: quote_deposit
                        }
                    )
                );

            (base_deposit, quote_deposit, shares)
        }

        // Burn pool shares and withdraw funds from strategy.
        //
        // # Arguments
        // * `shares` - pool shares to burn
        //
        // # Returns
        // * `base_amount` - base asset withdrawn
        // * `quote_amount` - quote asset withdrawn
        fn withdraw(ref self: ContractState, market_id: felt252, shares: u256) -> (u256, u256) {
            // Run checks
            let total_deposits = self.total_deposits.read(market_id);
            assert(total_deposits != 0, 'NoSupply');
            assert(shares != 0, 'SharesZero');
            assert(shares <= total_deposits, 'SharesOF');
            let caller = get_caller_address();
            let user_deposits = self.user_deposits.read((market_id, caller));
            assert(user_deposits >= shares, 'InsuffShares');

            // Fetch current market state
            let market_manager = self.market_manager.read();
            let market_state = market_manager.market_state(market_id);
            let market_info = market_manager.market_info(market_id);
            let mut state = self.strategy_state.read(market_id);

            // Calculate share of reserves to withdraw
            let mut base_withdraw = math::mul_div(
                state.base_reserves, shares, total_deposits, false
            );
            let mut quote_withdraw = math::mul_div(
                state.quote_reserves, shares, total_deposits, false
            );
            state.base_reserves -= base_withdraw;
            state.quote_reserves -= quote_withdraw;

            // Calculate share of position liquidity to withdraw.
            let bid_liquidity_delta = math::mul_div(
                state.bid.liquidity.into(), shares, total_deposits, false
            );
            let bid_delta_i128 = bid_liquidity_delta.try_into().expect('BidLiqOF');
            state.bid.liquidity -= bid_delta_i128;
            let (bid_base_rem, bid_quote_rem, bid_base_fees, bid_quote_fees) = market_manager
                .modify_position(
                    market_id,
                    state.bid.lower_limit,
                    state.bid.upper_limit,
                    I128Trait::new(bid_delta_i128, true)
                );
            let ask_liquidity_delta = math::mul_div(
                state.ask.liquidity.into(), shares, total_deposits, false
            );
            let ask_delta_i128 = ask_liquidity_delta.try_into().expect('AskLiqOF');
            state.ask.liquidity -= ask_delta_i128;
            let (ask_base_rem, ask_quote_rem, ask_base_fees, ask_quote_fees) = market_manager
                .modify_position(
                    market_id,
                    state.ask.lower_limit,
                    state.ask.upper_limit,
                    I128Trait::new(ask_delta_i128, true)
                );

            // Withdrawal includes all fees in position, not only those belonging to caller.
            let base_fees_excess = math::mul_div(
                bid_base_fees + ask_base_fees, total_deposits - shares, total_deposits, true
            );
            let quote_fees_excess = math::mul_div(
                bid_quote_fees + ask_quote_fees, total_deposits - shares, total_deposits, true
            );
            base_withdraw += bid_base_rem.val + ask_base_rem.val - base_fees_excess;
            quote_withdraw += bid_quote_rem.val + ask_quote_rem.val - quote_fees_excess;
            state.base_reserves += base_fees_excess;
            state.quote_reserves += quote_fees_excess;

            // Burn shares.
            self.user_deposits.write((market_id, caller), user_deposits - shares);
            self.total_deposits.write(market_id, total_deposits - shares);

            // Transfer tokens to caller.
            let contract = get_contract_address();
            if base_withdraw != 0 {
                let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
                base_token.transfer(caller, base_withdraw);
            }
            if quote_withdraw != 0 {
                let quote_token = IERC20Dispatcher { contract_address: market_info.quote_token };
                quote_token.transfer(caller, quote_withdraw);
            }

            // Commit state updates.
            self.strategy_state.write(market_id, state);

            // Emit event.
            self
                .emit(
                    Event::Withdraw(
                        Withdraw {
                            market_id,
                            caller,
                            base_amount: base_withdraw,
                            quote_amount: quote_withdraw
                        }
                    )
                );

            // Return withdrawn amounts.
            (base_withdraw, quote_withdraw)
        }

        // Manually trigger contract to collect all outstanding positions and pause the contract.
        // Only callable by strategy owner.
        fn collect_and_pause(ref self: ContractState, market_id: felt252) {
            self.assert_strategy_owner(market_id);
            self._collect_and_pause(market_id);
        }

        // Change the parameters of the strategy.
        //
        // # Arguments
        // * `min_spread` - minimum spread between reference price and bid/ask price
        // * `range` - range parameter (width, in limits, of bid and ask liquidity positions)
        // * `max_delta` - max inv_delta parameter (additional single-sided spread based on portfolio imbalance)
        // * `allow_deposits` - whether deposits are allowed
        fn set_params(ref self: ContractState, market_id: felt252, params: StrategyParams) {
            self.assert_strategy_owner(market_id);
            let market_manager = self.market_manager.read();
            let width = market_manager.width(market_id);
            let old_params = self.strategy_params.read(market_id);
            assert(old_params != params, 'ParamsUnchanged');
            assert(params.range != 0, 'RangeZero');
            self.strategy_params.write(market_id, params);
            self
                .emit(
                    Event::SetStrategyParams(
                        SetStrategyParams {
                            market_id,
                            min_spread: params.min_spread,
                            range: params.range,
                            max_delta: params.max_delta,
                            allow_deposits: params.allow_deposits,
                        }
                    )
                );
        }

        // Change the oracle or oracle summary contracts.
        //
        // # Arguments
        // * `oracle` - contract address of oracle feed
        fn change_oracle(
            ref self: ContractState, oracle: ContractAddress, oracle_summary: ContractAddress
        ) {
            self.assert_owner();
            let oracle_dispatcher = IOracleABIDispatcher { contract_address: oracle };
            self.oracle.write(oracle_dispatcher);
            let oracle_summary_dispatcher = ISummaryStatsABIDispatcher {
                contract_address: oracle_summary
            };
            self.oracle_summary.write(oracle_summary_dispatcher);
            self.emit(Event::ChangeOracle(ChangeOracle { oracle, oracle_summary }));
        }

        // Request transfer ownership of the contract.
        // Part 1 of 2 step process to transfer ownership.
        //
        // # Arguments
        // * `new_owner` - New owner of the contract
        fn transfer_owner(ref self: ContractState, new_owner: ContractAddress) {
            self.assert_owner();
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

        // Request transfer ownership of a strategy.
        // Part 1 of 2 step process to transfer ownership.
        //
        // # Arguments
        // * `new_owner` - New owner of the contract
        fn transfer_strategy_owner(
            ref self: ContractState, market_id: felt252, new_owner: ContractAddress
        ) {
            self.assert_strategy_owner(market_id);
            let old_owner = self.strategy_owner.read(market_id);
            assert(new_owner != old_owner, 'SameOwner');
            self.queued_strategy_owner.write(market_id, new_owner);
        }

        // Called by new owner to accept ownership of a strategy.
        // Part 2 of 2 step process to transfer ownership.
        fn accept_strategy_owner(ref self: ContractState, market_id: felt252) {
            let queued_owner = self.queued_strategy_owner.read(market_id);
            assert(get_caller_address() == queued_owner, 'OnlyNewOwner');
            let old_owner = self.strategy_owner.read(market_id);
            self.strategy_owner.write(market_id, queued_owner);
            self.queued_strategy_owner.write(market_id, ContractAddressZeroable::zero());
            self
                .emit(
                    Event::ChangeStrategyOwner(
                        ChangeStrategyOwner { old: old_owner, new: queued_owner }
                    )
                );
        }

        // Pause strategy.
        fn pause(ref self: ContractState, market_id: felt252) {
            self.assert_strategy_owner(market_id);
            let mut state = self.strategy_state.read(market_id);
            state.is_paused = true;
            self.strategy_state.write(market_id, state);
            self.emit(Event::Pause(Pause { market_id }));
        }

        // Unpause strategy.
        fn unpause(ref self: ContractState, market_id: felt252) {
            self.assert_strategy_owner(market_id);
            let mut state = self.strategy_state.read(market_id);
            state.is_paused = false;
            self.strategy_state.write(market_id, state);
            self.emit(Event::Unpause(Unpause { market_id }));
        }

        // Temporary function to allow upgrading while deployed on testnet.
        // Callable by owner only.
        //
        // # Arguments
        // # `new_class_hash` - New class hash of the contract
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.assert_owner();
            replace_class_syscall(new_class_hash);
        }
    }

    ////////////////////////////////
    // INTERNAL FUNCTIONS
    ////////////////////////////////

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // Internal function to update for new optimal bid and ask positions.
        //
        // # Arguments
        // * `market_id` - market id of strategy
        //
        // # Returns
        // * `bid` - new optimal bid position
        // * `ask` - new optimal ask position
        fn _update_positions(
            ref self: ContractState, market_id: felt252
        ) -> (PositionInfo, PositionInfo) {
            // Fetch market and strategy state.
            let market_manager = self.market_manager.read();
            let mut state = self.strategy_state.read(market_id);

            // Fetch new bid and ask positions.
            // If the old positions are the same as the new positions, no updates will be made.
            let queued_positions = self.queued_positions(market_id);
            let next_bid = *queued_positions.at(0);
            let next_ask = *queued_positions.at(1);
            let update_bid: bool = next_bid != state.bid;
            let update_ask: bool = next_ask != state.ask;

            // Update positions.
            // If old positions exist at different price ranges, first remove them.
            if state.bid.liquidity != 0 && update_bid {
                let (base_amount, quote_amount, _, _) = market_manager
                    .modify_position(
                        market_id,
                        state.bid.lower_limit,
                        state.bid.upper_limit,
                        I128Trait::new(state.bid.liquidity, true)
                    );
                state.base_reserves += base_amount.val;
                state.quote_reserves += quote_amount.val;
                state.bid.liquidity = Default::default();
            }
            if state.ask.liquidity != 0 && update_ask {
                let (base_amount, quote_amount, _, _) = market_manager
                    .modify_position(
                        market_id,
                        state.ask.lower_limit,
                        state.ask.upper_limit,
                        I128Trait::new(state.ask.liquidity, true)
                    );
                state.base_reserves += base_amount.val;
                state.quote_reserves += quote_amount.val;
                state.ask.liquidity = Default::default();
            }

            // Place new positions.
            if next_bid.liquidity != 0 {
                let (_, quote_amount, _, _) = market_manager
                    .modify_position(
                        market_id,
                        next_bid.lower_limit,
                        next_bid.upper_limit,
                        I128Trait::new(next_bid.liquidity, false)
                    );
                state.quote_reserves -= quote_amount.val;
                state.bid = next_bid;
            };
            if next_ask.liquidity != 0 {
                let (base_amount, _, _, _) = market_manager
                    .modify_position(
                        market_id,
                        next_ask.lower_limit,
                        next_ask.upper_limit,
                        I128Trait::new(next_ask.liquidity, false)
                    );
                state.base_reserves -= base_amount.val;
                state.ask = next_ask;
            }

            // Commit state updates
            self.strategy_state.write(market_id, state);

            // Emit event if positions have changed.
            if update_bid || update_ask {
                self
                    .emit(
                        Event::UpdatePositions(
                            UpdatePositions {
                                market_id,
                                bid_lower_limit: next_bid.lower_limit,
                                bid_upper_limit: next_bid.upper_limit,
                                bid_liquidity: next_bid.liquidity,
                                ask_lower_limit: next_ask.lower_limit,
                                ask_upper_limit: next_ask.upper_limit,
                                ask_liquidity: next_ask.liquidity,
                            }
                        )
                    );
            }

            (state.bid, state.ask)
        }

        // Note: Volatility-based limits are currently disabled as they are not fully supported by the oracle.
        // // Internal function to fetch volatility and unpack limits.
        // // 
        // // # Arguments
        // // * `limits` - `Limits` enum to unpack
        // // * `market_id` - market id
        // //
        // // # Returns
        // // * `limits` - unpacked number of limits
        // fn _unpack_limits(self: @ContractState, limits: Limits, market_id: felt252) -> u32 {
        //     match limits {
        //         Limits::Fixed(x) => x,
        //         Limits::Vol(_) => {
        //             let vol = self.get_oracle_vol(market_id);
        //             let width = self.market_manager.read().width(market_id);
        //             spread_math::unpack_limits(limits, vol, width)
        //         }
        //     }
        // }

        // Internal function to collect all outstanding positions and pause the contract.
        // 
        // # Arguments
        // * `market_id` - market id
        fn _collect_and_pause(ref self: ContractState, market_id: felt252) {
            let mut state = self.strategy_state.read(market_id);
            assert(state.is_initialised, 'NotInitialised');
            assert(!state.is_paused, 'AlreadyPaused');

            let market_manager = self.market_manager.read();

            if state.bid.liquidity != 0 {
                let (bid_base, bid_quote, _, _) = market_manager
                    .modify_position(
                        market_id,
                        state.bid.lower_limit,
                        state.bid.upper_limit,
                        I128Trait::new(state.bid.liquidity, true)
                    );
                state.base_reserves += bid_base.val;
                state.quote_reserves += bid_quote.val;
                state.bid = Default::default();
            }
            if state.ask.liquidity != 0 {
                let (ask_base, ask_quote, _, _) = market_manager
                    .modify_position(
                        market_id,
                        state.ask.lower_limit,
                        state.ask.upper_limit,
                        I128Trait::new(state.ask.liquidity, true)
                    );
                state.base_reserves += ask_base.val;
                state.quote_reserves += ask_quote.val;
                state.ask = Default::default();
            }

            // Commit state updates
            state.is_paused = true;
            self.strategy_state.write(market_id, state);

            self.emit(Event::Pause(Pause { market_id }));
        }
    }
}
