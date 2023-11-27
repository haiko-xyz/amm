// Core lib imports.
use cmp::{min, max};
use starknet::ContractAddress;
use dict::{Felt252Dict, Felt252DictTrait};

// Local imports.
use amm::libraries::constants::{OFFSET, MAX_LIMIT};
use amm::libraries::math::fee_math;
use amm::types::core::{SwapParams, PositionInfo};
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
    owner, alice, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e28_u128, to_e18, to_e18_u128, approx_eq};

// External imports.
use snforge_std::{
    start_prank, stop_prank, PrintTrait, declare, ContractClass, ContractClassTrait, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

fn before(width: u32) -> (
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
    params.start_limit = 0; // initial limit
    let market_id = create_market(market_manager, params);

    // Fund LPs with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000000000000);
    let initial_quote_amount = to_e28(1000000000000000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    fund(base_token, owner(), initial_base_amount);
    fund(quote_token, owner(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);
    approve(base_token, owner(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, owner(), market_manager.contract_address, initial_quote_amount);

    // create order
    let liquidity = to_e18_u128(100);
    let limit = 10;
    let is_bid = false;
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager.create_order(market_id, is_bid, limit, liquidity);
    stop_prank(CheatTarget::One(market_manager.contract_address));
    (market_manager, base_token, quote_token, market_id)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_swap_limit_fully_filled() {
    let (market_manager, base_token, quote_token, market_id) = before(10);

    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let is_buy = true;
    let exact_input = true;
    let amount = 1;
    let sqrt_price = Option::Some(curr_sqrt_price + 1000000);
    let threshold_amount = Option::Some(0);

    let swap_params = swap_params(
        alice(), market_id, is_buy, exact_input, amount, sqrt_price, threshold_amount, Option::None,
    );

    'test start'.print();
    swap(market_manager, swap_params);
    '(SLLFF) test end'.print();
}

#[test]
fn test_swap_partially_filled() {
    let (market_manager, base_token, quote_token, market_id) = before(1);

    let liquidity = to_e18_u128(10000);
    let limit = 11;
    let is_bid = false;
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
    market_manager.create_order(market_id, is_bid, limit, liquidity);
    stop_prank(CheatTarget::One(market_manager.contract_address));
    
    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let is_buy = true;
    let exact_input = true;
    let amount = 10;
    let sqrt_price = Option::Some(curr_sqrt_price + 100000000000);
    let threshold_amount = Option::Some(0);

    let swap_params = swap_params(
        alice(), market_id, is_buy, exact_input, amount, sqrt_price, threshold_amount, Option::None,
    );

    'test start'.print();
    swap(market_manager, swap_params);
    '(SLLPF) test end'.print();
}
