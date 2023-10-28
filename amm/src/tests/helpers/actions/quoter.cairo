use starknet::ContractAddress;
use starknet::deploy_syscall;
use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};
use core::starknet::SyscallResultTrait;
use core::result::ResultTrait;
use array::ArrayTrait;

use amm::contracts::quoter::Quoter;
use amm::interfaces::IQuoter::{IQuoter, IQuoterDispatcher, IQuoterDispatcherTrait};

fn deploy_quoter(market_manager: ContractAddress) -> IQuoterDispatcher {
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    market_manager.serialize(ref constructor_calldata);

    let (deployed_address, _) = deploy_syscall(
        Quoter::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), false
    )
        .unwrap();

    IQuoterDispatcher { contract_address: deployed_address }
}
