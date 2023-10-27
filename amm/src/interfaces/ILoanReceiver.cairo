#[starknet::interface]
trait ILoanReceiver<TContractState> {
    fn on_flash_loan(ref self: TContractState, amount: u256);
}
