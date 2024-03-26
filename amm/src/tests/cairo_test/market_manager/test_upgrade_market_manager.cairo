// Core lib imports.
use starknet::contract_address_const;
use starknet::testing::set_contract_address;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::math::price_math;
use amm::libraries::constants::{OFFSET, MAX_LIMIT};
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::mocks::upgraded_market_manager::{
    UpgradedMarketManager, IUpgradedMarketManagerDispatcher, IUpgradedMarketManagerDispatcherTrait
};
use amm::tests::cairo_test::helpers::market_manager::{deploy_market_manager, create_market};
use amm::tests::cairo_test::helpers::token::deploy_token;
use amm::tests::common::params::{owner, alice, default_token_params, default_market_params};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher) {
    // Deploy market manager.
    let owner = owner();
    set_contract_address(owner);
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (_treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    (market_manager, base_token, quote_token)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_upgrade_market_manager() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token) = before();

    // Upgrade market manager.
    set_contract_address(owner());
    market_manager.upgrade(UpgradedMarketManager::TEST_CLASS_HASH.try_into().unwrap());

    // Calling owner returns existing owner.
    let upgraded_market_manager = IUpgradedMarketManagerDispatcher {
        contract_address: market_manager.contract_address
    };
    assert(upgraded_market_manager.owner() == owner(), 'Upgrade: owner');
}

#[test]
#[should_panic(expected: ('OnlyOwner', 'ENTRYPOINT_FAILED',))]
fn test_upgrade_market_manager_not_owner() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token) = before();

    // Upgrade market manager.
    set_contract_address(alice());
    market_manager.upgrade(UpgradedMarketManager::TEST_CLASS_HASH.try_into().unwrap());
}
