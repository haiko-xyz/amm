// Core lib imports.
use starknet::ContractAddress;

// Local imports.
use amm::libraries::constants::OFFSET;
use amm::libraries::math::{fee_math, price_math, liquidity_math};
use amm::types::i256::I256Trait;
use amm::contracts::market_manager::MarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market},
    token::{declare_token, deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, treasury, token_params, default_market_params, default_token_params,
};
use amm::tests::common::utils::{to_e28, to_e18, encode_sqrt_price};

// External imports.
use snforge_std::{
    start_prank, declare, PrintTrait, spy_events, SpyOn, EventSpy, EventAssertions, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, felt252, ERC20ABIDispatcher, ERC20ABIDispatcher) {
    // Deploy market manager.
    let class = declare('MarketManager');
    let market_manager = deploy_market_manager(class, owner());

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let erc20_class = declare_token();
    let base_token = deploy_token(erc20_class, base_token_params);
    let quote_token = deploy_token(erc20_class, quote_token_params);

    // Fund LP with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000000000000);
    let initial_quote_amount = to_e28(10000000000000000000000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = OFFSET;
    params.width = 1;
    let market_id = create_market(market_manager, params);

    (market_manager, market_id, base_token, quote_token)
}

////////////////////////////////
// TESTS
////////////////////////////////

// Event emission tests for following cases:
//  1. Swap without strategy, no limit orders filled - should fire `Swap` 
//  2. Swap without strategy, limit order fully filled - should fire `Swap` and `ModifyPosition`
//  3. Swap without strategy, limit order partially filled - should fire `Swap`
//  4. Swap with strategy, positions updated - should fire `Swap` and 2 x `ModifyPosition`

#[test]
fn test_swap_no_strategy_or_limit_orders_filled() {
    let (market_manager, market_id, base_token, quote_token) = before();

    start_prank(CheatTarget::One(market_manager.contract_address), alice());

    let mut spy = spy_events(SpyOn::One(market_manager.contract_address));

    // Creating an order should fire an event.
    let curr_limit = OFFSET;
    let width = 1;
    let is_bid = true;
    let limit = OFFSET - 1000;
    let liquidity_delta = to_e18(10000);
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity_delta);
    let order = market_manager.order(order_id);

    let amount = liquidity_math::liquidity_to_quote(
        price_math::limit_to_sqrt_price(limit, width),
        price_math::limit_to_sqrt_price(limit + width, width),
        I256Trait::new(liquidity_delta, false),
        true
    );

    spy
        .assert_emitted(
            @array![
                (
                    market_manager.contract_address,
                    MarketManager::Event::CreateOrder(
                        MarketManager::CreateOrder {
                            caller: alice(),
                            market_id,
                            order_id,
                            limit,
                            batch_id: order.batch_id,
                            is_bid,
                            amount: amount.val,
                        }
                    )
                ),
                (
                    market_manager.contract_address,
                    MarketManager::Event::ModifyPosition(
                        MarketManager::ModifyPosition {
                            caller: order.batch_id.try_into().unwrap(),
                            market_id,
                            lower_limit: limit,
                            upper_limit: limit + width,
                            liquidity_delta: I256Trait::new(liquidity_delta, false),
                            base_amount: I256Trait::new(0, false),
                            quote_amount: amount,
                            base_fees: 0,
                            quote_fees: 0,
                            is_limit_order: true,
                        }
                    )
                )
            ]
        );

    // Collect order should fire an event.
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);
    spy
        .assert_emitted(
            @array![
                (
                    market_manager.contract_address,
                    MarketManager::Event::ModifyPosition(
                        MarketManager::ModifyPosition {
                            caller: order.batch_id.try_into().unwrap(),
                            market_id,
                            lower_limit: limit,
                            upper_limit: limit + width,
                            liquidity_delta: I256Trait::new(liquidity_delta, true),
                            base_amount: I256Trait::new(0, false),
                            quote_amount: I256Trait::new(quote_amount, true),
                            base_fees: 0,
                            quote_fees: 0,
                            is_limit_order: true,
                        }
                    )
                ),
                (
                    market_manager.contract_address,
                    MarketManager::Event::CollectOrder(
                        MarketManager::CollectOrder {
                            caller: alice(),
                            market_id,
                            order_id,
                            limit,
                            batch_id: order.batch_id,
                            is_bid,
                            base_amount: 0,
                            quote_amount: quote_amount,
                        }
                    )
                ),
            ]
        );
}
