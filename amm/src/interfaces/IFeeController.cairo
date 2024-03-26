use starknet::ContractAddress;

#[starknet::interface]
pub trait IFeeController<TContractState> {
    fn swap_fee_rate(self: @TContractState) -> u16;
}
