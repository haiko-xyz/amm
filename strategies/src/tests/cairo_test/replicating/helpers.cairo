use starknet::deploy_syscall;
use starknet::ContractAddress;
use starknet::testing::set_contract_address;

use strategies::strategies::replicating::{
    replicating_strategy::ReplicatingStrategy,
    interface::{IReplicatingStrategyDispatcher, IReplicatingStrategyDispatcherTrait},
    test::mock_pragma_oracle::{
        MockPragmaOracle, IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait
    }
};

fn deploy_mock_pragma_oracle(owner: ContractAddress,) -> IMockPragmaOracleDispatcher {
    let constructor_calldata = ArrayTrait::<felt252>::new();
    let (deployed_address, _) = deploy_syscall(
        MockPragmaOracle::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), false
    )
        .unwrap();

    IMockPragmaOracleDispatcher { contract_address: deployed_address }
}

fn deploy_replicating_strategy(
    owner: ContractAddress,
    market_manager: ContractAddress,
    oracle: ContractAddress,
    oracle_summary: ContractAddress
) -> IReplicatingStrategyDispatcher {
    set_contract_address(owner);

    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    owner.serialize(ref constructor_calldata);
    'Replicating'.serialize(ref constructor_calldata);
    'REPL'.serialize(ref constructor_calldata);
    '1.0.0'.serialize(ref constructor_calldata);
    market_manager.serialize(ref constructor_calldata);
    oracle.serialize(ref constructor_calldata);
    oracle_summary.serialize(ref constructor_calldata);

    let (deployed_address, _) = deploy_syscall(
        ReplicatingStrategy::TEST_CLASS_HASH.try_into().unwrap(),
        0,
        constructor_calldata.span(),
        false
    )
        .unwrap();

    IReplicatingStrategyDispatcher { contract_address: deployed_address }
}
