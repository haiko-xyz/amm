// Core lib imports.
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::libraries::id;
use amm::libraries::math::math;
use amm::libraries::constants::OFFSET;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::core::{MarketState, OrderBatch};
use amm::types::i256::{i256, I256Trait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position
};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::params::{
    owner, alice, bob, charlie, treasury, default_token_params, default_market_params,
    modify_position_params
};
use amm::tests::common::utils::to_e28;

// External imports.
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before(width: u32) -> (IMarketManagerDispatcher, IERC20Dispatcher, IERC20Dispatcher, felt252) {
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
    params.start_limit = OFFSET - 0; // initial limit
    let market_id = create_market(market_manager, params);

    // Fund LPs with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000);
    let initial_quote_amount = to_e28(10000000);

    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);

    fund(base_token, bob(), initial_base_amount);
    fund(quote_token, bob(), initial_quote_amount);
    approve(base_token, bob(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, bob(), market_manager.contract_address, initial_quote_amount);

    fund(base_token, charlie(), initial_base_amount);
    fund(quote_token, charlie(), initial_quote_amount);
    approve(base_token, charlie(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, charlie(), market_manager.contract_address, initial_quote_amount);

    (market_manager, base_token, quote_token, market_id)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(100000000)]
fn test_create_bid_order_initialises_order_and_batch() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create limit order.
    set_contract_address(alice());
    let liquidity = to_e28(1);
    let limit = OFFSET - 1000;
    let is_bid = true;
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);
    let base_amount_exp = 0;
    let quote_amount_exp = 49750500827450308946577;

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    let position = market_manager
        .position(id::position_id(market_id, order.batch_id, limit, limit + 1));

    // Run checks.
    assert(order.liquidity == liquidity, 'Create bid: liquidity');
    assert(batch.filled == false, 'Create bid: batch filled');
    assert(batch.limit == limit, 'Create bid: batch limit');
    assert(batch.is_bid == is_bid, 'Create bid: batch direction');
    assert(batch.base_amount == base_amount_exp, 'Create bid: batch base amt');
    assert(batch.quote_amount == quote_amount_exp, 'Create bid: batch quote amt');
    assert(position.liquidity == liquidity, 'Create bid: position liq');
    assert(position.base_fee_factor_last == 0, 'Create bid: position qff');
    assert(position.quote_fee_factor_last == 0, 'Create bid: position bff');
}

#[test]
#[available_gas(100000000)]
fn test_create_ask_order_initialises_order_and_batch() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create limit order.
    set_contract_address(alice());
    let liquidity = to_e28(1);
    let limit = OFFSET + 1000;
    let is_bid = false;
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);
    let base_amount_exp = 49750252076811799929167;
    let quote_amount_exp = 0;

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    let position = market_manager
        .position(id::position_id(market_id, order.batch_id, limit, limit + 1));

    // Run checks.
    assert(order.liquidity == liquidity, 'Create ask: amount');
    assert(batch.filled == false, 'Create ask: batch filled');
    assert(batch.limit == limit, 'Create ask: batch limit');
    assert(batch.is_bid == is_bid, 'Create ask: batch direction');
    assert(batch.base_amount == base_amount_exp, 'Create ask: batch base amt');
    assert(batch.quote_amount == quote_amount_exp, 'Create ask: batch quote amt');
    assert(position.liquidity == liquidity, 'Create ask: position liq');
    assert(position.base_fee_factor_last == 0, 'Create order: position qff');
    assert(position.quote_fee_factor_last == 0, 'Create ask: position bff');
}

#[test]
#[available_gas(100000000)]
fn test_create_multiple_bid_orders() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create first limit order.
    set_contract_address(alice());
    let limit = OFFSET - 1000;
    let is_bid = true;
    let mut liquidity = to_e28(1);
    let mut batch_liquidity = liquidity;
    let mut order_id = market_manager.create_order(market_id, is_bid, limit, to_e28(1));
    let mut quote_amount_exp = 49750500827450308946577;
    let mut batch_quote_amount_exp = quote_amount_exp;

    // Fetch limit order, batch and position.
    set_contract_address(bob());
    let mut order = market_manager.order(order_id);
    let mut batch = market_manager.batch(order.batch_id);
    assert(batch.liquidity == liquidity, 'Create bid 1: liquidity');
    assert(batch.base_amount == 0, 'Create bid 1: batch base amount');
    assert(batch.quote_amount == quote_amount_exp, 'Create bid 1: batch quote amt');

    // Create second limit order.
    liquidity = to_e28(2);
    batch_liquidity += liquidity;
    order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);
    quote_amount_exp = 99501001654900617893154;
    batch_quote_amount_exp += quote_amount_exp;

    // Fetch limit order, batch and position.
    order = market_manager.order(order_id);
    batch = market_manager.batch(order.batch_id);
    assert(order.liquidity == liquidity, 'Create bid 2: liquidity');
    assert(batch.liquidity == batch_liquidity, 'Create bid 2: batch liquidity');
    assert(batch.base_amount == 0, 'Create bid 2: batch base amt');
    assert(batch.quote_amount == batch_quote_amount_exp, 'Create bid 2: batch quote amt');
}

#[test]
#[available_gas(100000000)]
fn test_create_multiple_ask_orders() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create first limit order.
    set_contract_address(alice());
    let limit = OFFSET + 1000;
    let is_bid = false;
    let mut liquidity = to_e28(1);
    let mut batch_liquidity = liquidity;
    let mut order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);
    let mut base_amount_exp = 49750252076811799929167;
    let mut batch_base_amount_exp = base_amount_exp;

    // Fetch limit order, batch and position.
    let mut order = market_manager.order(order_id);
    let mut batch = market_manager.batch(order.batch_id);
    assert(order.liquidity == liquidity, 'Create ask 1: liquidity');
    assert(batch.liquidity == liquidity, 'Create ask 1: batch liquidity');
    assert(batch.base_amount == base_amount_exp, 'Create ask 1: batch base amt');
    assert(batch.quote_amount == 0, 'Create ask 1: batch quote amt');

    // Create second limit order.
    set_contract_address(bob());
    liquidity = to_e28(2);
    batch_liquidity += liquidity;
    order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);
    base_amount_exp = 99500504153623599858334;
    batch_base_amount_exp += base_amount_exp;

    // Fetch limit order, batch and position.
    order = market_manager.order(order_id);
    batch = market_manager.batch(order.batch_id);
    assert(order.liquidity == liquidity, 'Create ask 2: liquidity');
    assert(batch.liquidity == batch_liquidity, 'Create ask 2: batch liquidity');
    assert(batch.base_amount == batch_base_amount_exp, 'Create ask 2: batch base amt');
    assert(batch.quote_amount == 0, 'Create ask 2: batch quote amt');
}

#[test]
#[available_gas(1000000000)]
fn test_swap_fully_fills_bid_limit_orders() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create first limit order.
    set_contract_address(alice());
    let is_bid = true;
    let width = 1;
    let limit = OFFSET - 1000;
    let liquidity_1 = to_e28(1000000);
    let order_id_1 = market_manager.create_order(market_id, is_bid, limit, liquidity_1);
    let quote_amount_1 = 49750500827450308946577000000;
    let fees_1 = 151204356800905303095964200;

    // Create second limit order.
    set_contract_address(bob());
    let liquidity_2 = to_e28(500000);
    let order_id_2 = market_manager.create_order(market_id, is_bid, limit, liquidity_2);
    let quote_amount_2 = 24875250413725154473288500000;

    // Liquidity to base amount, add fees less protocol fees
    let base_amount_exp = 75601724787382248832071653874;

    // Create random range liquidity position which should be ignored when filling limit orders.
    market_manager
        .modify_position(market_id, OFFSET - 600, OFFSET - 500, I256Trait::new(to_e28(1), false));

    // Create third limit order (fallback liquidity so swap doesn't fail).
    let other_limit = OFFSET - 1100;
    market_manager.create_order(market_id, is_bid, other_limit, to_e28(1500000));

    // Swap sell.
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, !is_bid, to_e28(10), true, Option::None(()), Option::None(()));

    // Fetch limit order, batch and position.
    let order_1 = market_manager.order(order_id_1);
    let order_2 = market_manager.order(order_id_2);
    let batch = market_manager.batch(order_1.batch_id);
    let lower_limit_info = market_manager.limit_info(market_id, limit);
    let upper_limit_info = market_manager.limit_info(market_id, limit + width);

    assert(order_1.liquidity == liquidity_1, 'Create bid 1: liquidity');
    assert(order_2.liquidity == liquidity_2, 'Create bid 2: liquidity');
    assert(batch.liquidity == liquidity_1 + liquidity_2, 'Create bid: batch liquidity');
    assert(batch.filled == true, 'Create bid: batch filled');
    assert(batch.quote_amount == 0, 'Create bid: batch quote amt');
    batch.base_amount.print();
    assert(batch.base_amount == base_amount_exp, 'Create bid: batch base amt');
    assert(lower_limit_info.liquidity == 0, 'Create bid: lower limit liq');
    assert(upper_limit_info.liquidity == 0, 'Create bid: upper limit liq');
}

#[test]
#[available_gas(1000000000)]
fn test_swap_fully_fills_ask_limit_orders() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create first limit order.
    set_contract_address(alice());
    let is_bid = false;
    let width = 1;
    let limit = OFFSET + 1000;
    let liquidity_1 = to_e28(1000000);
    let order_id_1 = market_manager.create_order(market_id, is_bid, limit, liquidity_1);
    let base_amount_1 = 49750252076811799929166657173;

    // Create second limit order.
    set_contract_address(bob());
    let liquidity_2 = to_e28(500000);
    let order_id_2 = market_manager.create_order(market_id, is_bid, limit, liquidity_2);
    let base_amount_2 = 24875126038405899964583328587;

    // Liquidity to quote amount, add fees less protocol fees
    let quote_amount_exp = 75602102795061168908553000000;

    // Create random range liquidity position which should be ignored when filling limit orders.
    market_manager
        .modify_position(market_id, OFFSET + 500, OFFSET + 600, I256Trait::new(to_e28(1), false));

    // Create third limit order (fallback liquidity so swap doesn't fail).
    let other_limit = OFFSET + 1100;
    market_manager.create_order(market_id, is_bid, other_limit, to_e28(1500000));

    // Swap buy.
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, !is_bid, to_e28(10), true, Option::None(()), Option::None(()));

    // Fetch limit order, batch and position.
    let order_1 = market_manager.order(order_id_1);
    let order_2 = market_manager.order(order_id_2);
    let batch = market_manager.batch(order_1.batch_id);
    let lower_limit_info = market_manager.limit_info(market_id, limit);
    let upper_limit_info = market_manager.limit_info(market_id, limit + width);

    assert(order_1.liquidity == liquidity_1, 'Create ask 1: liquidity');
    assert(order_2.liquidity == liquidity_2, 'Create ask 2: liquidity');
    assert(batch.liquidity == liquidity_1 + liquidity_2, 'Create ask: batch liquidity');
    assert(batch.filled == true, 'Create ask: batch filled');
    assert(batch.base_amount == 0, 'Create ask: batch base amt');
    assert(batch.quote_amount == quote_amount_exp, 'Create ask: batch quote amt');
    assert(lower_limit_info.liquidity == 0, 'Create ask: lower limit liq');
    assert(upper_limit_info.liquidity == 0, 'Create ask: upper limit liq');
}

#[test]
#[available_gas(100000000)]
fn test_create_and_collect_unfilled_bid_order() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Snapshot user balance before.
    set_contract_address(alice());
    let base_balance_before = base_token.balance_of(alice());
    let quote_balance_before = quote_token.balance_of(alice());

    // Create limit order.
    let is_bid = true;
    let mut limit = OFFSET - 1000;
    let liquidity = to_e28(1000000);
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);
    let quote_amount_exp = 49750500827450308946577000000;

    // Collect limit order.
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let base_balance_after = base_token.balance_of(alice());
    let quote_balance_after = quote_token.balance_of(alice());

    // Fetch order and batch. Run checks.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    assert(quote_amount == quote_amount_exp, 'Collect bid: quote amount');
    assert(base_amount == 0, 'Collect bid: base amount');
    assert(order.liquidity == 0, 'Collect bid: order liquidity');
    assert(batch.liquidity == 0, 'Collect bid: batch liquidity');
    assert(batch.filled == false, 'Collect bid: batch filled');
    assert(batch.base_amount == 0, 'Collect bid: batch base amount');
    assert(batch.quote_amount == 0, 'Collect bid: batch quote amount');
    assert(base_balance_after == base_balance_before, 'Collect bid: base balance');
    assert(quote_balance_after == quote_balance_before, 'Collect bid: quote balance');
}

#[test]
#[available_gas(100000000)]
fn test_create_and_collect_unfilled_ask_order() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Snapshot user balance before.
    set_contract_address(alice());
    let quote_balance_before = quote_token.balance_of(alice());
    let base_balance_before = base_token.balance_of(alice());

    // Create limit order.
    let is_bid = false;
    let mut limit = OFFSET + 1000;
    let liquidity = to_e28(1000000);
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);
    let base_amount_exp = 49750252076811799929166657173;

    // Collect limit order.
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let base_balance_after = base_token.balance_of(alice());
    let quote_balance_after = quote_token.balance_of(alice());

    // Fetch order and batch. Run checks.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    assert(base_amount == base_amount_exp, 'Collect bid: base amount');
    assert(quote_amount == 0, 'Collect bid: quote amount');
    assert(order.liquidity == 0, 'Collect bid: order liquidity');
    assert(batch.liquidity == 0, 'Collect bid: batch liquidity');
    assert(batch.filled == false, 'Collect bid: batch filled');
    assert(batch.base_amount == 0, 'Collect bid: batch base amount');
    assert(batch.quote_amount == 0, 'Collect bid: batch quote amount');
    assert(base_balance_after == base_balance_before - 0, 'Collect bid: base balance');
    assert(quote_balance_after == quote_balance_before, 'Collect bid: quote balance');
}

#[test]
#[available_gas(150000000)]
fn test_create_and_collect_fully_filled_bid_order() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Snapshot user balance before.
    let base_balance_before = base_token.balance_of(alice());
    let quote_balance_before = quote_token.balance_of(alice());

    // Create first limit order.
    set_contract_address(alice());
    let is_bid = true;
    let mut limit = OFFSET - 1000;
    let liquidity_1 = to_e28(1000000);
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity_1);
    let base_amount_exp = 50401149858254832554714435916;
    let quote_amount_exp = 49750500827450308946577000000;

    // Create second limit order.
    set_contract_address(bob());
    let liquidity_2 = to_e28(500000);
    market_manager.create_order(market_id, is_bid, limit, liquidity_2);
    let base_amount_exp_2 = 25200574929127416277357217958;
    let quote_amount_exp_2 = 24875250413725154473288500000;

    // Create third limit order (fallback liquidity so swap doesn't fail).
    limit = OFFSET - 1100;
    market_manager.create_order(market_id, is_bid, limit, to_e28(1500000));

    // Swap sell.
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, !is_bid, to_e28(10), true, Option::None(()), Option::None(()));

    // Collect limit order.
    set_contract_address(alice());
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let quote_balance_after = quote_token.balance_of(alice());
    let base_balance_after = base_token.balance_of(alice());

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    assert(base_amount == base_amount_exp, 'Collect bid: base amount');
    assert(quote_amount == 0, 'Collect bid: quote amount');
    assert(order.liquidity == 0, 'Collect bid: order liquidity');
    assert(batch.liquidity == liquidity_2, 'Collect bid: batch liquidity');
    assert(batch.filled == true, 'Collect bid: batch filled');
    assert(batch.base_amount == base_amount_exp_2, 'Collect bid: batch base amount');
    assert(batch.quote_amount == 0, 'Collect bid: batch quote amount');
    assert(
        base_balance_after == base_balance_before + base_amount_exp, 'Collect bid: base balance'
    );
    assert(
        quote_balance_after == quote_balance_before - quote_amount_exp, 'Collect bid: quote balance'
    );
}

#[test]
#[available_gas(150000000)]
fn test_create_and_collect_fully_filled_ask_order() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Snapshot user balance before.
    let quote_balance_before = quote_token.balance_of(alice());
    let base_balance_before = base_token.balance_of(alice());

    // Create first limit order.
    set_contract_address(alice());
    let is_bid = false;
    let mut limit = OFFSET + 1000;
    let liquidity_1 = to_e28(1000000);
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity_1);
    let base_amount_exp = 49750252076811799929166657173;
    let quote_amount_exp = 50401401863374112605702000000;

    // Create second limit order.
    set_contract_address(bob());
    let liquidity_2 = to_e28(500000);
    market_manager.create_order(market_id, is_bid, limit, liquidity_2);
    let base_amount_exp_2 = 24875126038405899964583328587;
    let quote_amount_exp_2 = 25200700931687056302851000000;

    let total_quote_amount_exp = 75602102795061168908553000000;

    // Create third limit order (fallback liquidity so swap doesn't fail).
    limit = OFFSET + 1100;
    market_manager.create_order(market_id, is_bid, limit, to_e28(1500000));

    // Swap buy.
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, !is_bid, to_e28(10), true, Option::None(()), Option::None(()));

    // Collect limit order.
    set_contract_address(alice());
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let quote_balance_after = quote_token.balance_of(alice());
    let base_balance_after = base_token.balance_of(alice());

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    assert(base_amount == 0, 'Collect ask: base amount');
    assert(quote_amount == quote_amount_exp, 'Collect ask: quote amount');
    assert(order.liquidity == 0, 'Collect ask: order liquidity');
    assert(batch.liquidity == liquidity_2, 'Collect ask: batch liquidity');
    assert(batch.filled == true, 'Collect ask: batch filled');
    assert(batch.base_amount == 0, 'Collect ask: batch base amount');
    assert(batch.quote_amount == quote_amount_exp_2, 'Collect ask: batch quote amount');
    assert(
        base_balance_after == base_balance_before - base_amount_exp, 'Collect ask: base balance'
    );
    assert(
        quote_balance_after == quote_balance_before + quote_amount_exp, 'Collect ask: quote balance'
    );
}

#[test]
#[available_gas(150000000)]
fn test_create_and_collect_partially_filled_bid_order() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Snapshot user balance before.
    let base_balance_before = base_token.balance_of(bob());
    let quote_balance_before = quote_token.balance_of(bob());

    // Create first limit order.
    set_contract_address(bob());
    let is_bid = true;
    let mut limit = OFFSET - 1000;
    let liquidity_1 = to_e28(500000);
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity_1);
    let quote_amount_exp = 24875250413725154473288500000;
    let amount_filled_exp = 19741713750297465584247500000;
    let amount_unfilled_exp = 5133536663427688889041000000;
    let amount_earned_exp = 19999880000000000000000000000;

    // Create second limit order.
    set_contract_address(alice());
    let liquidity_2 = to_e28(1000000);
    market_manager.create_order(market_id, is_bid, limit, liquidity_2);
    let quote_amount_exp_2 = 49750500827450308946577000000;
    let amount_filled_exp_2 = 39483427500594931168495000000;
    let amount_unfilled_exp_2 = 10267073326855377778082000000;
    let amount_earned_exp_2 = 39999760000000000000000000000;

    // Swap sell (partially filled against limit orders).
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, !is_bid, to_e28(6), true, Option::None(()), Option::None(()));

    // Collect limit order.
    set_contract_address(bob());
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let base_balance_after = base_token.balance_of(bob());
    let quote_balance_after = quote_token.balance_of(bob());

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    assert(base_amount == amount_earned_exp, 'Collect bid: base amount');
    assert(quote_amount == amount_unfilled_exp, 'Collect bid: quote amount');
    assert(order.liquidity == 0, 'Collect bid: order liquidity');
    assert(batch.liquidity == liquidity_2, 'Collect bid: batch liquidity');
    assert(batch.filled == false, 'Collect bid: batch filled');
    assert(batch.base_amount == amount_earned_exp_2, 'Collect bid: batch base amount');
    assert(batch.quote_amount == amount_unfilled_exp_2, 'Collect bid: batch quote amount');
    assert(
        base_balance_after == base_balance_before + amount_earned_exp, 'Collect bid: base balance'
    );
    assert(
        quote_balance_after == quote_balance_before - amount_filled_exp,
        'Collect bid: quote balance'
    );
}

#[test]
#[available_gas(150000000)]
fn test_create_and_collect_partially_filled_ask_order() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Snapshot user balance before.
    let base_balance_before = base_token.balance_of(bob());
    let quote_balance_before = quote_token.balance_of(bob());

    // Create first limit order.
    set_contract_address(bob());
    let is_bid = false;
    let mut limit = OFFSET + 1000;
    let liquidity_1 = to_e28(500000);
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity_1);
    let base_amount_exp = 24875126038405899964583328587;
    let amount_filled_exp = 19741516335525794238392802523;
    let amount_unfilled_exp = 5133609702880105726190526064;
    let amount_earned_exp = 19999880000000000000000000000;

    // Create second limit order.
    set_contract_address(alice());
    let liquidity_2 = to_e28(1000000);
    market_manager.create_order(market_id, is_bid, limit, liquidity_2);
    let base_amount_exp_2 = 49750252076811799929166657173;
    let amount_filled_exp_2 = 39483032671051588476785605044;
    let amount_unfilled_exp_2 = 10267219405760211452381052130;
    let amount_earned_exp_2 = 39999760000000000000000000000;

    // Swap buy (partially filled against limit orders).
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, !is_bid, to_e28(6), true, Option::None(()), Option::None(()));

    // Collect limit order.
    set_contract_address(bob());
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let quote_balance_after = quote_token.balance_of(bob());
    let base_balance_after = base_token.balance_of(bob());

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);

    assert(base_amount == amount_unfilled_exp, 'Collect ask: base amount');
    assert(quote_amount == amount_earned_exp, 'Collect ask: quote amount');
    assert(order.liquidity == 0, 'Collect ask: order liquidity');
    assert(batch.liquidity == liquidity_2, 'Collect ask: batch liquidity');
    assert(batch.filled == false, 'Collect ask: batch filled');
    assert(batch.base_amount == amount_unfilled_exp_2, 'Collect ask: batch base amount');
    assert(batch.quote_amount == amount_earned_exp_2, 'Collect ask: batch quote amount');
    assert(
        base_balance_after == base_balance_before - amount_filled_exp, 'Collect ask: base balance'
    );
    assert(
        quote_balance_after == quote_balance_before + amount_earned_exp,
        'Collect ask: quote balance'
    );
}

#[test]
#[available_gas(1000000000)]
fn test_partially_filled_bid_correctly_unfills() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Snapshot user balance before.
    let base_balance_before = base_token.balance_of(bob());
    let quote_balance_before = quote_token.balance_of(bob());

    // Create limit order.
    set_contract_address(bob());
    let is_bid = true;
    let mut limit = OFFSET - 1000;
    let liquidity = to_e28(1500000);
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);
    let quote_amount_exp = 74625751241175463419865500000;

    // Swap sell (partial fill).
    let (amount_in_sell, amount_out_sell, fees_sell) = market_manager
        .swap(market_id, !is_bid, to_e28(6), true, Option::None(()), Option::None(()));
    let base_amount_sell_exp = 59999640000000000000000000000; // earned incl. fees
    let quote_amount_sell_exp = 59225141250892396752742500000; // filled

    // Swap buy (unfill).
    let (amount_in_buy, amount_out_buy, fees_buy) = market_manager
        .swap(market_id, is_bid, to_e28(4), true, Option::None(()), Option::None(()));
    let base_amount_buy_exp = 40280607892236366896911482291; // repaid
    let quote_amount_buy_exp = 39999760000000000000000000000; // unfilled (incl. fees)

    // Snapshot user balance after.
    let base_balance_after = base_token.balance_of(bob());
    let quote_balance_after = quote_token.balance_of(bob());

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);

    assert(order.liquidity == liquidity, 'Unfill bid: order liquidity');
    assert(batch.liquidity == liquidity, 'Unfill bid: batch liquidity');
    assert(batch.filled == false, 'Unfill bid: batch filled');
    assert(
        batch.quote_amount == quote_amount_exp - quote_amount_sell_exp + quote_amount_buy_exp,
        'Unfill bid: batch quote amount'
    );
    assert(
        batch.base_amount == base_amount_sell_exp - base_amount_buy_exp,
        'Unfill bid: batch base amount'
    );
}

#[test]
#[available_gas(1000000000)]
fn test_partially_filled_ask_correctly_unfills() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Snapshot user balance before.
    let base_balance_before = base_token.balance_of(bob());
    let quote_balance_before = quote_token.balance_of(bob());

    // Create first limit order.
    set_contract_address(bob());
    let is_bid = false;
    let mut limit = OFFSET + 1000;
    let liquidity = to_e28(1500000);
    let order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);
    let base_amount_exp = 74625378115217699893749985760;

    // Swap buy (partial fill).
    let (amount_in_sell, amount_out_sell, fees_sell) = market_manager
        .swap(market_id, !is_bid, to_e28(6), true, Option::None(()), Option::None(()));
    let base_amount_sell_exp = 59224549006577382715178407566; // filled
    let quote_amount_sell_exp = 59999640000000000000000000000; // earned incl. fees

    // Swap sell (unfill).
    let (amount_in_buy, amount_out_buy, fees_buy) = market_manager
        .swap(market_id, is_bid, to_e28(4), true, Option::None(()), Option::None(()));
    let base_amount_buy_exp = 39999760000000000000000000000; // unfilled (incl. fees)
    let quote_amount_buy_exp = 40281010696178757375688500000; // repaid

    // Snapshot user balance after.
    let quote_balance_after = quote_token.balance_of(bob());
    let base_balance_after = base_token.balance_of(bob());

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);

    assert(order.liquidity == liquidity, 'Unfill ask: order liquidity');
    assert(batch.liquidity == liquidity, 'Unfill ask: batch amount in');
    assert(batch.filled == false, 'Unfill ask: batch filled');
    assert(
        batch.base_amount == base_amount_exp - base_amount_sell_exp + base_amount_buy_exp,
        'Unfill ask: batch base amount'
    );
    assert(
        batch.quote_amount == quote_amount_sell_exp - quote_amount_buy_exp,
        'Unfill bid: batch quote amount'
    );
}

#[test]
#[available_gas(1000000000)]
fn test_fill_bid_advances_batch_nonce() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create first (bid) limit order.
    set_contract_address(bob());
    let is_bid = true;
    let limit = OFFSET - 1000;
    market_manager.create_order(market_id, is_bid, limit, to_e28(500000));

    // Create fallback liquidity position.
    market_manager
        .modify_position(
            market_id, OFFSET - 1200, OFFSET - 1100, I256Trait::new(to_e28(1000000), false)
        );

    // Snapshot batch nonce before.
    let nonce_before = market_manager.limit_info(market_id, limit).nonce;

    // Swap sell.
    market_manager.swap(market_id, !is_bid, to_e28(6), true, Option::None(()), Option::None(()));

    // Create second (ask) limit order.
    set_contract_address(bob());
    let is_bid = false;
    market_manager.create_order(market_id, is_bid, limit, to_e28(1000000));

    // Snapshot batch nonce after.
    let nonce_after = market_manager.limit_info(market_id, limit).nonce;

    // Check nonce increased.
    assert(nonce_after == nonce_before + 1, 'Nonce after');
}

#[test]
#[available_gas(1000000000)]
fn test_fill_ask_advances_batch_nonce() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create first (ask) limit order.
    set_contract_address(bob());
    let is_bid = false;
    let limit = OFFSET + 1000;
    market_manager.create_order(market_id, is_bid, limit, to_e28(500000));

    // Create fallback liquidity position.
    market_manager
        .modify_position(
            market_id, OFFSET + 1100, OFFSET + 1200, I256Trait::new(to_e28(1000000), false)
        );

    // Snapshot batch nonce before.
    let nonce_before = market_manager.limit_info(market_id, limit).nonce;

    // Swap sell.
    market_manager.swap(market_id, !is_bid, to_e28(6), true, Option::None(()), Option::None(()));

    // Create second (ask) limit order.
    set_contract_address(bob());
    let is_bid = true;
    market_manager.create_order(market_id, is_bid, limit, to_e28(1000000));

    // Snapshot batch nonce after.
    let nonce_after = market_manager.limit_info(market_id, limit).nonce;

    // Check nonce increased.
    assert(nonce_after == nonce_before + 1, 'Nonce after');
}

#[test]
#[available_gas(1000000000)]
fn test_limit_orders_misc() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create orders:
    //  - Ask [1000]: 200000 (Bob)
    //  - Ask [900]: 150000 (Alice), 100000 (Bob)
    //  - Curr price [0]
    //  - Bid [-900]: 50000 (Alice), 100000 (Bob)
    //  - Bid [-1000]: 200000 (Alice)
    set_contract_address(alice());
    let liquidity_bid_a1 = to_e28(50000);
    let bid_a1 = market_manager.create_order(market_id, true, OFFSET - 900, liquidity_bid_a1);
    let liquidity_bid_a2 = to_e28(200000);
    let bid_a2 = market_manager.create_order(market_id, true, OFFSET - 1000, liquidity_bid_a2);
    let liquidity_ask_a1 = to_e28(150000);
    let ask_a1 = market_manager.create_order(market_id, false, OFFSET + 900, liquidity_ask_a1);

    set_contract_address(bob());
    let liquidity_bid_b1 = to_e28(100000);
    let bid_b1 = market_manager.create_order(market_id, true, OFFSET - 900, liquidity_bid_b1);
    let liquidity_ask_b1 = to_e28(100000);
    let ask_b1 = market_manager.create_order(market_id, false, OFFSET + 900, liquidity_ask_b1);
    let liquidity_ask_b2 = to_e28(200000);
    let ask_b2 = market_manager.create_order(market_id, false, OFFSET + 1000, liquidity_ask_b2);

    // Snapshot balances.
    let market_base_start = market_manager.reserves(base_token.contract_address);
    let market_quote_start = market_manager.reserves(quote_token.contract_address);
    let alice_base_start = base_token.balance_of(alice());
    let alice_quote_start = quote_token.balance_of(alice());
    let bob_base_start = base_token.balance_of(bob());
    let bob_quote_start = quote_token.balance_of(bob());
    let charlie_base_start = base_token.balance_of(charlie());
    let charlie_quote_start = quote_token.balance_of(charlie());

    // Sell to fill both bid orders at -900 and partially fill one at -1000.
    set_contract_address(charlie());
    let (amount_in_1, amount_out_1, fees_1) = market_manager
        .swap(market_id, false, to_e28(1), true, Option::None(()), Option::None(()));

    // Collect one of the filled orders.
    set_contract_address(alice());
    let (base_collect_1, quote_collect_1) = market_manager.collect_order(market_id, bid_a1);

    // Fetch state.
    let mut market_state = market_manager.market_state(market_id);
    let order_bid_a1 = market_manager.order(bid_a1);
    let order_bid_a2 = market_manager.order(bid_a2);
    let order_bid_b1 = market_manager.order(bid_b1);
    let batch_neg_900 = market_manager.batch(order_bid_a1.batch_id);
    let batch_neg_1000 = market_manager.batch(order_bid_a2.batch_id);
    let mut market_base_reserves = market_manager.reserves(base_token.contract_address);
    let mut market_quote_reserves = market_manager.reserves(quote_token.contract_address);
    let mut alice_base_balance = base_token.balance_of(alice());
    let mut alice_quote_balance = quote_token.balance_of(alice());
    let mut bob_base_balance = base_token.balance_of(bob());
    let mut bob_quote_balance = quote_token.balance_of(bob());

    // Check state.
    assert(amount_in_1 == to_e28(1), 'Amount in 1');
    assert(amount_out_1 == 9878318364512459259506950000, 'Amount out 1');
    assert(_approx_eq(fees_1, 30000000000000000000000000, 1), 'Fees 1');
    assert(base_collect_1 == 2518797785417929711264524858, 'Base collect 1');
    assert(quote_collect_1 == 0, 'Quote collect 1');
    assert(
        market_state == MarketState {
            liquidity: to_e28(200000),
            curr_limit: OFFSET - 1000,
            protocol_share: 20,
            curr_sqrt_price: 9950162731123922544094402921,
            is_concentrated: true,
            base_fee_factor: 187406629087480932662,
            quote_fee_factor: 0,
        },
        'Market state 1'
    );
    assert(order_bid_a1.liquidity == 0, 'Order a1: liquidity');
    assert(order_bid_b1.liquidity == liquidity_bid_b1, 'Order b1: liquidity');
    assert(order_bid_a2.liquidity == liquidity_bid_a2, 'Order a2: liquidity');
    assert(
        batch_neg_900 == OrderBatch {
            liquidity: liquidity_bid_b1,
            filled: true,
            limit: OFFSET - 900,
            is_bid: true,
            base_amount: 5037595570835859422529049718,
            quote_amount: 0,
        },
        'Batch -900'
    );
    assert(
        batch_neg_1000 == OrderBatch {
            liquidity: liquidity_bid_a2,
            filled: false,
            limit: OFFSET - 1000,
            is_bid: true,
            base_amount: 2443501305114041550455592201,
            quote_amount: 7538089126968944009690000000,
        },
        'Batch -1000'
    );
    'MARKET BASE RESERVES'.print();
    market_base_reserves.print();
    'MARKET QUOTE RESERVES'.print();
    market_quote_reserves.print();
    assert(market_base_reserves == 29875035954502256465732274092, 'Market base reserves');
    assert(market_quote_reserves == 7538089126968944009690000000, 'Market quote reserves');
    assert(alice_base_balance == alice_base_start + base_collect_1, 'Alice base balance');
    assert(
        alice_quote_balance == to_e28(10000000) - 12438869274153842282609250000,
        'Alice quote balance'
    );
    assert(bob_base_balance == bob_base_start, 'Bob base balance');
    assert(
        bob_quote_balance == to_e28(10000000) - 4977538217327560986587700000, 'Bob quote balance'
    );

    // Buy to unfill last bid order and partially fill 2 ask orders.
    let (amount_in_2, amount_out_2, fees_2) = market_manager
        .swap(market_id, true, to_e28(1), true, Option::None(()), Option::None(()));

    // Collect a partially filled ask order at 900.
    let (base_collect_2, quote_collect_2) = market_manager.collect_order(market_id, ask_b1);

    // Collect unfilled order at 1000.
    let (base_collect_3, quote_collect_3) = market_manager.collect_order(market_id, ask_b2);

    // Fetch state again.
    market_state = market_manager.market_state(market_id);
    let order_ask_a1 = market_manager.order(ask_a1);
    let order_ask_b1 = market_manager.order(ask_b1);
    let order_ask_b2 = market_manager.order(ask_b2);
    let batch_900 = market_manager.batch(order_ask_b1.batch_id);
    let batch_1000 = market_manager.batch(order_ask_b2.batch_id);
    market_base_reserves = market_manager.reserves(base_token.contract_address);
    market_quote_reserves = market_manager.reserves(quote_token.contract_address);

    // Verify state.
    assert(amount_in_2 == to_e28(1), 'Amount in 2');
    assert(amount_out_2 == 9926480658583945067498077765, 'Amount out 2');
    assert(_approx_eq(fees_2, 30000000000000000000000000, 1), 'Fees 2');
    assert(base_collect_2 == 1981413314869032219787770622, 'Base collect 2');
    assert(quote_collect_2 == 3032268461977485344182387162, 'Quote collect 2');
    assert(base_collect_3 == 9950050415362359985833331435, 'Base collect 3');
    assert(quote_collect_3 == 0, 'Quote collect 3');
    assert(
        market_state == MarketState {
            liquidity: to_e28(250000),
            curr_limit: OFFSET + 900,
            protocol_share: 20,
            curr_sqrt_price: 10045131407988586929877373380,
            is_concentrated: true,
            base_fee_factor: 187406629087480932662,
            quote_fee_factor: 127003290922098522197,
        },
        'Market state 2'
    );
    assert(order_ask_a1.liquidity == liquidity_ask_a1, 'Order a1: liquidity');
    assert(order_ask_b1.liquidity == 0, 'Order b1: liquidity');
    assert(order_ask_b2.liquidity == 0, 'Order b2: liquidity');
    assert(
        batch_900 == OrderBatch {
            liquidity: liquidity_ask_a1,
            filled: false,
            limit: OFFSET + 900,
            is_bid: false,
            base_amount: 2972119972303548329681655934,
            quote_amount: 4548438692966228016273580743,
        },
        'Batch 900'
    );
    assert(
        batch_1000 == OrderBatch {
            liquidity: 0,
            filled: false,
            limit: OFFSET + 1000,
            is_bid: false,
            base_amount: 0,
            quote_amount: 0,
        },
        'Batch 1000'
    );

    // Create a new orders at -900 and 900.
    market_manager.create_order(market_id, true, OFFSET - 900, to_e28(1));
    market_manager.create_order(market_id, false, OFFSET + 1000, to_e28(1));

    // Verify nonce increase handled correctly. 
    let limit_info_neg_900 = market_manager.limit_info(market_id, OFFSET - 900);
    let limit_info_900 = market_manager.limit_info(market_id, OFFSET + 900);
    assert(limit_info_neg_900.nonce == 1, 'Nonce -900');
    assert(limit_info_900.nonce == 0, 'Nonce 900');
}

////////////////////////////////
// TESTS - failure cases
////////////////////////////////

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('NotLimitOrder', 'ENTRYPOINT_FAILED',))]
fn test_create_bid_above_curr_limit_reverts() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);
    market_manager.create_order(market_id, true, 8388609, to_e28(1));
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('NotLimitOrder', 'ENTRYPOINT_FAILED',))]
fn test_create_bid_at_curr_limit_reverts() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);
    market_manager.create_order(market_id, true, 8388608, to_e28(1));
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('NotLimitOrder', 'ENTRYPOINT_FAILED',))]
fn test_create_ask_curr_limit_reverts() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);
    market_manager.create_order(market_id, false, 8388608, to_e28(1));
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('NotLimitOrder', 'ENTRYPOINT_FAILED',))]
fn test_create_ask_at_curr_limit_reverts() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);
    market_manager.create_order(market_id, false, 8388608, to_e28(1));
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('OrderAmtZero', 'ENTRYPOINT_FAILED',))]
fn test_create_order_zero_liquidity() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);
    market_manager.create_order(market_id, true, 8388508, 0);
}

////////////////////////////////
// INTERNAL HELPERS
////////////////////////////////

fn _approx_eq(x: u256, y: u256, tolerance: u256) -> bool {
    if x > y {
        x - y <= tolerance
    } else {
        y - x <= tolerance
    }
}
