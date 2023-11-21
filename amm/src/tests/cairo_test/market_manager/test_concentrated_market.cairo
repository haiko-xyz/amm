// Core lib imports.
use starknet::contract_address_const;
use starknet::testing::set_contract_address;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::math::price_math;
use amm::libraries::constants::{OFFSET, MIN_LIMIT, MAX_LIMIT, MAX_WIDTH};
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::i256::I256Trait;
use amm::tests::cairo_test::helpers::market_manager::{deploy_market_manager, create_market};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::params::{owner, alice, default_token_params, default_market_params};
use amm::tests::common::utils::{to_e18, to_e28};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Fund LPs with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000);
    let initial_quote_amount = to_e28(10000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);

    (market_manager, base_token, quote_token)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(40000000)]
fn test_enable_concentrated() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.is_concentrated = false;
    let market_id = create_market(market_manager, params);

    // Place positions across whole range.
    set_contract_address(alice());
    let lower_limit = OFFSET - MIN_LIMIT;
    let upper_limit = OFFSET + MAX_LIMIT;
    let liquidity = I256Trait::new(to_e18(100000), false);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity);

    // Enable concentrated.
    set_contract_address(owner());
    market_manager.enable_concentrated(market_id);
}

#[test]
#[should_panic(expected: ('OnlyOwner', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_enable_concentrated_not_owner() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.is_concentrated = false;
    let market_id = create_market(market_manager, params);

    // Enable concentrated.
    set_contract_address(alice());
    market_manager.enable_concentrated(market_id);
}

#[test]
#[should_panic(expected: ('AlreadyConcentrated', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_enable_concentrated_already_concentrated() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    let market_id = create_market(market_manager, params);

    // Enable concentrated.
    market_manager.enable_concentrated(market_id);
}
