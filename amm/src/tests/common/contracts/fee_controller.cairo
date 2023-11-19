#[starknet::contract]
mod FeeController {
    use starknet::ContractAddress;
    use amm::interfaces::IFeeController::IFeeController;

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl FeeController of IFeeController<ContractState> {
        fn swap_fee_rate(self: @ContractState) -> u16 {
            30
        }
    }
}
