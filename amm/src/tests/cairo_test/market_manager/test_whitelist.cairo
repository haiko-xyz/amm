// Core lib imports.
use starknet::contract_address_const;
use starknet::testing::set_contract_address;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::math::price_math;
use amm::libraries::constants::{OFFSET, MAX_LIMIT, MAX_WIDTH};
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, create_market_without_whitelisting
};
use amm::tests::cairo_test::helpers::token::deploy_token;
use amm::tests::common::params::{owner, alice, default_token_params, default_market_params};

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
    let (_treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    (market_manager, base_token, quote_token)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_create_market_whitelisted_works() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    create_market(market_manager, params);
}

#[test]
fn test_create_market_whitelisted_tokens_work() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Whitelist tokens.
    set_contract_address(owner());
    market_manager
        .whitelist_tokens(array![base_token.contract_address, quote_token.contract_address]);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    create_market_without_whitelisting(market_manager, params);
}

#[test]
#[should_panic(expected: ('NotWhitelisted', 'ENTRYPOINT_FAILED',))]
fn test_create_market_not_whitelisted() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Create market.
    set_contract_address(owner());
    market_manager
        .create_market(
            base_token.contract_address,
            quote_token.contract_address,
            1,
            contract_address_const::<0x0>(),
            10,
            contract_address_const::<0x0>(),
            OFFSET + 0,
            contract_address_const::<0x0>(),
            Option::None(()),
        );
}

#[test]
#[should_panic(expected: ('NotWhitelisted', 'ENTRYPOINT_FAILED',))]
fn test_create_market_whitelisted_pair_with_strategy() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Whitelist tokens.
    set_contract_address(owner());
    market_manager
        .whitelist_tokens(array![base_token.contract_address, quote_token.contract_address]);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.strategy = contract_address_const::<0x123>();
    create_market_without_whitelisting(market_manager, params);
}

#[test]
#[should_panic(expected: ('NotWhitelisted', 'ENTRYPOINT_FAILED',))]
fn test_create_market_whitelisted_pair_with_fee_controller() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Whitelist tokens.
    set_contract_address(owner());
    market_manager
        .whitelist_tokens(array![base_token.contract_address, quote_token.contract_address]);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.fee_controller = contract_address_const::<0x123>();
    create_market_without_whitelisting(market_manager, params);
}

#[test]
#[should_panic(expected: ('NotWhitelisted', 'ENTRYPOINT_FAILED',))]
fn test_create_market_whitelisted_pair_with_controller() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Whitelist tokens.
    set_contract_address(owner());
    market_manager
        .whitelist_tokens(array![base_token.contract_address, quote_token.contract_address]);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.controller = contract_address_const::<0x123>();
    create_market_without_whitelisting(market_manager, params);
}

#[test]
#[should_panic(expected: ('OnlyOwner', 'ENTRYPOINT_FAILED',))]
fn test_whitelist_market_not_owner() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token) = before();

    set_contract_address(alice());
    market_manager.whitelist_markets(array![123]);
}

#[test]
#[should_panic(expected: ('AlreadyWhitelisted', 'ENTRYPOINT_FAILED',))]
fn test_whitelist_market_twice() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Create market (whitelist both tokens).
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    let market_id = create_market(market_manager, params);

    market_manager.whitelist_markets(array![market_id]);
}
