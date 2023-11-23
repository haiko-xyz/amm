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
use snforge_std::{start_prank, declare, PrintTrait, spy_events, SpyOn, EventSpy, EventAssertions};
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

// Tests for following cases:
//  1. Creating an order - should fire `CreateOrder` and `ModifyPosition`
//  2. 
#[test]
fn test_order_events() {
    let (market_manager, market_id, base_token, quote_token) = before();

    start_prank(market_manager.contract_address, alice());

    let mut spy = spy_events(SpyOn::One(market_manager.contract_address));
// // Creating a position should fire an event.
// let curr_limit = OFFSET;
// let width = 1;
// let lower_limit = OFFSET - 1000;
// let upper_limit = OFFSET + 1000;
// let mut liquidity_delta = I256Trait::new(to_e18(10000), false);
// let (base_amount, quote_amount, base_fees, quote_fees) = market_manager
//     .modify_position(market_id, lower_limit, upper_limit, liquidity_delta);

// let mut events_exp = array![
//     (
//         market_manager.contract_address,
//         MarketManager::Event::ModifyPosition(
//             MarketManager::ModifyPosition {
//                 caller: alice(),
//                 market_id,
//                 lower_limit,
//                 upper_limit,
//                 liquidity_delta,
//                 base_amount,
//                 quote_amount,
//                 base_fees,
//                 quote_fees,
//                 is_limit_order: false,
//             }
//         )
//     )
// ];

// // Swap so position has some fees.
// market_manager.swap(market_id, true, to_e18(1), true, Option::None(()), Option::None(()));

// // Collect fees should fire an event.
// liquidity_delta = I256Trait::new(0, false);
// let (base_amount_2, quote_amount_2, base_fees_2, quote_fees_2) = market_manager
//     .modify_position(market_id, lower_limit, upper_limit, liquidity_delta);
// events_exp
//     .append(
//         (
//             market_manager.contract_address,
//             MarketManager::Event::ModifyPosition(
//                 MarketManager::ModifyPosition {
//                     caller: alice(),
//                     market_id,
//                     lower_limit,
//                     upper_limit,
//                     liquidity_delta,
//                     base_amount: base_amount_2,
//                     quote_amount: quote_amount_2,
//                     base_fees: base_fees_2,
//                     quote_fees: quote_fees_2,
//                     is_limit_order: false,
//                 }
//             )
//         )
//     );

// // Collecting again should not fire an event.
// market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity_delta);

// // Removing liquidity should fire an event.
// liquidity_delta = I256Trait::new(to_e18(10000), true);
// let (base_amount_3, quote_amount_3, base_fees_3, quote_fees_3) = market_manager
//     .modify_position(market_id, lower_limit, upper_limit, liquidity_delta);
// events_exp
//     .append(
//         (
//             market_manager.contract_address,
//             MarketManager::Event::ModifyPosition(
//                 MarketManager::ModifyPosition {
//                     caller: alice(),
//                     market_id,
//                     lower_limit,
//                     upper_limit,
//                     liquidity_delta,
//                     base_amount: base_amount_3,
//                     quote_amount: quote_amount_3,
//                     base_fees: base_fees_3,
//                     quote_fees: quote_fees_3,
//                     is_limit_order: false,
//                 }
//             )
//         )
//     );

// // Check all events correctly fired.
// spy.assert_emitted(@events_exp);
}

#[test]
fn test_collect_partially_filled_order_events() {
    let (market_manager, market_id, base_token, quote_token) = before();

    start_prank(CheatTarget::One(market_manager.contract_address), alice());

    let mut spy = spy_events(SpyOn::One(market_manager.contract_address));

    // Creating an order should fire an event.
    let curr_limit = OFFSET;
    let width = 1;
    let is_bid = true;
    let limit = OFFSET - 1000;
    let liquidity_delta = to_e28(10000);
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
                ),
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
            ]
        );

    // Partially filling order should emit `Swap`.
    let is_buy = false;
    let (amount_in, amount_out, fees) = market_manager
        .swap(
            market_id, is_buy, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );
    let market_state = market_manager.market_state(market_id);
    spy
        .assert_emitted(
            @array![
                (
                    market_manager.contract_address,
                    MarketManager::Event::Swap(
                        MarketManager::Swap {
                            caller: alice(),
                            market_id,
                            is_buy,
                            exact_input: true,
                            amount_in,
                            amount_out,
                            fees,
                            end_limit: market_state.curr_limit,
                            end_sqrt_price: market_state.curr_sqrt_price,
                            market_liquidity: market_state.liquidity,
                            swap_id: 1,
                        }
                    )
                )
            ]
        );

    // Collect order should fire both `ModifyPosition` and `CollectOrder` events.
    let position = market_manager.position(market_id, order.batch_id, limit, limit + width);
    let lower_limit_info = market_manager.limit_info(market_id, limit);
    let upper_limit_info = market_manager.limit_info(market_id, limit + width);

    let (base_fees, quote_fees, _, _) = fee_math::get_fee_inside(
        position,
        lower_limit_info,
        upper_limit_info,
        limit,
        limit + width,
        market_state.curr_limit,
        market_state.base_fee_factor,
        market_state.quote_fee_factor,
    );
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
                            // base amount is different because fees are forfeited for partial fills
                            base_amount: I256Trait::new(999993999999996772, true),
                            quote_amount: I256Trait::new(quote_amount, true),
                            base_fees,
                            quote_fees,
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
                            base_amount,
                            quote_amount,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_collect_fully_filled_order_events() {
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
                ),
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
            ]
        );

    // Fully filling order should emit `Swap` and `ModifyPosition`.
    let is_buy = false;
    let (amount_in, amount_out, fees) = market_manager
        .swap(
            market_id, is_buy, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );

    let market_state = market_manager.market_state(market_id);
    let protocol_fees = fee_math::calc_fee(fees, market_state.protocol_share);
    let base_amount_exp = 50401149858254832;
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
                            base_amount: I256Trait::new(base_amount_exp, true),
                            quote_amount: I256Trait::new(0, true),
                            base_fees: fees - protocol_fees,
                            quote_fees: 0,
                            is_limit_order: true,
                        }
                    )
                ),
                (
                    market_manager.contract_address,
                    MarketManager::Event::Swap(
                        MarketManager::Swap {
                            caller: alice(),
                            market_id,
                            is_buy,
                            exact_input: true,
                            amount_in,
                            amount_out,
                            fees,
                            end_limit: market_state.curr_limit,
                            end_sqrt_price: market_state.curr_sqrt_price,
                            market_liquidity: market_state.liquidity,
                            swap_id: 1,
                        }
                    )
                )
            ]
        );

    // Collect order should fire `CollectOrder` only.
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);
    spy
        .assert_emitted(
            @array![
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
                            base_amount,
                            quote_amount,
                        }
                    )
                )
            ]
        );
}

