// Core lib imports.
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

// Local imports.
use amm::types::core::PositionInfo;
use strategies::strategies::replicating::types::{StrategyParams, OracleParams, StrategyState};


#[starknet::interface]
trait IReplicatingStrategy<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn queued_owner(self: @TContractState) -> ContractAddress;
    fn strategy_owner(self: @TContractState, market_id: felt252) -> ContractAddress;
    fn queued_strategy_owner(self: @TContractState, market_id: felt252) -> ContractAddress;
    fn oracle(self: @TContractState) -> ContractAddress;
    fn oracle_summary(self: @TContractState) -> ContractAddress;
    fn strategy_params(self: @TContractState, market_id: felt252) -> StrategyParams;
    fn oracle_params(self: @TContractState, market_id: felt252) -> OracleParams;
    fn strategy_state(self: @TContractState, market_id: felt252) -> StrategyState;
    fn is_paused(self: @TContractState, market_id: felt252) -> bool;
    fn bid(self: @TContractState, market_id: felt252) -> PositionInfo;
    fn ask(self: @TContractState, market_id: felt252) -> PositionInfo;
    fn base_reserves(self: @TContractState, market_id: felt252) -> u256;
    fn quote_reserves(self: @TContractState, market_id: felt252) -> u256;
    fn user_deposits(self: @TContractState, market_id: felt252, owner: ContractAddress) -> u256;
    fn total_deposits(self: @TContractState, market_id: felt252) -> u256;

    fn get_oracle_price(self: @TContractState, market_id: felt252) -> (u256, bool);
    // fn get_oracle_vol(self: @TContractState, market_id: felt252) -> u256;
    fn get_balances(self: @TContractState, market_id: felt252) -> (u256, u256);
    fn get_bid_ask(self: @TContractState, market_id: felt252) -> (u32, u32, u32, u32);

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
    );
    fn deposit_initial(
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> u256;
    fn deposit(
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> (u256, u256, u256);
    fn withdraw(ref self: TContractState, market_id: felt252, shares: u256) -> (u256, u256);
    fn collect_and_pause(ref self: TContractState, market_id: felt252);
    fn set_params(ref self: TContractState, market_id: felt252, params: StrategyParams,);
    fn change_oracle(
        ref self: TContractState, oracle: ContractAddress, oracle_summary: ContractAddress,
    );
    fn transfer_owner(ref self: TContractState, new_owner: ContractAddress);
    fn accept_owner(ref self: TContractState);
    fn transfer_strategy_owner(
        ref self: TContractState, market_id: felt252, new_owner: ContractAddress
    );
    fn accept_strategy_owner(ref self: TContractState, market_id: felt252);
    fn pause(ref self: TContractState, market_id: felt252);
    fn unpause(ref self: TContractState, market_id: felt252);
    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}
