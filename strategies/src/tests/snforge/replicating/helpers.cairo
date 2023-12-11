// Core lib imports.
use starknet::deploy_syscall;
use starknet::ContractAddress;
use starknet::testing::set_contract_address;

// Local imports.
use strategies::strategies::replicating::{
    replicating_strategy::ReplicatingStrategy, interface::IReplicatingStrategyDispatcher,
    test::mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
};

// External imports.
use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank};


fn deploy_mock_pragma_oracle(owner: ContractAddress,) -> IMockPragmaOracleDispatcher {
    let contract = declare('MockPragmaOracle');
    let contract_address = contract.deploy(@array![]).unwrap();
    IMockPragmaOracleDispatcher { contract_address }
}

fn deploy_replicating_strategy(
    owner: ContractAddress,
    market_manager: ContractAddress,
    oracle: ContractAddress,
    oracle_summary: ContractAddress,
) -> IReplicatingStrategyDispatcher {
    let contract = declare('ReplicatingStrategy');
    let calldata = array![
        owner.into(),
        'Replicating',
        'REPL',
        '1.0.0',
        market_manager.into(),
        oracle.into(),
        oracle_summary.into()
    ];
    let contract_address = contract.deploy(@calldata).unwrap();
    IReplicatingStrategyDispatcher { contract_address }
}
