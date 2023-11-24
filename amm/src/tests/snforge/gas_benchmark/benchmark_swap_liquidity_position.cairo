// Core lib imports.
use cmp::{min, max};
use starknet::ContractAddress;
use dict::{Felt252Dict, Felt252DictTrait};

// Local imports.
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT};
use amm::libraries::math::fee_math;
use amm::types::core::{SwapParams, PositionInfo};
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
    owner, alice, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, approx_eq};

// External imports.
use snforge_std::{
    start_prank, stop_prank, PrintTrait, declare, ContractClass, ContractClassTrait, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

fn before(width: u32, start_limit: u32) -> (
    IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252
) {
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
    params.width = width;
    params.start_limit = start_limit; // initial limit
    let market_id = create_market(market_manager, params);

    // Fund LPs with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(5000000000000000000);
    let initial_quote_amount = to_e28(1000000000000000000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    fund(base_token, owner(), initial_base_amount);
    fund(quote_token, owner(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);
    approve(base_token, owner(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, owner(), market_manager.contract_address, initial_quote_amount);

    (market_manager, base_token, quote_token, market_id)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_swap_zero_liquidity_no_limit_crossed() {
    let (market_manager, base_token, quote_token, market_id) = before(10, 10);

    let lower_limit = 20;
    let upper_limit = 30;
    let liquidity = I256Trait::new(to_e18(100000), false);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity
    );
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
    market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        );
    stop_prank(CheatTarget::One(market_manager.contract_address));

    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let mut is_buy = true;
    let exact_input = true;
    let amount = 5;
    let sqrt_price = Option::Some(curr_sqrt_price + 1000);

    let mut swap_params = swap_params(
        alice(), market_id, is_buy, exact_input, amount, sqrt_price, Option::None, Option::None,
    );

    'test start'.print();
    swap(market_manager, swap_params);
    '(SPZN) test end'.print();
}

#[test]
fn test_swap_high_liquidity_no_limit_crossed() {
    let (market_manager, base_token, quote_token, market_id) = before(10, 10);

    let lower_limit = 0;
    let upper_limit = 1000;
    let liquidity = I256Trait::new(to_e18(100000), false);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity
    );
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
    market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        );
    stop_prank(CheatTarget::One(market_manager.contract_address));

    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let mut is_buy = true;
    let exact_input = true;
    let amount = 10;

    let mut swap_params = swap_params(
        alice(), market_id, is_buy, exact_input, amount, Option::None, Option::None, Option::None,
    );

    'test start'.print();
    swap(market_manager, swap_params);
    '(SPHN) test end'.print();
}

#[test]
fn test_swap_zero_liquidity_one_limit_crossed() {
    let (market_manager, base_token, quote_token, market_id) = before(10, 10);

    let lower_limit = 20;
    let upper_limit = 1000;
    let liquidity = I256Trait::new(to_e18(100000), false);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity
    );
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
    market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        );
    stop_prank(CheatTarget::One(market_manager.contract_address));

    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let mut is_buy = true;
    let exact_input = true;
    let amount = 10;

    let mut swap_params = swap_params(
        alice(), market_id, is_buy, exact_input, amount, Option::None, Option::None, Option::None,
    );

    'test start'.print();
    swap(market_manager, swap_params);
    '(SPZ1) test end'.print();
}

#[test]
fn test_swap_high_liquidity_one_limit_crossed() {
    let (market_manager, base_token, quote_token, market_id) = before(1, 10000);

    let lower_limit = 0;
    let upper_limit = 10000;
    let liquidity = I256Trait::new(to_e18(1000000000), false);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity
    );
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
    market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        );
    stop_prank(CheatTarget::One(market_manager.contract_address));

    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let mut is_buy = false;
    let exact_input = true;
    let amount = 100;
    let sqrt_price = Option::Some(curr_sqrt_price - 1000);

    let mut swap_params = swap_params(
        alice(), market_id, is_buy, exact_input, amount, sqrt_price, Option::None, Option::None,
    );

    'test start'.print();
    swap(market_manager, swap_params);
    '(SPH1) test end'.print();
}

// WIP: trying to cross four limits
#[test]
fn test_swap_high_liquidity_four_limit_crossed() {
    let (market_manager, base_token, quote_token, market_id) = before(1, 10000);

    let lower_limit = 0;
    let upper_limit = 10000;
    let liquidity = I256Trait::new(to_e18(1000000000000000000000), false);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity
    );
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
    market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        );
    stop_prank(CheatTarget::One(market_manager.contract_address));

    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let mut is_buy = false;
    let exact_input = true;
    let amount = to_e18(100000000000);

    let mut swap_params = swap_params(
        alice(), market_id, is_buy, exact_input, amount, Option::None, Option::None, Option::None,
    );

    'test start'.print();
    swap(market_manager, swap_params);
    '(SPH1) test end'.print();
}
