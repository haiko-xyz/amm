use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::syscalls::call_contract_syscall;
use starknet::info::get_block_timestamp;
use integer::BoundedU32;

use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IQuoter::{IQuoterDispatcher, IQuoterDispatcherTrait};
use strategies::strategies::replicating::{
    interface::{IReplicatingStrategyDispatcher, IReplicatingStrategyDispatcherTrait},
};
use strategies::tests::replicating::helpers::deploy_replicating_strategy;

use snforge_std::{start_prank, stop_prank, PrintTrait, CheatTarget};

#[test]
#[fork("TESTNET")]
fn test_pragma_oracle_forked_state() {
    let oracle_addr = contract_address_const::<
        0x06df335982dddce41008e4c03f2546fa27276567b5274c7d0c1262f3c2b5d167
    >();
    let oracle_summary_addr = contract_address_const::<
        0x6421fdd068d0dc56b7f5edc956833ca0ba66b2d5f9a8fea40932f226668b5c4
    >();
    let owner = contract_address_const::<
        0x2afc579c1a02e4e36b2717bb664bee705d749d581e150d1dd16311e3b3bb057
    >();
    let market_manager = contract_address_const::<
        0x889f55a7bb4f673281ab34499d0f506605febc5ab880f4c286472eaf67e20
    >();
    let market_id = 0x383fdd4406bdb35bda8978f61436ecf4c8b3abed6bb6017eb7f4b90ae589992;

    // Deploy strategy contract.
    let strategy = deploy_replicating_strategy(
        owner, market_manager, oracle_addr, oracle_summary_addr
    );

    // Add market to strategy.
    start_prank(CheatTarget::One(strategy.contract_address), owner);
    strategy
        .add_market(
            market_id,
            owner,
            'ETH',
            'USDC',
            3,
            600,
            0,
            5000,
            0,
            true,
        );
    stop_prank(CheatTarget::One(strategy.contract_address));

    // Fetch oracle price.
    let (price, is_valid) = strategy.get_oracle_price(market_id);
    'oracle price'.print();
    price.print();
    assert(is_valid, 'Oracle price: valid');
    assert(true, 'Test finished');
}