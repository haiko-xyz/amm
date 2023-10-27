use starknet::ContractAddress;

#[starknet::interface]
trait IFeeController<TContractState> {
    fn market_manager(self: @TContractState) -> ContractAddress;
    fn name(self: @TContractState) -> felt252;
    fn swap_fee_rate(self: @TContractState) -> u16;
    fn flash_loan_fee(self: @TContractState) -> u16;
}
