use starknet::ContractAddress;

use amm::contracts::quoter::Quoter;
use amm::interfaces::IQuoter::{IQuoter, IQuoterDispatcher, IQuoterDispatcherTrait};

// External imports.
use snforge_std::{declare, ContractClassTrait};

fn deploy_quoter(owner: ContractAddress, market_manager: ContractAddress) -> IQuoterDispatcher {
    let contract = declare('Quoter');
    let contract_address = contract.deploy(@array![owner.into(), market_manager.into()]).unwrap();
    IQuoterDispatcher { contract_address }
}
