// Core lib imports.
use starknet::deploy_syscall;
use starknet::ContractAddress;
use starknet::testing::set_contract_address;

// Local imports.
use strategies::strategies::replicating::{
    replicating_strategy::{ReplicatingStrategy, IReplicatingStrategyDispatcher},
    mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
};

// External imports.
use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank};


fn deploy_mock_pragma_oracle(owner: ContractAddress,) -> IMockPragmaOracleDispatcher {
    let contract = declare('MockPragmaOracle');
    let contract_address = contract.deploy(@array![]).unwrap();
    IMockPragmaOracleDispatcher { contract_address }
}

fn deploy_replicating_strategy(owner: ContractAddress,) -> IReplicatingStrategyDispatcher {
    let contract = declare('ReplicatingStrategy');
    let contract_address = contract.deploy(@array![owner.into()]).unwrap();
    IReplicatingStrategyDispatcher { contract_address }
}
