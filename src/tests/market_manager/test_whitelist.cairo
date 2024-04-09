// Core lib imports.
use starknet::contract_address_const;

// Local imports.

// Haiko imports.
use haiko_lib::math::price_math;
use haiko_lib::constants::{OFFSET, MAX_LIMIT, MAX_WIDTH};
use haiko_lib::interfaces::IMarketManager::{
    IMarketManager, IMarketManagerDispatcher, IMarketManagerDispatcherTrait
};
use haiko_lib::helpers::actions::{
    market_manager::{deploy_market_manager, create_market, create_market_without_whitelisting},
    token::deploy_token,
};
use haiko_lib::helpers::params::{owner, alice, default_token_params, default_market_params};

// External imports.
use snforge_std::{start_prank, stop_prank, CheatTarget, declare};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher) {
    // Deploy market manager.
    let market_manager_class = declare("MarketManager");
    let market_manager = deploy_market_manager(market_manager_class, owner());

    // Deploy tokens.
    let (_treasury, base_token_params, quote_token_params) = default_token_params();
    let erc20_class = declare("ERC20");
    let base_token = deploy_token(erc20_class, @base_token_params);
    let quote_token = deploy_token(erc20_class, @quote_token_params);

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
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
    market_manager
        .whitelist_tokens(array![base_token.contract_address, quote_token.contract_address]);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    create_market_without_whitelisting(market_manager, params);
}

#[test]
#[should_panic(expected: ('NotWhitelisted',))]
fn test_create_market_not_whitelisted() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Create market.
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
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
#[should_panic(expected: ('NotWhitelisted',))]
fn test_create_market_whitelisted_pair_with_strategy() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Whitelist tokens.
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
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
#[should_panic(expected: ('NotWhitelisted',))]
fn test_create_market_whitelisted_pair_with_fee_controller() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Whitelist tokens.
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
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
#[should_panic(expected: ('NotWhitelisted',))]
fn test_create_market_whitelisted_pair_with_controller() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Whitelist tokens.
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
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
#[should_panic(expected: ('OnlyOwner',))]
fn test_whitelist_market_not_owner() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token) = before();

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager.whitelist_markets(array![123]);
}

#[test]
#[should_panic(expected: ('AlreadyWhitelisted',))]
fn test_whitelist_market_twice() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token) = before();

    // Create market (whitelist both tokens).
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    let market_id = create_market(market_manager, params);

    start_prank(CheatTarget::One(market_manager.contract_address), owner());
    market_manager.whitelist_markets(array![market_id]);
}
