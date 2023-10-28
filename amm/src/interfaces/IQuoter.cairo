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
}