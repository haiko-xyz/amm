use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

#[starknet::interface]
trait IQuoter<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn market_manager(self: @TContractState) -> ContractAddress;

    fn quote(
        self: @TContractState, market_id: felt252, is_buy: bool, amount: u256, exact_input: bool,
    ) -> u256;

    fn unsafe_quote_array(
        self: @TContractState,
        market_ids: Span<felt252>,
        is_buy: bool,
        amount: u256,
        exact_input: bool
    ) -> Span<u256>;

    fn quote_multiple(
        self: @TContractState,
        in_token: ContractAddress,
        out_token: ContractAddress,
        amount: u256,
        route: Span<felt252>,
    ) -> u256;

    fn unsafe_quote_multiple_array(
        self: @TContractState,
        in_token: ContractAddress,
        out_token: ContractAddress,
        amount: u256,
        routes: Span<felt252>,
        route_lens: Span<u8>,
    ) -> Span<u256>;

    fn amounts_inside_position_array(
        self: @TContractState, position_ids: Span<felt252>
    ) -> Span<(u256, u256, u256, u256)>;

    fn amounts_inside_order_array(
        self: @TContractState, order_ids: Span<felt252>, market_ids: Span<felt252>
    ) -> Span<(u256, u256)>;

    fn token_balance_array(
        self: @TContractState, user: ContractAddress, tokens: Span<ContractAddress>
    ) -> Span<(u256, u8)>;

    fn new_market_position_approval_amounts(
        self: @TContractState,
        width: u32,
        start_limit: u32,
        lower_limit: u32,
        upper_limit: u32,
        liquidity_delta: u128,
    ) -> (u256, u256);

    fn set_market_manager(ref self: TContractState, market_manager: ContractAddress);

    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}
