// Core lib imports.
use cmp::{min, max};
use starknet::ContractAddress;
use dict::{Felt252Dict, Felt252DictTrait};

// Local imports.
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT};
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
    owner, alice, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, approx_eq};

// External imports.
use snforge_std::{
    start_prank, PrintTrait, declare, ContractClass, ContractClassTrait, CheatTarget
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

    // Fund LP with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(5000000000000000000000000000000000000000000);
    let initial_quote_amount = to_e28(100000000000000000000000000000000000000000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);

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
    let liquidity = I256Trait::new(to_e18(100000), false);

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
    let liquidity = I256Trait::new(to_e18(100000), false);

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

// TODO: add remaining cases.

// #[test]
// fn test_modify_position_after_swap() {
//     let manager_class = declare('MarketManager');
//     let erc20_class = declare_token();
//     let (market_manager, market_id, base_token, quote_token) = before(
//         manager_class, erc20_class, 30
//     );

//     let lower_limit = OFFSET - 1000;
//     let upper_limit = OFFSET + 1000;
//     let liquidity = I256Trait::new(to_e18(100000), false);

//     let params = modify_position_params(
//         alice(),
//         market_id,
//         lower_limit,
//         upper_limit,
//         liquidity
//     );

//     modify_position(market_manager, params);

//     let swap_params = swap_params(alice(), market_id, true, true, 10000, Option::None, Option::None, Option::None);
//     swap(market_manager, swap_params);

//     let gas_before = testing::get_available_gas();
//     gas::withdraw_gas().unwrap();
//     modify_position(market_manager, params);
//     'modify_position gas used'.print();
//     (gas_before - testing::get_available_gas()).print(); 

// }