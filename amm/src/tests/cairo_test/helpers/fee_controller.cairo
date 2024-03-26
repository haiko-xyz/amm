// Core lib imports.
use starknet::syscalls::deploy_syscall;
use starknet::ContractAddress;

// Local imports.
use amm::tests::mocks::fee_controller::FeeController;
use amm::tests::common::params::{fee_controller_params, FeeControllerParams};
use amm::interfaces::IFeeController::{
    IFeeController, IFeeControllerDispatcher, IFeeControllerDispatcherTrait
};

pub fn deploy_fee_controller(swap_fee: u16) -> IFeeControllerDispatcher {
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    swap_fee.serialize(ref constructor_calldata);
    let (deployed_address, _) = deploy_syscall(
        FeeController::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), false
    )
        .unwrap();

    IFeeControllerDispatcher { contract_address: deployed_address }
}
