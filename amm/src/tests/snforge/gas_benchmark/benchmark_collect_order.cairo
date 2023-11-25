// Core lib imports.
use cmp::{min, max};
use starknet::ContractAddress;
use dict::{Felt252Dict, Felt252DictTrait};

// Local imports.
use amm::libraries::constants::{OFFSET, MAX_LIMIT};
use amm::libraries::math::fee_math;
use amm::libraries::id;
use amm::libraries::liquidity as liquidity_helpers;
use amm::types::core::{MarketState, LimitInfo};
use amm::types::i256::{i256, I256Trait, I256Zeroable};
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap, swap_multiple},
    token::{declare_token, deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, bob, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, approx_eq};

// External imports.
use snforge_std::{
    start_prank, stop_prank, PrintTrait, declare, ContractClass, ContractClassTrait, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let manager_class = declare('MarketManager');
    let market_manager = deploy_market_manager(manager_class, owner);

    // Deploy tokens.
    let erc20_class = declare_token();
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(erc20_class, base_token_params);
    let quote_token = deploy_token(erc20_class, quote_token_params);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.width = 1;
    params.start_limit = OFFSET - 230260; // initial limit
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

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_collect_order() {
    let (market_manager, base_token, quote_token, market_id) = before();

    // Create limit order.
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    let liquidity = to_e28(1);
    let limit = OFFSET - 1000;
    let is_bid = false;

    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);

    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    market_manager.collect_order(market_id, order_id);

    'collect_order gas used'.print();
    (gas_before - testing::get_available_gas()).print(); 
    stop_prank(CheatTarget::One(market_manager.contract_address));
}

#[test]
fn test_collect_order_batch_filled() {
    let (market_manager, base_token, quote_token, market_id) = before();

    // Create limit order.
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    let liquidity = 10000;
    let limit = OFFSET;
    let is_bid = false;

    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);

    let swap_params = swap_params(alice(), market_id, true, true, 10000, Option::None, Option::None, Option::None);
    swap(market_manager, swap_params);

    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    market_manager.collect_order(market_id, order_id);

    'collect_order gas used'.print();
    (gas_before - testing::get_available_gas()).print(); 
    stop_prank(CheatTarget::One(market_manager.contract_address));
}