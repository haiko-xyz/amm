use starknet::ContractAddress;

#[starknet::interface]
trait IQuoter<TContractState> {
    fn quote(
        self: @TContractState,
        market_id: felt252,
        is_buy: bool,
        amount: u256,
        exact_input: bool,
        threshold_sqrt_price: Option<u256>,
    ) -> u256;

    fn quote_multiple(
        self: @TContractState,
        in_token: ContractAddress,
        out_token: ContractAddress,
        amount: u256,
        route: Span<felt252>,
    ) -> u256;
}