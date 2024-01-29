// Core lib imports.
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::contracts::quoter::Quoter;
use amm::libraries::constants::{OFFSET, MAX_LIMIT};
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IQuoter::{IQuoterDispatcher, IQuoterDispatcherTrait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position, swap
};
use amm::tests::cairo_test::helpers::quoter::deploy_quoter;
use amm::tests::common::params::{owner, alice, default_token_params, default_market_params};
use amm::tests::common::utils::{to_e18, to_e18_u128, to_e28, encode_sqrt_price};

// External imports.
use openzeppelin::upgrades::interface::{IUpgradeableDispatcherTrait, IUpgradeableDispatcher};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, IQuoterDispatcher) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy quoter.
    let quoter = deploy_quoter(owner(), market_manager.contract_address);

    (market_manager, quoter)
}

#[test]
#[should_panic(expected: ('OnlyOwner', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_upgrade_quoter_not_owner() {
    // Deploy market manager and tokens.
    let (_market_manager, quoter) = before();

    // Upgrade market manager.
    set_contract_address(alice());
    let dispatcher = IUpgradeableDispatcher { contract_address: quoter.contract_address };
    dispatcher.upgrade(Quoter::TEST_CLASS_HASH.try_into().unwrap());
}
