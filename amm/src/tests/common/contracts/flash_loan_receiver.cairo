#[starknet::contract]
mod FlashLoanReceiver {
    use starknet::ContractAddress;
    use amm::interfaces::ILoanReceiver::ILoanReceiver;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        market_manager: ContractAddress,
        return_funds: bool,
    }

    #[constructor]
    fn constructor(ref self: ContractState, market_manager: ContractAddress, return_funds: bool) {
        self.market_manager.write(market_manager);
        self.return_funds.write(return_funds);
    }

    #[external(v0)]
    impl LoanReceiver of ILoanReceiver<ContractState> {
        // Callback function for flash loan.
        // Returns funds to market manager after loan.
        //
        // # Arguments
        // * `token` - address of the token being borrowed
        // * `amount` - amount of the token being borrowed (excludes fee)
        // * `fee` - flash loan fee
        fn on_flash_loan(
            ref self: ContractState, token: ContractAddress, amount: u256, fee: u256,
        ) {
            if !self.return_funds.read() {
                return;
            }
            let dispatcher = IERC20Dispatcher { contract_address: token };
            dispatcher.transfer(self.market_manager.read(), amount + fee);
        }
    }
}
