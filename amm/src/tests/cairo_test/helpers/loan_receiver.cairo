// Core lib imports.
use starknet::{ContractAddress, ClassHash, syscalls::deploy_syscall};

// Local imports.
use amm::tests::mocks::flash_loan_receiver::FlashLoanReceiver;
use amm::tests::mocks::flash_loan_stealer::FlashLoanStealer;
use amm::interfaces::ILoanReceiver::{
    ILoanReceiver, ILoanReceiverDispatcher, ILoanReceiverDispatcherTrait
};

pub fn deploy_loan_receiver(
    market_manager: ContractAddress, use_stealer: bool
) -> ILoanReceiverDispatcher {
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    market_manager.serialize(ref constructor_calldata);

    let class_hash: ClassHash = if use_stealer {
        FlashLoanStealer::TEST_CLASS_HASH
    } else {
        FlashLoanReceiver::TEST_CLASS_HASH
    }
        .try_into()
        .unwrap();

    let (deployed_address, _) = deploy_syscall(class_hash, 0, constructor_calldata.span(), false)
        .unwrap();

    ILoanReceiverDispatcher { contract_address: deployed_address }
}
