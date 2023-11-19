// Core lib imports.
use starknet::ContractAddress;

// Local imports.
use amm::types::core::{SwapParams, PositionInfo};

#[starknet::interface]
trait IStrategy<TContractState> {
    // View
    fn market_manager(self: @TContractState) -> ContractAddress;
    fn market_id(self: @TContractState) -> felt252;
    fn strategy_name(self: @TContractState) -> felt252;
    fn strategy_symbol(self: @TContractState) -> felt252;
    fn placed_positions(self: @TContractState) -> Span<PositionInfo>;
    fn queued_positions(self: @TContractState) -> Span<PositionInfo>;

    // External
    fn update_positions(ref self: TContractState, params: SwapParams);
    fn cleanup(ref self: TContractState);
}
