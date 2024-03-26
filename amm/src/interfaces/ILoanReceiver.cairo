use starknet::ContractAddress;

#[starknet::interface]
pub trait ILoanReceiver<TContractState> {
    fn on_flash_loan(ref self: TContractState, token: ContractAddress, amount: u256, fee: u256);
}
