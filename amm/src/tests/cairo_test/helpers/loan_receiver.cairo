use serde::Serde;
use core::result::ResultTrait;
use traits::TryInto;
use option::OptionTrait;
use array::ArrayTrait;
use starknet::{ContractAddress, deploy_syscall};

use amm::tests::common::contracts::flash_loan_receiver::FlashLoanReceiver;
use amm::interfaces::ILoanReceiver::{
    ILoanReceiver, ILoanReceiverDispatcher, ILoanReceiverDispatcherTrait
};

fn deploy_loan_receiver(
    market_manager: ContractAddress, return_funds: bool
) -> ILoanReceiverDispatcher {
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    market_manager.serialize(ref constructor_calldata);
    return_funds.serialize(ref constructor_calldata);

    let (deployed_address, _) = deploy_syscall(
        FlashLoanReceiver::TEST_CLASS_HASH.try_into().unwrap(),
        0,
        constructor_calldata.span(),
        false
    )
        .unwrap();

    ILoanReceiverDispatcher { contract_address: deployed_address }
}
