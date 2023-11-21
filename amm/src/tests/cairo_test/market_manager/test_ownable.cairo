// Core lib imports.
use starknet::testing::set_contract_address;

// Local imports.
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, transfer_owner, accept_owner
};
use amm::tests::common::params::{
    owner, default_transfer_owner_params, alice, bob
};


////////////////////////////////
// SETUP
////////////////////////////////

fn _before() -> IMarketManagerDispatcher {
    // Get default owner.
    let owner = owner();

    deploy_market_manager(owner)
}

#[test]
#[available_gas(100000000)]
fn test_transfer_and_accept_owner() {
    let market_manager = _before();
    let transfer_owner_params = default_transfer_owner_params();

    transfer_owner(market_manager, transfer_owner_params);

    accept_owner(market_manager, transfer_owner_params.new_owner);
    assert(market_manager.owner() == transfer_owner_params.new_owner, 'Owner transferred check');
}

#[test]
#[available_gas(100000000)]
fn test_transfer_then_update_owner_before_accepting() {
    let market_manager = _before();
    let mut transfer_owner_params = default_transfer_owner_params();

    transfer_owner(market_manager, transfer_owner_params);

    transfer_owner_params.new_owner = bob(); // new owner changed
    transfer_owner(market_manager, transfer_owner_params); // transfer ownership to another address

    assert(market_manager.owner() != transfer_owner_params.new_owner, 'Owner not transferred check 1');
    assert(market_manager.owner() == transfer_owner_params.owner, 'Owner transfer check 2');

    accept_owner(market_manager, transfer_owner_params.new_owner);

    assert(market_manager.owner() != alice(), 'Owner transferred check 3');
    assert(market_manager.owner() == bob(), 'Owner transferred check 4');
}


////////////////////////////////
// TESTS - failure cases
////////////////////////////////

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('OnlyOwner', 'ENTRYPOINT_FAILED',))]
fn test_transfer_owner_not_owner() {
    let market_manager = _before();
    let mut transfer_owner_params = default_transfer_owner_params();

    transfer_owner_params.owner = alice(); // changing owner
    transfer_owner(market_manager, transfer_owner_params);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('OnlyNewOwner', 'ENTRYPOINT_FAILED',))]
fn test_accept_owner_not_transferred() {
    let market_manager = _before();

    let transfer_owner_params = default_transfer_owner_params();
    transfer_owner(market_manager, transfer_owner_params);

    accept_owner(market_manager, bob());
}