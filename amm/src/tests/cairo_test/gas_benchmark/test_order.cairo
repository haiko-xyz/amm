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
    deploy_market_manager, create_market, modify_position
};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::utils::approx_eq;
use amm::tests::common::params::{
    owner, alice, bob, treasury, default_token_params, default_market_params, modify_position_params
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

fn _before(
    width: u32, is_concentrated: bool, allow_orders: bool, allow_positions: bool
) -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.width = width;
    params.start_limit = OFFSET - 230260; // initial limit
    params.is_concentrated = is_concentrated;
    params.allow_orders = allow_orders;
    params.allow_positions = allow_positions;
    let market_id = create_market(market_manager, params);

    // Fund LPs with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000);
    let initial_quote_amount = to_e28(10000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    fund(base_token, bob(), initial_base_amount);
    fund(quote_token, bob(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);
    approve(base_token, bob(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, bob(), market_manager.contract_address, initial_quote_amount);

    (market_manager, base_token, quote_token, market_id)
}

fn before(
    width: u32
) -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
    _before(width, true, true, true)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(1000000000)]
fn test_create_order() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create limit order.
    set_contract_address(alice());
    let liquidity = to_e28(1);
    let limit = OFFSET - 1000;
    let is_bid = false;

    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let _ = market_manager.create_order(market_id, is_bid, limit, liquidity);

    'create_order gas used'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // should be around 14386022
}

#[test]
#[available_gas(1000000000)]
fn test_collect_order() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create limit order.
    set_contract_address(alice());
    let liquidity = to_e28(1);
    let limit = OFFSET - 1000;
    let is_bid = false;

    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);

    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    market_manager.collect_order(market_id, order_id);

    'collect_order gas used'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // should be around 14413738
}