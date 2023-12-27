use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

#[starknet::interface]
trait IQuoter<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn market_manager(self: @TContractState) -> ContractAddress;

    fn quote(
        self: @TContractState, market_id: felt252, is_buy: bool, amount: u256, exact_input: bool,
    ) -> u256;

    fn quote_array(
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

    fn quote_multiple_array(
        self: @TContractState,
        in_token: ContractAddress,
        out_token: ContractAddress,
        amount: u256,
        routes: Span<felt252>,
        route_lens: Span<u8>,
    ) -> Span<u256>;

    fn set_market_manager(ref self: TContractState, market_manager: ContractAddress);

    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}
