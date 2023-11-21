// Core lib imports.
use starknet::ContractAddress;
use starknet::deploy_syscall;

// Local imports.
use amm::tests::common::contracts::manual_strategy::{ManualStrategy, IManualStrategyDispatcher};

fn deploy_manual_strategy(owner: ContractAddress) -> IManualStrategyDispatcher {
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    owner.serialize(ref constructor_calldata);
    let (strategy_addr, _) = deploy_syscall(
        ManualStrategy::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), false
    )
        .unwrap();
    let strategy = IManualStrategyDispatcher { contract_address: strategy_addr };
    strategy
}
