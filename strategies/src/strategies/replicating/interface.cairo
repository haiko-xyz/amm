// Core lib imports.
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use amm::types::core::PositionInfo;
use strategies::strategies::replicating::types::{StrategyParams, OracleParams, StrategyState};


#[starknet::interface]
trait IReplicatingStrategy<TContractState> {
    // Contract owner
    fn owner(self: @TContractState) -> ContractAddress;

    // Queued contract owner, used for ownership transfers
    fn queued_owner(self: @TContractState) -> ContractAddress;

    // Strategy owner
    fn strategy_owner(self: @TContractState, market_id: felt252) -> ContractAddress;

    // Queued strategy owner, used for ownership transfers
    fn queued_strategy_owner(self: @TContractState, market_id: felt252) -> ContractAddress;

    // Pragma oracle contract address
    fn oracle(self: @TContractState) -> ContractAddress;

    // Pragma oracle summary contract address
    fn oracle_summary(self: @TContractState) -> ContractAddress;

    // Strategy parameters for a given market
    fn strategy_params(self: @TContractState, market_id: felt252) -> StrategyParams;

    // Oracle parameters for a given market
    fn oracle_params(self: @TContractState, market_id: felt252) -> OracleParams;

    // Strategy state
    fn strategy_state(self: @TContractState, market_id: felt252) -> StrategyState;

    // Whether strategy is paused for a given market
    fn is_paused(self: @TContractState, market_id: felt252) -> bool;

    // Placed bid position for a given market
    fn bid(self: @TContractState, market_id: felt252) -> PositionInfo;

    // Placed ask position for a given market
    fn ask(self: @TContractState, market_id: felt252) -> PositionInfo;

    // Base reserves of strategy
    fn base_reserves(self: @TContractState, market_id: felt252) -> u256;

    // Quote reserves of strategy
    fn quote_reserves(self: @TContractState, market_id: felt252) -> u256;

    // Whether a user is whitelisted to deposit to the strategy contract
    fn is_whitelisted(self: @TContractState, user: ContractAddress) -> bool;

    // User's deposited shares in a given market
    fn user_deposits(self: @TContractState, market_id: felt252, owner: ContractAddress) -> u256;

    // Total deposited shares  in a given market
    fn total_deposits(self: @TContractState, market_id: felt252) -> u256;

    // Withdraw fee rate for a given market
    fn withdraw_fee_rate(self: @TContractState, market_id: felt252) -> u16;

    // Accumulated withdraw fee balance for a given asset
    fn withdraw_fees(self: @TContractState, token: ContractAddress) -> u256;

    // Get price from oracle feed.
    // 
    // # Returns
    // * `price` - oracle price
    // * `is_valid` - whether oracle price passes validity checks re number of sources and age
    fn get_oracle_price(self: @TContractState, market_id: felt252) -> (u256, bool);

    // fn get_oracle_vol(self: @TContractState, market_id: felt252) -> u256;

    // Get total tokens held in strategy, whether in reserves or in positions.
    // 
    // # Arguments
    // * `market_id` - market id
    //
    // # Returns
    // * `base_amount` - total base tokens owned
    // * `quote_amount` - total quote tokens owned
    fn get_balances(self: @TContractState, market_id: felt252) -> (u256, u256);

    // Get token amounts held in strategy market for a list of markets.
    // 
    // # Arguments
    // * `market_ids` - list of market ids
    //
    // # Returns
    // * `base_amount` - base amount held in strategy market
    // * `quote_amount` - quote amount held in strategy market
    fn get_balances_array(self: @TContractState, market_ids: Span<felt252>) -> Span<(u256, u256)>;

    // Get user's share of amounts held in strategy, for a list of users.
    // 
    // # Arguments
    // * `users` - list of user address
    // * `market_ids` - list of market ids
    //
    // # Returns
    // * `base_amount` - base tokens owned by user
    // * `quote_amount` - quote tokens owned by user
    // * `user_shares` - user shares
    // * `total_shares` - total shares in strategy market
    fn get_user_balances(
        self: @TContractState, users: Span<ContractAddress>, market_ids: Span<felt252>
    ) -> Span<(u256, u256, u256, u256)>;

    // Calculate next optimal bid and ask positions.
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
    fn get_bid_ask(self: @TContractState, market_id: felt252) -> (u32, u32, u32, u32);

    // Initialise strategy for market.
    // At the moment, only callable by contract owner to prevent unwanted claiming of strategies. 
    //
    // # Arguments
    // * `market_id` - market id
    // * `owner` - nominated owner for strategy
    // * `base_currency_id` - base currency id for oracle
    // * `quote_currency_id` - quote currency id for oracle
    // * `min_sources` - minimum number of sources required for oracle price (automatically paused if fails)
    // * `max_age` - maximum age of oracle price in seconds (automatically paused if fails)
    // * `min_spread` - minimum spread to between reference price and bid/ask price
    // * `range` - range parameter (width, in limits, of bid and ask liquidity positions)
    // * `max_delta` - max inv_delta parameter (additional single-sided spread based on portfolio imbalance)
    // * `allow_deposits` - whether deposits are allowed for depositors other than the strategy owner
    // * `use_whitelist` - whether to use a whitelist for deposits
    fn add_market(
        ref self: TContractState,
        market_id: felt252,
        owner: ContractAddress,
        base_currency_id: felt252,
        quote_currency_id: felt252,
        min_sources: u32,
        max_age: u64,
        min_spread: u32,
        range: u32,
        max_delta: u32,
        allow_deposits: bool,
        use_whitelist: bool,
    );

    // Deposit initial liquidity to strategy and place positions.
    // Should be used whenever total deposits in a strategy are zero. This can happen both
    // when a strategy is first initialised, or subsequently whenever all deposits are withdrawn.
    // The deposited amounts will constitute the starting reserves of the strategy, so initial
    // base and quote deposits should be balanced in value to avoid portfolio skew.
    //
    // # Arguments
    // * `market_id` - market id
    // * `base_amount` - base asset to deposit
    // * `quote_amount` - quote asset to deposit
    //
    // # Returns
    // * `shares` - pool shares minted in the form of liquidity
    fn deposit_initial(
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> u256;

    // Deposit liquidity to strategy.
    //
    // # Arguments
    // * `market_id` - market id
    // * `base_amount` - base asset desired
    // * `quote_amount` - quote asset desired
    //
    // # Returns
    // * `base_amount` - base asset deposited
    // * `quote_amount` - quote asset deposited
    // * `shares` - pool shares minted
    fn deposit(
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> (u256, u256, u256);

    // Burn pool shares and withdraw funds from strategy.
    //
    // # Arguments
    // * `market_id` - market id
    // * `shares` - pool shares to burn
    //
    // # Returns
    // * `base_amount` - base asset withdrawn
    // * `quote_amount` - quote asset withdrawn
    fn withdraw(ref self: TContractState, market_id: felt252, shares: u256) -> (u256, u256);

    // Manually trigger contract to collect all outstanding positions and pause the contract.
    // Only callable by strategy owner.
    fn collect_and_pause(ref self: TContractState, market_id: felt252);

    // Collect withdrawal fees.
    // Only callable by contract owner.
    //
    // # Arguments
    // * `receiver` - address to receive fees
    // * `token` - token to collect fees for
    // * `amount` - amount of fees requested
    fn collect_withdraw_fees(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256
    ) -> u256;

    // Change the parameters of the strategy.
    // Only callable by strategy owner.
    //
    // # Params
    // * `market_id` - market id
    // * `params` - strategy params
    //    * `min_spread` - minimum spread between reference price and bid/ask price
    //    * `range` - range parameter (width, in limits, of bid and ask liquidity positions)
    //    * `max_delta` - max inv_delta parameter (additional single-sided spread based on portfolio imbalance)
    //    * `allow_deposits` - whether deposits are allowed for depositors other than the strategy owner
    fn set_params(ref self: TContractState, market_id: felt252, params: StrategyParams,);

    // Update whitelist for user deposits.
    // Only callable by owner.
    //
    // # Arguments
    // * `user` - user to whitelist
    // * `enable` - whether to enable or disable user whitelist
    fn set_whitelist(ref self: TContractState, user: ContractAddress, enable: bool);

    // Set withdraw fee for a given market.
    // Only callable by contract owner.
    //
    // # Arguments
    // * `market_id` - market id
    // * `fee_rate` - fee rate
    fn set_withdraw_fee(ref self: TContractState, market_id: felt252, fee_rate: u16);

    // Change the oracle or oracle summary contract addresses.
    //
    // # Arguments
    // * `oracle` - contract address of oracle feed
    // * `oracle_summary` - contract address of oracle summary
    fn change_oracle(
        ref self: TContractState, oracle: ContractAddress, oracle_summary: ContractAddress,
    );

    // Request transfer ownership of the contract.
    // Part 1 of 2 step process to transfer ownership.
    //
    // # Arguments
    // * `new_owner` - New owner of the contract
    fn transfer_owner(ref self: TContractState, new_owner: ContractAddress);

    // Called by new owner to accept ownership of the contract.
    // Part 2 of 2 step process to transfer ownership.
    fn accept_owner(ref self: TContractState);

    // Request transfer ownership of a strategy.
    // Part 1 of 2 step process to transfer ownership.
    //
    // # Arguments
    // * `market_id` - market id
    // * `new_owner` - New owner of the contract
    fn transfer_strategy_owner(
        ref self: TContractState, market_id: felt252, new_owner: ContractAddress
    );

    // Called by new owner to accept ownership of a strategy.
    // Part 2 of 2 step process to transfer ownership.
    //
    // # Arguments
    // * `market_id` - market id of strategy
    fn accept_strategy_owner(ref self: TContractState, market_id: felt252);

    // Pause strategy. 
    // Only callable by strategy owner. 
    // 
    // # Arguments
    // * `market_id` - market id of strategy
    fn pause(ref self: TContractState, market_id: felt252);

    // Unpause strategy.
    // Only callable by strategy owner.
    //
    // # Arguments
    // * `market_id` - market id of strategy
    fn unpause(ref self: TContractState, market_id: felt252);

    // Upgrade contract to new version.
    // Only callable by contract owner.
    //
    // # Arguments
    // * `new_class_hash` - new class hash of upgraded contract
    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}
