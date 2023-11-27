// Core lib imports.
use cmp::{min, max};
use starknet::ContractAddress;
use dict::{Felt252Dict, Felt252DictTrait};

// Local imports.
use amm::libraries::constants::{OFFSET, MAX_LIMIT, MIN_LIMIT};
use amm::libraries::math::fee_math;
use amm::libraries::id;
use amm::libraries::liquidity_lib as liquidity_helpers;
use amm::types::core::{MarketState, LimitInfo};
use amm::types::i256::{i256, I256Trait, I256Zeroable};
use amm::types::i128::{i128, I128Zeroable, I128Trait};
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap, swap_multiple},
    token::{declare_token, deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, bob, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, to_e18_u128, approx_eq};

// External imports.
use snforge_std::{
    start_prank, stop_prank, PrintTrait, declare, ContractClass, ContractClassTrait, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before(
    manager: ContractClass, token: ContractClass, swap_fee: u16
) -> (IMarketManagerDispatcher, felt252, ERC20ABIDispatcher, ERC20ABIDispatcher) {
    // Deploy market manager.
    let market_manager = deploy_market_manager(manager, owner());

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();

    let base_token = deploy_token(token, base_token_params);
    let quote_token = deploy_token(token, quote_token_params);

    // Funds LP with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(100000000000000000000000000000000000000000);
    let initial_quote_amount = to_e28(10000000000000000000000000000000000000000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);
    fund(base_token, bob(), initial_base_amount);
    fund(quote_token, bob(), initial_quote_amount);
    approve(base_token, bob(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, bob(), market_manager.contract_address, initial_quote_amount);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = OFFSET;
    params.swap_fee_rate = swap_fee;
    params.width = 1;

    let market_id = create_market(market_manager, params);

    (market_manager, market_id, base_token, quote_token)
}

// Benchmark gas use for following cases:
//  1. MPALU: Add liquidity at previously uninitialised limits.
//  2. MPALI: Add liquidity at previously initialised limits.
//  3. MPALIU: Add liquidity at initialised lower, but previously uninitialised upper limit.
//  4. MPCF: Collect fees from position (position is only one at limits).
//  4. MPRL01: Remove liquidity with no accumulated fees (position is only one at limits).
//  5. MPRLFM: Remove liquidity with accumulated fees (position is only one at limits).
//  6. MPRL01: Remove liquidity with no accumulated fees (other positions exist at limits).
//  7. MPRLFM: Remove liquidity with accumulated fees (other positions exist at limits).

#[test]
fn test_create_position_uninitialised_limits() {
    let manager_class = declare('MarketManager');
    let erc20_class = declare_token();
    let (market_manager, market_id, base_token, quote_token) = before(
        manager_class, erc20_class, 30
    );

    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity = I128Trait::new(to_e18_u128(100000), false);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity
    );

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    'MPALU: start of test'.print();
    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let (base_amount, quote_amount, base_fees, quote_fees) = market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        );
    'create_position gas used'.print();
    (gas_before - testing::get_available_gas()).print();
    'MPALU: end of test'.print();
}

#[test]
fn test_create_position_initialised_limits() {
    let manager_class = declare('MarketManager');
    let erc20_class = declare_token();
    let (market_manager, market_id, base_token, quote_token) = before(
        manager_class, erc20_class, 30
    );

    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity = I128Trait::new(to_e18_u128(100000), false);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity
    );

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager.modify_position(
        params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
    );

    'MPALI: start of test'.print();
    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let (base_amount, quote_amount, base_fees, quote_fees) = market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        );
    'create_position gas used'.print();
    (gas_before - testing::get_available_gas()).print();
    'MPALI: end of test'.print(); 
}

#[test]
fn test_add_liquidity_to_initialised_lower_unintialised_upper() {
    let manager_class = declare('MarketManager');
    let erc20_class = declare_token();
    let (market_manager, market_id, base_token, quote_token) = before(
        manager_class, erc20_class, 30
    );

    let lower_limit = OFFSET - MIN_LIMIT;
    let upper_limit = OFFSET;
    let liquidity = I128Trait::new(to_e18_u128(100000), false);

    let params_1 = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity
    );

    let params_2 = modify_position_params(
        alice(),
        market_id,
        upper_limit - 10,
        OFFSET + 1000,
        liquidity
    );

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager.modify_position(
        params_1.market_id, params_1.lower_limit, params_1.upper_limit, params_1.liquidity_delta,
    );

    'MPALIU: start of test'.print();
    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let (base_amount, quote_amount, base_fees, quote_fees) = market_manager
        .modify_position(
            params_2.market_id, params_2.lower_limit, params_2.upper_limit, params_2.liquidity_delta,
        );
    'remove_position gas used'.print();
    (gas_before - testing::get_available_gas()).print();
    'MPALIU: end of test'.print();
}

#[test]
fn test_collect_fee_from_single_position() {
    let manager_class = declare('MarketManager');
    let erc20_class = declare_token();
    let (market_manager, market_id, base_token, quote_token) = before(
        manager_class, erc20_class, 30
    );

    let lower_limit = OFFSET - MIN_LIMIT;
    let upper_limit = OFFSET;
    let liquidity = I128Trait::new(to_e18_u128(100000), false);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity
    );

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager.modify_position(
        params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
    );

    market_manager.swap(market_id, false, 1000, true, Option::None, Option::None, Option::None);

    'MPCF: start of test'.print();
    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let (base_amount, quote_amount, base_fees, quote_fees) = market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, I128Trait::new(0, true),
        );
    (gas_before - testing::get_available_gas()).print();
    'MPCF: end of test'.print();
}

#[test]
fn test_remove_liquidity_no_fee_single_position() {
    let manager_class = declare('MarketManager');
    let erc20_class = declare_token();
    let (market_manager, market_id, base_token, quote_token) = before(
        manager_class, erc20_class, 30
    );

    let lower_limit = OFFSET - MIN_LIMIT;
    let upper_limit = OFFSET - MIN_LIMIT + market_manager.width(market_id);
    let liquidity_to_add = I128Trait::new(to_e18_u128(100000), false);
    let liquidity_to_remove = I128Trait::new(to_e18_u128(100000), true);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity_to_add
    );

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager.modify_position(
        params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
    );
    stop_prank(CheatTarget::One(market_manager.contract_address));
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    'MPRL01: start of test'.print();
    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, liquidity_to_remove,
        );
    'remove_position gas used'.print();
    (gas_before - testing::get_available_gas()).print();
    'MPRL01: end of test'.print();
}

#[test]
fn test_remove_liquidity_accumulated_fee_single_position() {
    let manager_class = declare('MarketManager');
    let erc20_class = declare_token();
    let (market_manager, market_id, base_token, quote_token) = before(
        manager_class, erc20_class, 30
    );

    let lower_limit = OFFSET + MAX_LIMIT - market_manager.width(market_id);
    let upper_limit = OFFSET + MAX_LIMIT;
    let liquidity_to_add = I128Trait::new(to_e18_u128(100000), false);
    let liquidity_to_remove = I128Trait::new(to_e18_u128(100000), true);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity_to_add
    );

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager.modify_position(
        params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
    );
    market_manager.swap(market_id, false, 1000, true, Option::None, Option::None, Option::None);
    stop_prank(CheatTarget::One(market_manager.contract_address));

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    'MPRLFM: start of test'.print();
    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let (base_amount, quote_amount, base_fees, quote_fees) = market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, liquidity_to_remove,
        );
    'remove_position gas used'.print();
    (gas_before - testing::get_available_gas()).print();
    'MPRLFM: end of test'.print();
}

#[test]
fn test_remove_liquidity_no_fee_other_position_exists() {
    let manager_class = declare('MarketManager');
    let erc20_class = declare_token();
    let (market_manager, market_id, base_token, quote_token) = before(
        manager_class, erc20_class, 30
    );

    let lower_limit = OFFSET + MAX_LIMIT - market_manager.width(market_id);
    let upper_limit = OFFSET + MAX_LIMIT;
    let liquidity_to_add = I128Trait::new(to_e18_u128(100000), false);
    let liquidity_to_remove = I128Trait::new(to_e18_u128(100000), true);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity_to_add
    );

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager.modify_position(
        params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
    );
    stop_prank(CheatTarget::One(market_manager.contract_address));
    start_prank(CheatTarget::One(market_manager.contract_address), bob());
    market_manager.modify_position(
        params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
    );
    stop_prank(CheatTarget::One(market_manager.contract_address));

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    'MPRL01: start of test'.print();
    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let (base_amount, quote_amount, base_fees, quote_fees) = market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, liquidity_to_remove,
        );
    'remove_position gas used'.print();
    (gas_before - testing::get_available_gas()).print();
    'MPRL01: end of test'.print();
}

#[test]
fn test_remove_liquidity_accumulated_fee_other_position_exists() {
    let manager_class = declare('MarketManager');
    let erc20_class = declare_token();
    let (market_manager, market_id, base_token, quote_token) = before(
        manager_class, erc20_class, 30
    );

    let lower_limit = OFFSET;
    let upper_limit = OFFSET + MAX_LIMIT;
    let liquidity_to_add = I128Trait::new(to_e18_u128(100000), false);
    let liquidity_to_remove = I128Trait::new(to_e18_u128(100000), true);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity_to_add
    );

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager.modify_position(
        params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
    );
    stop_prank(CheatTarget::One(market_manager.contract_address));
    start_prank(CheatTarget::One(market_manager.contract_address), bob());
    market_manager.modify_position(
        params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
    );
    market_manager.swap(market_id, true, 1000, true, Option::None, Option::None, Option::None);
    stop_prank(CheatTarget::One(market_manager.contract_address));

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    'MPRLFM: start of test'.print();
    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let (base_amount, quote_amount, base_fees, quote_fees) = market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, liquidity_to_remove,
        );
    'remove_position gas used'.print();
    (gas_before - testing::get_available_gas()).print();
    'MPRLFM: end of test'.print();
}