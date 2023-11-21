// Core lib imports.
use starknet::ContractAddress;

// Local imports.
use amm::types::core::{SwapParams, PositionInfo};

#[starknet::interface]
trait IStrategy<TContractState> {
    ////////////////////////////////
    // VIEW
    ////////////////////////////////

    // Get market manager contract address.
    fn market_manager(self: @TContractState) -> ContractAddress;

    // Get market id of strategy.
    fn market_id(self: @TContractState) -> felt252;

    // Get strategy name.
    fn strategy_name(self: @TContractState) -> felt252;

    // Get strategy symbol.
    fn strategy_symbol(self: @TContractState) -> felt252;

    // Get a list of positions placed by the strategy on the market.
    fn placed_positions(self: @TContractState) -> Span<PositionInfo>;

    // Get list of positions queued to be placed by strategy on next `swap` update. If no updates
    // are queued, the returned list will match the list returned by `placed_positions`.
    fn queued_positions(self: @TContractState) -> Span<PositionInfo>;

    ////////////////////////////////
    // EXTERNAL
    ////////////////////////////////

    // Called by `MarketManager` before swap to replace `placed_positions` with `queued_positions`.
    // If the two lists are equal, no positions will be updated.
    fn update_positions(ref self: TContractState, params: SwapParams);

    // Called by `MarketManager` after swap to execute any cleanup operations.
    fn cleanup(ref self: TContractState);
}
