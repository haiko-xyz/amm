use starknet::contract_address_const;
use starknet::testing::set_contract_address;

use amm::contracts::market_manager::MarketManager;
use amm::libraries::math::price_math;
use amm::libraries::constants::{OFFSET, MAX_LIMIT};
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IERC20::{IERC20Dispatcher, IERC20DispatcherTrait};
use amm::tests::helpers::contracts::upgraded_market_manager::{
    UpgradedMarketManager, IUpgradedMarketManagerDispatcher, IUpgradedMarketManagerDispatcherTrait
};
use amm::tests::helpers::actions::market_manager::{deploy_market_manager, create_market};
use amm::tests::helpers::actions::token::deploy_token;
use amm::tests::helpers::params::{owner, default_token_params, default_market_params};


////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, IERC20Dispatcher, IERC20Dispatcher) {
    // Deploy market manager.
    let owner = owner();
    set_contract_address(owner);
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    (market_manager, base_token, quote_token)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(40000000)]
fn test_upgrade_market_manager() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Upgrade market manager.
    set_contract_address(owner());
    market_manager.upgrade(UpgradedMarketManager::TEST_CLASS_HASH.try_into().unwrap());

    // Calling owner returns existing owner.
    let upgraded_market_manager = IUpgradedMarketManagerDispatcher {
        contract_address: market_manager.contract_address
    };
    assert(upgraded_market_manager.owner() == owner(), 'Upgrade: owner');
}
