use serde::Serde;
use core::result::ResultTrait;
use starknet::deploy_syscall;
use starknet::ContractAddress;

use amm::tests::common::contracts::fee_controller::FeeController;
use amm::tests::common::params::{fee_controller_params, FeeControllerParams};
use amm::interfaces::IFeeController::{
    IFeeController, IFeeControllerDispatcher, IFeeControllerDispatcherTrait
};

fn deploy_fee_controller() -> IFeeControllerDispatcher {
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    let (deployed_address, _) = deploy_syscall(
        FeeController::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), false
    )
        .unwrap();

    IFeeControllerDispatcher { contract_address: deployed_address }
}
