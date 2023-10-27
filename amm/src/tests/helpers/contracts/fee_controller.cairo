#[starknet::contract]
mod FeeController {
    use starknet::ContractAddress;
    use amm::interfaces::IFeeController::IFeeController;

    #[storage]
    struct Storage {
        market_manager: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, market_manager: ContractAddress,) {
        self.market_manager.write(market_manager);
    }

    #[external(v0)]
    impl FeeController of IFeeController<ContractState> {
        fn market_manager(self: @ContractState) -> ContractAddress {
            self.market_manager.read()
        }

        fn name(self: @ContractState) -> felt252 {
            '0% fees'
        }

        fn swap_fee_rate(self: @ContractState) -> u16 {
            0
        }

        fn flash_loan_fee(self: @ContractState) -> u16 {
            0
        }
    }
}
