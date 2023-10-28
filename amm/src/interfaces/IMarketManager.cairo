use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

use amm::types::core::{
    MarketInfo, MarketState, OrderBatch, Position, LimitInfo, LimitOrder, PositionInfo
};
use amm::types::i256::i256;

#[starknet::interface]
trait IMarketManager<TContractState> {
    ////////////////////////////////
    // VIEW
    ////////////////////////////////

    fn owner(self: @TContractState) -> ContractAddress;

    fn quote_token(self: @TContractState, market_id: felt252) -> ContractAddress;

    fn base_token(self: @TContractState, market_id: felt252) -> ContractAddress;

    fn width(self: @TContractState, market_id: felt252) -> u32;

    fn strategy(self: @TContractState, market_id: felt252) -> ContractAddress;

    fn fee_controller(self: @TContractState, market_id: felt252) -> ContractAddress;

    fn swap_fee_rate(self: @TContractState, market_id: felt252) -> u16;

    fn flash_loan_fee(self: @TContractState, token: ContractAddress) -> u16;

    fn protocol_share(self: @TContractState, market_id: felt252) -> u16;

    fn position(self: @TContractState, position_id: felt252) -> Position;

    fn order(self: @TContractState, order_id: felt252) -> LimitOrder;

    fn market_info(self: @TContractState, market_id: felt252) -> MarketInfo;

    fn market_state(self: @TContractState, market_id: felt252) -> MarketState;

    fn batch(self: @TContractState, batch_id: felt252) -> OrderBatch;

    fn liquidity(self: @TContractState, market_id: felt252) -> u256;

    fn curr_limit(self: @TContractState, market_id: felt252) -> u32;

    fn curr_sqrt_price(self: @TContractState, market_id: felt252) -> u256;

    fn limit_info(self: @TContractState, market_id: felt252, limit: u32) -> LimitInfo;

    fn is_limit_init(self: @TContractState, market_id: felt252, width: u32, limit: u32) -> bool;

    fn next_limit(
        self: @TContractState, market_id: felt252, is_buy: bool, width: u32, start_limit: u32
    ) -> Option<u32>;

    fn reserves(self: @TContractState, asset: ContractAddress) -> u256;

    fn protocol_fees(self: @TContractState, asset: ContractAddress) -> u256;

    fn position_fees(
        self: @TContractState,
        owner: ContractAddress,
        market_id: felt252,
        lower_limit: u32,
        upper_limit: u32
    ) -> (u256, u256);

    fn ERC721_position_info(self: @TContractState, token_id: felt252) -> PositionInfo;

    ////////////////////////////////
    // EXTERNAL
    ////////////////////////////////

    fn create_market(
        ref self: TContractState,
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
    ) -> felt252;

    fn modify_position(
        ref self: TContractState,
        market_id: felt252,
        lower_limit: u32,
        upper_limit: u32,
        liquidity_delta: i256,
    ) -> (i256, i256, u256, u256);

    fn create_order(
        ref self: TContractState,
        market_id: felt252,
        is_bid: bool,
        limit: u32,
        liquidity_delta: u256,
    ) -> felt252;

    fn collect_order(
        ref self: TContractState, market_id: felt252, order_id: felt252,
    ) -> (u256, u256);

    fn swap(
        ref self: TContractState,
        market_id: felt252,
        is_buy: bool,
        amount: u256,
        exact_input: bool,
        threshold_sqrt_price: Option<u256>,
        deadline: Option<u64>,
    ) -> (u256, u256, u256);

    fn swap_multiple(
        ref self: TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        is_buy: bool,
        amount: u256,
        route: Span<felt252>,
        deadline: Option<u64>,
    ) -> u256;

    fn quote(
        ref self: TContractState,
        market_id: felt252,
        is_buy: bool,
        amount: u256,
        exact_input: bool,
        threshold_sqrt_price: Option<u256>,
    );

    fn quote_multiple(
        ref self: TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        is_buy: bool,
        amount: u256,
        route: Span<felt252>,
        deadline: Option<u64>,
    );

    fn flash_loan(ref self: TContractState, token: ContractAddress, amount: u256);

    fn mint(ref self: TContractState, position_id: felt252);

    fn burn(ref self: TContractState, position_id: felt252);

    fn enable_concentrated(ref self: TContractState, market_id: felt252);

    fn collect_protocol_fees(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256,
    ) -> u256;

    fn sweep(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256,
    ) -> u256;

    fn set_owner(ref self: TContractState, new_owner: ContractAddress);

    fn set_flash_loan_fee(ref self: TContractState, token: ContractAddress, fee: u16);

    fn set_protocol_share(ref self: TContractState, market_id: felt252, protocol_share: u16);

    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}
