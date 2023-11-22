// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT, MIN_LIMIT};
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::i256::{i256, I256Trait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market
};
use amm::tests::cairo_test::helpers::token::{deploy_token};
use amm::tests::common::params::{
    owner, default_token_params, default_market_params
};
use amm::tests::common::utils::to_e28;

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
struct TestCase {
    lower_limit: u32,
    upper_limit: u32,
    liquidity: u256,
    base_exp: u256,
    quote_exp: u256,
}

////////////////////////////////
// SETUP
////////////////////////////////

fn _before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
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
#[available_gas(1000000000)]
fn test_create_market() {
    let (market_manager, base_token, quote_token) = _before();

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.width = 1;
    params.start_limit = OFFSET - 230260; // initial limit
    params.is_concentrated = true;
    params.allow_orders = true;
    params.allow_positions = true;

    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let market_id = create_market(market_manager, params);
    
    'create_market gas used'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // should be around 4143492
}
