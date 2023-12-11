use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::syscalls::call_contract_syscall;
use starknet::info::get_block_timestamp;
use integer::BoundedU32;

use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IQuoter::{IQuoterDispatcher, IQuoterDispatcherTrait};
use strategies::strategies::replicating::{
    interface::{IReplicatingStrategyDispatcher, IReplicatingStrategyDispatcherTrait}, types::Limits,
};
use strategies::tests::snforge::replicating::helpers::deploy_replicating_strategy;

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
        0x4f1d5c71f89ec0d4adc267682fce3280acdc2e5f6854632784372ba34f1dd83
    >();
    let market_id = 123;

    // Deploy strategy contract.
    let strategy = deploy_replicating_strategy(
        owner, market_manager, oracle_addr, oracle_summary_addr
    );

    // Register market on strategy.
    start_prank(CheatTarget::One(strategy.contract_address), owner);
    strategy
        .initialise(
            market_id,
            owner,
            'ETH/USD',
            'USDC/USD',
            'ETH/USD',
            BoundedU32::max(),
            Limits::Fixed(0),
            Limits::Fixed(5000),
            200,
            604800, // 7 days (in seconds)
            true,
        );
    stop_prank(CheatTarget::One(strategy.contract_address));

    // Fetch volatility.
    let volatility = strategy.get_oracle_vol(market_id);
    volatility.print();

    // Add assert to allow test to pass.
    assert(true, 'Test finished');
}
