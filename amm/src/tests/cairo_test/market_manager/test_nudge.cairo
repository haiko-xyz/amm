// Core lib imports.
use starknet::contract_address_const;
use starknet::testing::set_contract_address;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::math::price_math;
use amm::libraries::constants::OFFSET;
use amm::types::i128::I128Trait;
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::cairo_test::helpers::market_manager::{deploy_market_manager, create_market};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::params::{owner, alice, default_token_params, default_market_params};
use amm::tests::common::utils::{to_e18_u128, to_e28};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (_treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.width = 10;
    params.start_limit = 7906620 - 0;
    let market_id = create_market(market_manager, params);

    // Fund LPs with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000);
    let initial_quote_amount = to_e28(10000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);

    (market_manager, base_token, quote_token, market_id)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(40000000)]
fn test_nudge() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token, market_id) = before();

    // LP places a limit order.
    set_contract_address(alice());
    let offset = price_math::offset(10);
    market_manager.create_order(market_id, true, offset - 100, to_e18_u128(1));

    // Nudge price lower.
    set_contract_address(owner());
    market_manager.nudge(market_id, offset - 50);
    let mut market_state = market_manager.market_state(market_id);
    assert(market_state.curr_limit == offset - 50, 'Nudge 1: curr limit');
    assert(
        market_state.curr_sqrt_price == price_math::limit_to_sqrt_price(offset - 50, 10),
        'Nudge 1: curr sqrt price'
    );

    // Nudge price higher.
    market_manager.nudge(market_id, offset + 1000);
    market_state = market_manager.market_state(market_id);
    assert(market_state.curr_limit == offset + 1000, 'Nudge 2: curr limit');
    assert(
        market_state.curr_sqrt_price == price_math::limit_to_sqrt_price(offset + 1000, 10),
        'Nudge 2: curr sqrt price'
    );
}

#[test]
#[should_panic(expected: ('OnlyOwner', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_nudge_not_owner() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token, market_id) = before();

    set_contract_address(alice());
    let offset = price_math::offset(10);
    market_manager.nudge(market_id, offset + 1000);
}

#[test]
#[should_panic(expected: ('LimitInvalid', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_nudge_crosses_bid() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token, market_id) = before();

    // LP places a limit order.
    set_contract_address(alice());
    let offset = price_math::offset(10);
    market_manager.create_order(market_id, true, offset - 100, to_e18_u128(1));

    // Nudge price lower.
    set_contract_address(owner());
    market_manager.nudge(market_id, offset - 200);
}

#[test]
#[should_panic(expected: ('LimitInvalid', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_nudge_on_bid_boundary() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token, market_id) = before();

    // LP places a position.
    set_contract_address(alice());
    let offset = price_math::offset(10);
    market_manager
        .modify_position(
            market_id, offset - 100, offset - 0, I128Trait::new(to_e18_u128(1), false)
        );

    // Nudge price lower.
    set_contract_address(owner());
    market_manager.nudge(market_id, offset - 20);
}

#[test]
#[should_panic(expected: ('LimitInvalid', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_nudge_crosses_ask() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token, market_id) = before();

    // LP places a limit order.
    set_contract_address(alice());
    let offset = price_math::offset(10);
    market_manager.create_order(market_id, false, offset + 100, to_e18_u128(1));

    // Nudge price higher.
    set_contract_address(owner());
    market_manager.nudge(market_id, offset + 200);
}


#[test]
#[should_panic(expected: ('ActiveLiq', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_nudge_on_ask_boundary() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token, market_id) = before();

    // LP places a position.
    set_contract_address(alice());
    let offset = price_math::offset(10);
    market_manager
        .modify_position(
            market_id, offset - 0, offset + 100, I128Trait::new(to_e18_u128(1), false)
        );

    // Nudge price higher.
    set_contract_address(owner());
    market_manager.nudge(market_id, offset + 20);
}

#[test]
#[should_panic(expected: ('ActiveLiq', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_nudge_active_liquidity() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token, market_id) = before();

    // LP places a position.
    set_contract_address(alice());
    let offset = price_math::offset(10);
    market_manager
        .modify_position(
            market_id, offset - 100, offset + 100, I128Trait::new(to_e18_u128(1), false)
        );

    // Nudge price higher.
    set_contract_address(owner());
    market_manager.nudge(market_id, offset + 20);
}

#[test]
#[should_panic(expected: ('SameLimit', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_nudge_same_limit() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token, market_id) = before();

    // LP places a position.
    set_contract_address(alice());
    let offset = price_math::offset(10);
    market_manager
        .modify_position(
            market_id, offset - 100, offset - 10, I128Trait::new(to_e18_u128(1), false)
        );

    // Nudge price.
    set_contract_address(owner());
    market_manager.nudge(market_id, offset);
}

#[test]
#[should_panic(expected: ('LimitOF', 'ENTRYPOINT_FAILED',))]
#[available_gas(40000000)]
fn test_nudge_limit_overflow() {
    // Deploy market manager and tokens.
    let (market_manager, _base_token, _quote_token, market_id) = before();

    // LP places a position.
    set_contract_address(alice());
    let offset = price_math::offset(10);
    market_manager
        .modify_position(
            market_id, offset - 100, offset - 10, I128Trait::new(to_e18_u128(1), false)
        );

    // Nudge price.
    set_contract_address(owner());
    market_manager.nudge(market_id, 15813251);
}
