use amm::tests::cairo_test::helpers::market_manager::deploy_market_manager;
use amm::tests::common::params::owner;
use amm::contracts::market_manager::MarketManager;
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};


////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_deploy_market_manager_initialises_owner() {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Check owner correctly initialised. 
    assert(market_manager.owner() == owner, 'Deploy: incorrect owner');
}
