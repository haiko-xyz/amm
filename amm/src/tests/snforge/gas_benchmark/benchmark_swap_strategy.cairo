// Core lib imports.
use cmp::{min, max};
use starknet::ContractAddress;
use dict::{Felt252Dict, Felt252DictTrait};

// Local imports.
use amm::libraries::constants::{
    OFFSET, MIN_LIMIT, MIN_SQRT_PRICE, MAX_SQRT_PRICE, MAX_LIMIT
};
use amm::libraries::math::fee_math;
use amm::types::core::{SwapParams, PositionInfo};
use amm::libraries::id;
use amm::libraries::liquidity as liquidity_helpers;
use amm::types::core::{MarketState, LimitInfo};
use amm::types::i256::{i256, I256Trait, I256Zeroable};
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
    use amm::interfaces::IStrategy::{IStrategyDispatcher, IStrategyDispatcherTrait};
use amm::contracts::test::manual_strategy::{
    ManualStrategy, IManualStrategyDispatcher, IManualStrategyDispatcherTrait
};
use amm::tests::snforge::helpers::strategy::{deploy_strategy, initialise_strategy};
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

fn before(width: u32) -> (
    IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252, IManualStrategyDispatcher
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

    let strategy = deploy_strategy(owner());

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.width = width;
    params.start_limit = OFFSET; // initial limit
    params.strategy = strategy.contract_address;
    let market_id = create_market(market_manager, params);

    // Fund LPs with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000);
    let initial_quote_amount = to_e28(10000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    fund(base_token, owner(), initial_base_amount);
    fund(quote_token, owner(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);
    approve(base_token, owner(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, owner(), market_manager.contract_address, initial_quote_amount);
    approve(base_token, owner(), strategy.contract_address, initial_base_amount);
    approve(quote_token, owner(), strategy.contract_address, initial_quote_amount);

    // Fund strategy with initial token balances and approve market manager as spender.
    let base_amount = to_e28(500000000000000000);
    let quote_amount = to_e28(10000000000000000000);
    fund(base_token, strategy.contract_address, base_amount);
    fund(quote_token, strategy.contract_address, quote_amount);
    approve(base_token, strategy.contract_address, market_manager.contract_address, base_amount);
    approve(quote_token, strategy.contract_address, market_manager.contract_address, quote_amount);

    let lower_limit = OFFSET - 1000000;
    let upper_limit = OFFSET + 1000000;
    let liquidity = I256Trait::new(to_e18(100000), false);

    let mut params = modify_position_params(
        alice(),
        market_id,
        lower_limit,
        upper_limit,
        liquidity
    );
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        );
    stop_prank(CheatTarget::One(market_manager.contract_address));

    // Initialise strategy.
    initialise_strategy(
        strategy,
        owner(),
        'ETH-USDC Manual 1 0.3%',
        'ETH-USDC MANU-1-0.3%',
        market_manager.contract_address,
        market_id
    );
    (market_manager, base_token, quote_token, market_id, strategy)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_swap_no_position_updates() {
    let (market_manager, base_token, quote_token, market_id, strategy) = before(1);

    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let mut is_buy = true;
    let exact_input = true;
    let amount = 100;
    let sqrt_price = Option::Some(curr_sqrt_price + 1000);
    let threshold_amount = Option::Some(0);

    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    let mut swap_params = swap_params(
        strategy.contract_address, market_id, is_buy, exact_input, amount, sqrt_price, threshold_amount, Option::None,
    );

    'test start'.print();
    swap(market_manager, swap_params);
    '(SSNP) test end'.print();
}

#[test]
fn test_swap_one_position_update() {
    let (market_manager, base_token, quote_token, market_id, strategy) = before(1);
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.set_positions(OFFSET - MIN_LIMIT, OFFSET - 1, 0, 0);
    strategy.deposit(to_e18(100000000), 0);
    stop_prank(CheatTarget::One(strategy.contract_address));

    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let mut is_buy = true;
    let exact_input = true;
    let amount = 100;
    let sqrt_price = Option::Some(curr_sqrt_price + 1000);
    let threshold_amount = Option::Some(0);

    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    let mut swap_params = swap_params(
        strategy.contract_address, market_id, is_buy, exact_input, amount, sqrt_price, threshold_amount, Option::None,
    );

    'test start'.print();
    swap(market_manager, swap_params);
    '(SSOP) test end'.print();
}

#[test]
fn test_swap_both_position_update() {
    let (market_manager, base_token, quote_token, market_id, strategy) = before(1);
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.set_positions(OFFSET - MIN_LIMIT, OFFSET - 1, OFFSET + 1, OFFSET + MAX_LIMIT);
    strategy.deposit(to_e18(100000000), to_e18(100000000));
    stop_prank(CheatTarget::One(strategy.contract_address));

    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let mut is_buy = false;
    let exact_input = true;
    let amount = 1000;
    let sqrt_price = Option::Some(curr_sqrt_price - 1000);
    let threshold_amount = Option::Some(0);

    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    let mut swap_params = swap_params(
        strategy.contract_address, market_id, is_buy, exact_input, amount, sqrt_price, threshold_amount, Option::None,
    );

    'test start'.print();
    swap(market_manager, swap_params);
    '(SSBP) test end'.print();
}