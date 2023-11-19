// Core lib imports.
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use amm::types::core::PositionInfo;

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy, Serde, starknet::Store)]
struct StrategyParams {
    // default spread between reference price and bid/ask price (TODO: replace with volatility)
    min_spread: u32,
    // range parameter (width, in limits, of bid and ask liquidity positions)
    range: u32,
    // max_delta parameter (max additional single-sided spread based on portfolio imbalance)
    max_delta: u32,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
struct OracleParams {
    // Pragma base currency id
    base_currency_id: felt252,
    // Pragma quote currency id
    quote_currency_id: felt252,
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
    fn get_balances(self: @TContractState) -> (u256, u256);
    fn get_bid_ask(self: @TContractState) -> (u32, u32, u32, u32);

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
        range: u32,
        max_delta: u32,
    );
    fn deposit_initial(
        ref self: TContractState, base_amount: u256, quote_amount: u256
    ) -> (u256, u256, u256);
    fn deposit(
        ref self: TContractState, base_amount: u256, quote_amount: u256
    ) -> (u256, u256, u256);
    fn withdraw(ref self: TContractState, shares: u256) -> (u256, u256);
    fn collect_and_pause(ref self: TContractState);
    fn change_strategy_params(
        ref self: TContractState, min_spread: u32, range: u32, max_delta: u32
    );
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
    use super::{StrategyParams, OracleParams};
    use amm::contracts::market_manager::MarketManager;
    use amm::contracts::market_manager::MarketManager::ContractState as MMContractState;
    use amm::types::core::{MarketState, SwapParams, PositionInfo};
    use amm::libraries::math::{math, price_math, liquidity_math, fee_math};
    use amm::libraries::id;
    use amm::libraries::liquidity as liquidity_helpers;
    use amm::libraries::constants::ONE;
    use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
    use amm::interfaces::IStrategy::IStrategy;
    use amm::types::i256::{I256Trait, i256};
    use strategies::strategies::replicating::spread_math;
    use strategies::strategies::replicating::pragma_interfaces::{
        IOracleABIDispatcher, IOracleABIDispatcherTrait, AggregationMode, DataType, SimpleDataType,
        PragmaPricesResponse
    };

    // External imports.
    use openzeppelin::token::erc20::erc20::ERC20Component;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        // Immutables
        owner: ContractAddress,
        market_manager: IMarketManagerDispatcher,
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
        #[substorage(v0)]
        erc20: ERC20Component::Storage
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
        #[flat]
        ERC20Event: ERC20Component::Event
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
        range: u32,
        max_delta: u32,
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
            self.market_manager.read().contract_address
        }

        // Get market id
        fn market_id(self: @ContractState) -> felt252 {
            self.market_id.read()
        }

        // Get strategy name
        fn strategy_name(self: @ContractState) -> felt252 {
            self.erc20.name()
        }

        // Get strategy symbol
        fn strategy_symbol(self: @ContractState) -> felt252 {
            self.erc20.symbol()
        }

        // Get list of positions currently placed by strategy.
        //
        // # Returns
        // * `positions` - list of positions
        fn placed_positions(self: @ContractState) -> Span<PositionInfo> {
            let bid = self.bid.read();
            let ask = self.ask.read();
            let mut positions: Array<PositionInfo> = array![bid, ask];
            positions.span()
        }

        // Get list of positions queued to be placed by strategy on next update.
        // 
        // # Returns
        // * `positions` - list of positions
        fn queued_positions(self: @ContractState) -> Span<PositionInfo> {
            // Fetch market info.
            let market_manager = self.market_manager.read();
            let market_id = self.market_id.read();
            let market_info = market_manager.market_info(market_id);

            // Fetch strategy state.
            let strategy_params = self.strategy_params.read();
            let base_reserves = self.base_reserves.read();
            let quote_reserves = self.quote_reserves.read();
            let bid = self.bid.read();
            let ask = self.ask.read();

            // Fetch amounts in existing position.
            let contract: felt252 = get_contract_address().into();
            let bid_pos_id = id::position_id(market_id, contract, bid.lower_limit, bid.upper_limit);
            let ask_pos_id = id::position_id(market_id, contract, ask.lower_limit, ask.upper_limit);
            let (bid_base, bid_quote) = market_manager
                .amounts_inside_position(market_id, bid_pos_id, bid.lower_limit, bid.upper_limit);
            let (ask_base, ask_quote) = market_manager
                .amounts_inside_position(market_id, ask_pos_id, ask.lower_limit, ask.upper_limit);

            // Fetch new optimal bid and ask positions.
            let (next_bid_lower, next_bid_upper, next_ask_lower, next_ask_upper) = self
                .get_bid_ask();

            // Calculate amount of new liquidity to add.
            let base_amount = base_reserves + bid_base + ask_base;
            let base_liquidity = if base_amount == 0 || next_ask_lower
                + strategy_params.range > price_math::max_limit(market_info.width) {
                0
            } else {
                liquidity_math::base_to_liquidity(
                    price_math::limit_to_sqrt_price(next_ask_lower, market_info.width),
                    price_math::limit_to_sqrt_price(next_ask_upper, market_info.width),
                    base_amount
                )
            };
            let quote_amount = quote_reserves + bid_quote + ask_quote;
            let quote_liquidity = if next_bid_upper < strategy_params.range || quote_amount == 0 {
                0
            } else {
                liquidity_math::quote_to_liquidity(
                    price_math::limit_to_sqrt_price(next_bid_lower, market_info.width),
                    price_math::limit_to_sqrt_price(next_bid_upper, market_info.width),
                    quote_amount
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
            let mut positions: Array<PositionInfo> = array![next_bid, next_ask];
            positions.span()
        }

        // Updates positions. Called by MarketManager upon swap.
        fn update_positions(ref self: ContractState, params: SwapParams) {
            // Run checks
            let market_manager = self.market_manager.read();
            assert(get_caller_address() == market_manager.contract_address, 'OnlyMarketManager');
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
        fn get_balances(self: @ContractState) -> (u256, u256) {
            // Fetch strategy state.
            let base_reserves = self.base_reserves.read();
            let quote_reserves = self.quote_reserves.read();
            let bid = self.bid.read();
            let ask = self.ask.read();

            // Fetch position info from market manager.
            let market_id = self.market_id.read();
            let market_manager = self.market_manager.read();
            let contract: felt252 = get_contract_address().into();
            let bid_pos_id = id::position_id(market_id, contract, bid.lower_limit, bid.upper_limit);
            let ask_pos_id = id::position_id(market_id, contract, ask.lower_limit, ask.upper_limit);

            // Calculate base and quote amounts inside strategy, either in reserves or in positions.
            let (bid_base, bid_quote) = market_manager
                .amounts_inside_position(market_id, bid_pos_id, bid.lower_limit, bid.upper_limit,);
            let (ask_base, ask_quote) = market_manager
                .amounts_inside_position(market_id, ask_pos_id, ask.lower_limit, ask.upper_limit,);

            // Return total amounts.
            let base_amount = base_reserves + bid_base + ask_base;
            let quote_amount = quote_reserves + bid_quote + ask_quote;

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
        //   D is the max_delta parameter (controls how portfolio imbalance affects price)
        //
        // # Returns
        // * `bid_lower` - new bid lower limit
        // * `bid_upper` - new bid upper limit
        // * `ask_lower` - new ask lower limit
        // * `ask_upper` - new ask upper limit
        fn get_bid_ask(self: @ContractState) -> (u32, u32, u32, u32) {
            // Fetch strategy and market info.
            let strategy_params = self.strategy_params.read();
            let market_manager = self.market_manager.read();
            let market_id = self.market_id.read();
            let width = market_manager.width(market_id);
            let curr_limit = market_manager.curr_limit(market_id);

            // Calculate new optimal price.
            let price: u256 = self.get_oracle_price().into() * self.scaling_factor.read();
            let limit = price_math::price_to_limit(price, width, false);

            // Calculate new bid and ask limits.
            let (base_amount, quote_amount) = self.get_balances();
            let (bid_delta, ask_delta) = spread_math::delta_spread(
                strategy_params.max_delta, base_amount, quote_amount, price
            );
            let (bid_upper, ask_lower) = spread_math::calc_bid_ask(
                curr_limit, limit, bid_delta, ask_delta, strategy_params.min_spread, width
            );

            // Return new bid and ask limits.
            let bid_lower = bid_upper - strategy_params.range;
            let ask_upper = ask_lower + strategy_params.range;
            (bid_lower, bid_upper, ask_lower, ask_upper)
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
        // * `range` - range parameter (width, in limits, of bid and ask liquidity positions)
        // * `max_delta` - max_delta parameter (additional single-sided spread based on portfolio imbalance)
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
            range: u32,
            max_delta: u32,
        ) {
            self.assert_only_owner();
            assert(!self.is_initialised.read(), 'Initialised');
            self.erc20.initializer(name, symbol);

            let market_manager_contr = IMarketManagerDispatcher {
                contract_address: market_manager
            };
            self.market_manager.write(market_manager_contr);
            self.market_id.write(market_id);
            self.oracle.write(oracle);
            self.oracle_params.write(OracleParams { base_currency_id, quote_currency_id });
            self.scaling_factor.write(scaling_factor);

            let width = market_manager_contr.market_info(market_id).width;
            assert(min_spread % width == 0 && range % width == 0, 'NotMultipleOfWidth');
            assert(range > 0, 'rangeZero');
            self.strategy_params.write(StrategyParams { min_spread, range, max_delta });

            self.is_initialised.write(true);
            self
                .emit(
                    Event::ChangeOracle(
                        ChangeOracle { oracle, base_currency_id, quote_currency_id }
                    )
                );
            self.emit(Event::ChangeParams(ChangeParams { min_spread, range, max_delta }));
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
            assert(self.erc20.total_supply() == 0, 'UseDeposit');
            assert(base_amount != 0 && quote_amount != 0, 'AmountZero');
            assert(!self.is_paused.read(), 'Paused');
            assert(self.is_initialised.read(), 'NotInitialised');

            // Initialise state
            let market_id = self.market_id.read();
            let market_manager = self.market_manager.read();
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
            self.erc20._mint(caller, liquidity);

            assert(base_amount >= base_leftover, 'BaseLeftover');
            assert(quote_amount >= quote_leftover, 'QuoteLeftover');

            // Emit event
            self.emit(Event::Deposit(Deposit { owner: caller, base_amount, quote_amount }));

            (base_amount - base_leftover, quote_amount - quote_leftover, liquidity)
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
            ref self: ContractState, base_amount: u256, quote_amount: u256
        ) -> (u256, u256, u256) {
            // Run checks.
            let total_supply = self.erc20.total_supply();
            assert(total_supply != 0, 'UseDepositInitial');
            assert(base_amount != 0 || quote_amount != 0, 'AmountZero');
            assert(!self.is_paused.read(), 'Paused');

            // Fetch market info and strategy state.
            let market_manager = self.market_manager.read();
            let market_info = market_manager.market_info(self.market_id.read());
            let mut base_reserves = self.base_reserves.read();
            let mut quote_reserves = self.quote_reserves.read();
            let (base_balance, quote_balance) = self.get_balances();

            // Calculate shares to mint.
            let base_deposit = min(
                base_amount, math::mul_div(quote_amount, base_balance, quote_balance, false)
            );
            let quote_deposit = min(
                quote_amount, math::mul_div(base_amount, quote_balance, base_balance, false)
            );
            let shares = math::mul_div(total_supply, base_deposit, base_balance, false);

            // Transfer tokens into contract.
            let caller = get_caller_address();
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
            base_reserves += base_deposit;
            quote_reserves += quote_deposit;
            self.base_reserves.write(base_reserves);
            self.quote_reserves.write(quote_reserves);

            // Mint liquidity.
            self.erc20._mint(caller, shares);

            // Emit event.
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            owner: caller, base_amount: base_deposit, quote_amount: quote_deposit
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
        fn withdraw(ref self: ContractState, shares: u256) -> (u256, u256) {
            // Run checks
            let total_supply = self.erc20.total_supply();
            assert(total_supply != 0, 'NoSupply');
            assert(shares != 0, 'SharesZero');
            assert(shares <= total_supply, 'SharesOverflow');
            let caller = get_caller_address();
            let caller_balance = self.erc20.balance_of(caller);
            assert(caller_balance >= shares, 'InsufficientShares');

            // Fetch current market state
            let market_id = self.market_id.read();
            let market_manager = self.market_manager.read();
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
            let bid_liquidity_delta_i256 = I256Trait::new(bid_liquidity_delta, true);
            let (bid_base_rem, bid_quote_rem, bid_base_fees, bid_quote_fees) = market_manager
                .modify_position(
                    market_id, bid.lower_limit, bid.upper_limit, bid_liquidity_delta_i256
                );
            let ask_liquidity_delta = math::mul_div(ask.liquidity, shares, total_supply, false);
            ask.liquidity -= ask_liquidity_delta;
            let ask_liquidity_delta_i256 = I256Trait::new(ask_liquidity_delta, true);
            let (ask_base_rem, ask_quote_rem, ask_base_fees, ask_quote_fees) = market_manager
                .modify_position(
                    market_id, ask.lower_limit, ask.upper_limit, ask_liquidity_delta_i256
                );

            // Withdrawal includes all fees in position, not only those belonging to caller.
            let base_fees_excess = math::mul_div(
                bid_base_fees + ask_base_fees, total_supply - shares, total_supply, true
            );
            let quote_fees_excess = math::mul_div(
                bid_quote_fees + ask_quote_fees, total_supply - shares, total_supply, true
            );
            base_withdraw += bid_base_rem.val + ask_base_rem.val - base_fees_excess;
            quote_withdraw += bid_quote_rem.val + ask_quote_rem.val - quote_fees_excess;
            base_reserves += base_fees_excess;
            quote_reserves += quote_fees_excess;

            // Burn shares.
            self.erc20._burn(caller, shares);

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
            self.base_reserves.write(base_reserves);
            self.quote_reserves.write(quote_reserves);
            self.bid.write(bid);
            self.ask.write(ask);

            // Emit event.
            self
                .emit(
                    Event::Withdraw(
                        Withdraw {
                            owner: caller, base_amount: base_withdraw, quote_amount: quote_withdraw
                        }
                    )
                );

            // Return withdrawn amounts.
            (base_withdraw, quote_withdraw)
        }

        // Manually trigger contract to collect all outstanding positions and pause the contract.
        // Only callable by contract owner.
        fn collect_and_pause(ref self: ContractState) {
            self.assert_only_owner();
            assert(self.is_initialised.read(), 'NotInitialised');

            let market_manager = self.market_manager.read();
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
        // * `range` - range parameter (width, in limits, of bid and ask liquidity positions)
        // * `max_delta` - max_delta parameter (additional single-sided spread based on portfolio imbalance)
        fn change_strategy_params(
            ref self: ContractState, min_spread: u32, range: u32, max_delta: u32,
        ) {
            self.assert_only_owner();
            let market_manager = self.market_manager.read();
            let width = market_manager.market_info(self.market_id.read()).width;
            assert(min_spread % width == 0 && range % width == 0, 'NotMultipleOfWidth');
            assert(range > 0, 'rangeZero');
            self.strategy_params.write(StrategyParams { min_spread, range, max_delta });
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
            let market_manager = self.market_manager.read();
            let market_id = self.market_id.read();

            // Fetch strategy state.
            let mut base_reserves = self.base_reserves.read();
            let mut quote_reserves = self.quote_reserves.read();
            let mut bid = self.bid.read();
            let mut ask = self.ask.read();

            // Fetch new bid and ask positions.
            let queued_positions = self.queued_positions();
            let next_bid = *queued_positions.at(0);
            let next_ask = *queued_positions.at(1);
            let update_bid: bool = next_bid != bid;
            let update_ask: bool = next_ask != ask;

            // Update positions.
            // If old positions exist at different price ranges, first remove them.
            if bid.liquidity != 0 && update_bid {
                let (base_amount, quote_amount, _, _) = market_manager
                    .modify_position(
                        market_id,
                        bid.lower_limit,
                        bid.upper_limit,
                        I256Trait::new(bid.liquidity, true)
                    );
                base_reserves += base_amount.val;
                quote_reserves += quote_amount.val;
                bid.liquidity = Default::default();
            }
            if ask.liquidity != 0 && update_ask {
                let (base_amount, quote_amount, _, _) = market_manager
                    .modify_position(
                        market_id,
                        ask.lower_limit,
                        ask.upper_limit,
                        I256Trait::new(ask.liquidity, true)
                    );
                base_reserves += base_amount.val;
                quote_reserves += quote_amount.val;
                ask.liquidity = Default::default();
            }

            // Place new positions.
            if next_bid.liquidity != 0 {
                let (_, quote_amount, _, _) = market_manager
                    .modify_position(
                        market_id,
                        next_bid.lower_limit,
                        next_bid.upper_limit,
                        I256Trait::new(next_bid.liquidity, false)
                    );
                quote_reserves -= quote_amount.val;
                bid = next_bid;
            };
            if next_ask.liquidity != 0 {
                let (base_amount, _, _, _) = market_manager
                    .modify_position(
                        market_id,
                        next_ask.lower_limit,
                        next_ask.upper_limit,
                        I256Trait::new(next_ask.liquidity, false)
                    );
                base_reserves -= base_amount.val;
                ask = next_ask;
            }

            // Commit state updates
            self.base_reserves.write(base_reserves);
            self.quote_reserves.write(quote_reserves);
            self.bid.write(bid);
            self.ask.write(ask);

            // Emit event if positions have changed.
            if update_bid || update_ask {
                self
                    .emit(
                        Event::UpdatePositions(
                            UpdatePositions {
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

            (bid, ask)
        }
    }
}
