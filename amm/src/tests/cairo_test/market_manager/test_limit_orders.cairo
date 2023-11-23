// Core lib imports.
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::libraries::math::math;
use amm::libraries::constants::OFFSET;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::core::{MarketState, OrderBatch, MarketConfigs, Config, ConfigOption};
use amm::types::i256::{i256, I256Trait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position
};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::params::{
    owner, alice, bob, charlie, treasury, default_token_params, default_market_params,
    modify_position_params, config
};
use amm::tests::common::utils::{to_e28, approx_eq, approx_eq_pct};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn _before(
    width: u32, allow_orders: bool
) -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
    // Deploy market manager.
    let market_manager = deploy_market_manager(owner());

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
    let mut market_configs: MarketConfigs = Default::default();
    if !allow_orders {
        market_configs.create_bid = config(ConfigOption::Disabled, true);
        market_configs.create_ask = config(ConfigOption::Disabled, true);
    }
    params.controller = owner();
    params.market_configs = Option::Some(market_configs);
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

fn before(
    width: u32
) -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
    _before(width, true)
}

fn before_no_orders() -> (
    IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252
) {
    _before(1, false)
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
    let position = market_manager.position(market_id, order.batch_id, limit, limit + 1);

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
    let base_amount_exp = 49750252076811799929168;
    let quote_amount_exp = 0;

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    let position = market_manager.position(market_id, order.batch_id, limit, limit + 1);

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
    quote_amount_exp = 99501001654900617893155;
    batch_quote_amount_exp += quote_amount_exp;

    // Fetch limit order, batch and position.
    order = market_manager.order(order_id);
    batch = market_manager.batch(order.batch_id);
    assert(order.liquidity == liquidity, 'Create bid 2: liquidity');
    assert(batch.liquidity == batch_liquidity, 'Create bid 2: batch liquidity');
    assert(batch.base_amount == 0, 'Create bid 2: batch base amt');
    assert(
        approx_eq(batch.quote_amount, batch_quote_amount_exp, 10), 'Create bid 2: batch quote amt'
    );
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
    let mut base_amount_exp = 49750252076811799929166;
    let mut batch_base_amount_exp = base_amount_exp;

    // Fetch limit order, batch and position.
    let mut order = market_manager.order(order_id);
    let mut batch = market_manager.batch(order.batch_id);
    assert(order.liquidity == liquidity, 'Create ask 1: liquidity');
    assert(batch.liquidity == liquidity, 'Create ask 1: batch liquidity');
    assert(approx_eq(batch.base_amount, base_amount_exp, 10), 'Create ask 1: batch base amt');
    assert(batch.quote_amount == 0, 'Create ask 1: batch quote amt');

    // Create second limit order.
    set_contract_address(bob());
    liquidity = to_e28(2);
    batch_liquidity += liquidity;
    order_id = market_manager.create_order(market_id, is_bid, limit, liquidity);
    base_amount_exp = 99500504153623599858333;
    batch_base_amount_exp += base_amount_exp;

    // Fetch limit order, batch and position.
    order = market_manager.order(order_id);
    batch = market_manager.batch(order.batch_id);
    assert(order.liquidity == liquidity, 'Create ask 2: liquidity');
    assert(batch.liquidity == batch_liquidity, 'Create ask 2: batch liquidity');
    assert(approx_eq(batch.base_amount, batch_base_amount_exp, 10), 'Create ask 2: batch base amt');
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

    // Create second limit order.
    set_contract_address(bob());
    let liquidity_2 = to_e28(500000);
    let order_id_2 = market_manager.create_order(market_id, is_bid, limit, liquidity_2);

    // Liquidity to base amount, add fees less protocol fees
    let base_amount_exp = 75601724787382248832073627271;

    // Create random range liquidity position which should be ignored when filling limit orders.
    market_manager
        .modify_position(market_id, OFFSET - 600, OFFSET - 500, I256Trait::new(to_e28(1), false));

    // Swap sell.
    let (amount_in, amount_out, fees) = market_manager
        .swap(
            market_id,
            !is_bid,
            to_e28(10),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

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
    assert(approx_eq_pct(batch.base_amount, base_amount_exp, 22), 'Create bid: batch base amt');
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

    // Create second limit order.
    set_contract_address(bob());
    let liquidity_2 = to_e28(500000);
    let order_id_2 = market_manager.create_order(market_id, is_bid, limit, liquidity_2);

    // Liquidity to quote amount, add fees less protocol fees
    let quote_amount_exp = 75602102795061168908553777023;

    // Create random range liquidity position which should be ignored when filling limit orders.
    market_manager
        .modify_position(market_id, OFFSET + 500, OFFSET + 600, I256Trait::new(to_e28(1), false));

    // Create third limit order (fallback liquidity so swap doesn't fail).
    let other_limit = OFFSET + 1100;
    market_manager.create_order(market_id, is_bid, other_limit, to_e28(1500000));

    // Swap buy.
    let (amount_in, amount_out, fees) = market_manager
        .swap(
            market_id,
            !is_bid,
            to_e28(10),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

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
    assert(approx_eq_pct(batch.quote_amount, quote_amount_exp, 22), 'Create ask: batch quote amt');
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
    let quote_amount_exp = 49750500827450308946577536307;

    // Collect limit order.
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let base_balance_after = base_token.balance_of(alice());
    let quote_balance_after = quote_token.balance_of(alice());

    // Fetch order and batch. Run checks.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    assert(approx_eq_pct(quote_amount, quote_amount_exp, 22), 'Collect bid: quote amount');
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
    let base_amount_exp = 49750252076811799929166716728;

    // Collect limit order.
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let base_balance_after = base_token.balance_of(alice());
    let quote_balance_after = quote_token.balance_of(alice());

    // Fetch order and batch. Run checks.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    assert(approx_eq_pct(base_amount, base_amount_exp, 22), 'Collect bid: base amount');
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
    let base_amount_exp = 50401149858254832554715751514;
    let quote_amount_exp = 49750500827450308946577536307;

    // Create second limit order.
    set_contract_address(bob());
    let liquidity_2 = to_e28(500000);
    market_manager.create_order(market_id, is_bid, limit, liquidity_2);
    let base_amount_exp_2 = 25200574929127416277357875757;
    let quote_amount_exp_2 = 24875250413725154473288768153;

    // Swap sell.
    let (amount_in, amount_out, fees) = market_manager
        .swap(
            market_id,
            !is_bid,
            to_e28(10),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

    // Collect limit order.
    set_contract_address(alice());
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let quote_balance_after = quote_token.balance_of(alice());
    let base_balance_after = base_token.balance_of(alice());

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    assert(approx_eq_pct(base_amount, base_amount_exp, 22), 'Collect bid: base amount');
    assert(quote_amount == 0, 'Collect bid: quote amount');
    assert(order.liquidity == 0, 'Collect bid: order liquidity');
    assert(batch.liquidity == liquidity_2, 'Collect bid: batch liquidity');
    assert(batch.filled == true, 'Collect bid: batch filled');
    assert(
        approx_eq_pct(batch.base_amount, base_amount_exp_2, 22), 'Collect bid: batch base amount'
    );
    assert(batch.quote_amount == 0, 'Collect bid: batch quote amount');
    assert(
        approx_eq_pct(base_balance_after, base_balance_before + base_amount_exp, 22),
        'Collect bid: base balance'
    );
    assert(
        approx_eq_pct(quote_balance_after, quote_balance_before - quote_amount_exp, 22),
        'Collect bid: quote balance'
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
    let base_amount_exp = 49750252076811799929166716728;
    let quote_amount_exp = 50401401863374112605702518015;

    // Create second limit order.
    set_contract_address(bob());
    let liquidity_2 = to_e28(500000);
    market_manager.create_order(market_id, is_bid, limit, liquidity_2);
    let base_amount_exp_2 = 24875126038405899964583358364;
    let quote_amount_exp_2 = 25200700931687056302851259007;

    let total_quote_amount_exp = 75602102795061168908553000000;

    // Create third limit order (fallback liquidity so swap doesn't fail).
    limit = OFFSET + 1100;
    market_manager.create_order(market_id, is_bid, limit, to_e28(1500000));

    // Swap buy.
    let (amount_in, amount_out, fees) = market_manager
        .swap(
            market_id,
            !is_bid,
            to_e28(10),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

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
    assert(approx_eq_pct(quote_amount, quote_amount_exp, 22), 'Collect ask: quote amount');
    assert(order.liquidity == 0, 'Collect ask: order liquidity');
    assert(batch.liquidity == liquidity_2, 'Collect ask: batch liquidity');
    assert(batch.filled == true, 'Collect ask: batch filled');
    assert(batch.base_amount == 0, 'Collect ask: batch base amount');
    assert(
        approx_eq_pct(batch.quote_amount, quote_amount_exp_2, 22), 'Collect ask: batch quote amount'
    );
    assert(
        approx_eq_pct(base_balance_after, base_balance_before - base_amount_exp, 22),
        'Collect ask: base balance'
    );
    assert(
        approx_eq_pct(quote_balance_after, quote_balance_before + quote_amount_exp, 22),
        'Collect ask: quote balance'
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
    let quote_amount_exp = 24875250413725154473288768153;
    let amount_filled_exp = 19741713750297465584247721318;
    let amount_unfilled_exp = 5133536663427688889041046835; // diff of above
    let amount_earned_exp = 19999880000000000000000000000;

    // Create second limit order.
    set_contract_address(alice());
    let liquidity_2 = to_e28(1000000);
    market_manager.create_order(market_id, is_bid, limit, liquidity_2);
    let quote_amount_exp_2 = 49750500827450308946577536307;
    let amount_filled_exp_2 = 39483427500594931168495442636;
    let amount_unfilled_exp_2 = 10267073326855377778082093671; // diff of above
    let amount_earned_exp_2 = 39999760000000000000000000000;

    // Swap sell (partially filled against limit orders).
    let (amount_in, amount_out, fees) = market_manager
        .swap(
            market_id,
            !is_bid,
            to_e28(6),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

    // Collect limit order.
    set_contract_address(bob());
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let base_balance_after = base_token.balance_of(bob());
    let quote_balance_after = quote_token.balance_of(bob());

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    assert(approx_eq_pct(base_amount, amount_earned_exp, 22), 'Collect bid: base amount');
    assert(approx_eq_pct(quote_amount, amount_unfilled_exp, 22), 'Collect bid: quote amount');
    assert(order.liquidity == 0, 'Collect bid: order liquidity');
    assert(batch.liquidity == liquidity_2, 'Collect bid: batch liquidity');
    assert(batch.filled == false, 'Collect bid: batch filled');
    assert(
        approx_eq_pct(batch.base_amount, amount_earned_exp_2, 22), 'Collect bid: batch base amount'
    );
    assert(
        approx_eq_pct(batch.quote_amount, amount_unfilled_exp_2, 22),
        'Collect bid: batch quote amount'
    );
    assert(
        approx_eq_pct(base_balance_after, base_balance_before + amount_earned_exp, 22),
        'Collect bid: base balance'
    );
    assert(
        approx_eq_pct(quote_balance_after, quote_balance_before - amount_filled_exp, 22),
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
    let base_amount_exp = 24875126038405899964583358364;
    let amount_filled_exp = 19741516335525794238392802523;
    let amount_unfilled_exp = 5133609702880105726190555841;
    let amount_earned_exp = 19999879999999999999999999999;

    // Create second limit order.
    set_contract_address(alice());
    let liquidity_2 = to_e28(1000000);
    market_manager.create_order(market_id, is_bid, limit, liquidity_2);
    let base_amount_exp_2 = 49750252076811799929166716728;
    let amount_filled_exp_2 = 39483032671051588476785605046;
    let amount_unfilled_exp_2 = 10267219405760211452381111682;
    let amount_earned_exp_2 = 39999759999999999999999999999;

    // Swap buy (partially filled against limit orders).
    let (amount_in, amount_out, fees) = market_manager
        .swap(
            market_id,
            !is_bid,
            to_e28(6),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

    // Collect limit order.
    set_contract_address(bob());
    let (base_amount, quote_amount) = market_manager.collect_order(market_id, order_id);

    // Snapshot user balance after.
    let quote_balance_after = quote_token.balance_of(bob());
    let base_balance_after = base_token.balance_of(bob());

    // Fetch limit order, batch and position.
    let order = market_manager.order(order_id);
    let batch = market_manager.batch(order.batch_id);
    assert(approx_eq_pct(base_amount, amount_unfilled_exp, 22), 'Collect ask: base amount');
    assert(approx_eq_pct(quote_amount, amount_earned_exp, 22), 'Collect ask: quote amount');
    assert(order.liquidity == 0, 'Collect ask: order liquidity');
    assert(batch.liquidity == liquidity_2, 'Collect ask: batch liquidity');
    assert(batch.filled == false, 'Collect ask: batch filled');
    assert(
        approx_eq_pct(batch.base_amount, amount_unfilled_exp_2, 22),
        'Collect ask: batch base amount'
    );
    assert(
        approx_eq_pct(batch.quote_amount, amount_earned_exp_2, 22),
        'Collect ask: batch quote amount'
    );
    assert(
        approx_eq_pct(base_balance_after, base_balance_before - amount_filled_exp, 22),
        'Collect ask: base balance'
    );
    assert(
        approx_eq_pct(quote_balance_after, quote_balance_before + amount_earned_exp, 22),
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
    let quote_amount_exp = 74625751241175463419866304461;

    // Swap sell (partial fill).
    let (amount_in_sell, amount_out_sell, fees_sell) = market_manager
        .swap(
            market_id,
            !is_bid,
            to_e28(6),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );
    let base_amount_sell_exp = 59999640000000000000000000000; // earned incl. fees
    let quote_amount_sell_exp = 59225141250892396752743163954; // filled

    // Swap buy (unfill).
    let (amount_in_buy, amount_out_buy, fees_buy) = market_manager
        .swap(
            market_id, is_bid, to_e28(4), true, Option::None(()), Option::None(()), Option::None(())
        );
    let base_amount_buy_exp = 40280607892236366896912492338; // repaid
    let quote_amount_buy_exp = 39999759999999999999999999999; // unfilled (incl. fees)

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
        approx_eq_pct(
            batch.quote_amount, quote_amount_exp - quote_amount_sell_exp + quote_amount_buy_exp, 6
        ),
        'Unfill bid: batch quote amount'
    );
    assert(
        approx_eq_pct(batch.base_amount, base_amount_sell_exp - base_amount_buy_exp, 22),
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
    let base_amount_exp = 74625378115217699893750075092;

    // Swap buy (partial fill).
    let (amount_in_sell, amount_out_sell, fees_sell) = market_manager
        .swap(
            market_id,
            !is_bid,
            to_e28(6),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );
    let base_amount_sell_exp = 59224549006577382715178407569; // filled
    let quote_amount_sell_exp = 59999640000000000000000000000; // earned incl. fees

    // Swap sell (unfill).
    let (amount_in_buy, amount_out_buy, fees_buy) = market_manager
        .swap(
            market_id, is_bid, to_e28(4), true, Option::None(()), Option::None(()), Option::None(())
        );
    let base_amount_buy_exp = 39999760000000000000000000000; // unfilled (incl. fees)
    let quote_amount_buy_exp = 40281010696178757375689329400; // repaid

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
        approx_eq_pct(
            batch.base_amount, base_amount_exp - base_amount_sell_exp + base_amount_buy_exp, 6
        ),
        'Unfill ask: batch base amount'
    );
    assert(
        approx_eq_pct(batch.quote_amount, quote_amount_sell_exp - quote_amount_buy_exp, 22),
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

    // Snapshot batch nonce before.
    let nonce_before = market_manager.limit_info(market_id, limit).nonce;

    // Swap sell.
    market_manager
        .swap(
            market_id,
            !is_bid,
            to_e28(6),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

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

    // Snapshot batch nonce before.
    let nonce_before = market_manager.limit_info(market_id, limit).nonce;

    // Swap sell.
    market_manager
        .swap(
            market_id,
            !is_bid,
            to_e28(6),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

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
fn test_limit_orders_misc_actions() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create orders:
    //  - Ask [1000]: 200000 (Bob)
    //  - Ask [900]: 150000 (Alice), 100000 (Bob)
    //  - Curr price [0]
    //  - Bid [-900]: 50000 (Alice), 100000 (Bob)
    //  - Bid [-1000]: 200000 (Alice)
    set_contract_address(alice());
    let bid_alice_n900 = market_manager.create_order(market_id, true, OFFSET - 900, to_e28(50000));
    let liq_bid_alice_n1000 = to_e28(200000);
    let bid_alice_n1000 = market_manager
        .create_order(market_id, true, OFFSET - 1000, liq_bid_alice_n1000);
    let liq_ask_alice_900 = to_e28(150000);
    let ask_a1 = market_manager.create_order(market_id, false, OFFSET + 900, liq_ask_alice_900);

    set_contract_address(bob());
    let liq_bid_bob_n900 = to_e28(100000);
    let bid_bob_n900 = market_manager.create_order(market_id, true, OFFSET - 900, liq_bid_bob_n900);
    let liq_ask_bob_900 = to_e28(100000);
    let ask_bob_900 = market_manager.create_order(market_id, false, OFFSET + 900, liq_ask_bob_900);
    let liq_ask_bob_1000 = to_e28(200000);
    let ask_bob_1000 = market_manager
        .create_order(market_id, false, OFFSET + 1000, liq_ask_bob_1000);

    // Snapshot balances.
    let market_base_start = market_manager.reserves(base_token.contract_address);
    let market_quote_start = market_manager.reserves(quote_token.contract_address);
    let alice_base_start = base_token.balance_of(alice());
    let alice_quote_start = quote_token.balance_of(alice());
    let bob_base_start = base_token.balance_of(bob());
    let bob_quote_start = quote_token.balance_of(bob());

    // Swap 1: Sell to fill both bid orders at -900 and partially fill one at -1000.
    set_contract_address(charlie());
    let (amount_in_1, amount_out_1, fees_1) = market_manager
        .swap(
            market_id, false, to_e28(1), true, Option::None(()), Option::None(()), Option::None(())
        );

    // Collect one of the filled orders.
    set_contract_address(alice());
    let (base_collect_1, quote_collect_1) = market_manager.collect_order(market_id, bid_alice_n900);

    // Fetch state.
    let mut market_state = market_manager.market_state(market_id);
    let order_bid_alice_n900 = market_manager.order(bid_alice_n900);
    let order_bid_alice_n1000 = market_manager.order(bid_alice_n1000);
    let order_bid_bob_n900 = market_manager.order(bid_bob_n900);
    let batch_neg_900 = market_manager.batch(order_bid_alice_n900.batch_id);
    let batch_neg_1000 = market_manager.batch(order_bid_alice_n1000.batch_id);
    let mut market_base_reserves = market_manager.reserves(base_token.contract_address);
    let mut market_quote_reserves = market_manager.reserves(quote_token.contract_address);
    let mut alice_base_balance = base_token.balance_of(alice());
    let mut alice_quote_balance = quote_token.balance_of(alice());
    let mut bob_base_balance = base_token.balance_of(bob());
    let mut bob_quote_balance = quote_token.balance_of(bob());

    // Check state.
    assert(approx_eq(amount_in_1, to_e28(1), 1), 'Amount in 1');
    assert(approx_eq_pct(amount_out_1, 9878318364512459259507136716, 22), 'Amount out 1');
    assert(approx_eq(fees_1, 30000000000000000000000000, 1), 'Fees 1');
    assert(approx_eq_pct(base_collect_1, 2518797785417929711264561597, 22), 'Base collect 1');
    assert(quote_collect_1 == 0, 'Quote collect 1');

    assert(market_state.liquidity == to_e28(200000), 'Mkt state 1: liquidity');
    assert(market_state.curr_limit == OFFSET - 1000, 'Mkt state 1: curr limit');
    assert(
        approx_eq_pct(market_state.curr_sqrt_price, 9950162731123922544094402919, 22),
        'Mkt state 1: curr sqrt price'
    );
    assert(
        approx_eq(market_state.base_fee_factor, 187406629087480932663, 1),
        'Mkt state 1: base fee factor'
    );
    assert(market_state.quote_fee_factor == 0, 'Mkt state 1: quote fee factor');

    assert(order_bid_alice_n900.liquidity == 0, 'Order a1: liquidity');
    assert(order_bid_bob_n900.liquidity == liq_bid_bob_n900, 'Order b1: liquidity');
    assert(order_bid_alice_n1000.liquidity == liq_bid_alice_n1000, 'Order a2: liquidity');
    assert(batch_neg_900.liquidity == liq_bid_bob_n900, 'Batch -900: liquidity');
    assert(batch_neg_900.filled, 'Batch -900: filled');
    assert(batch_neg_900.limit == OFFSET - 900, 'Batch -900: limit');
    assert(batch_neg_900.is_bid, 'Batch -900: is bid');
    assert(
        approx_eq_pct(batch_neg_900.base_amount, 5037595570835859422529123195, 22),
        'Batch -900: base amount'
    );
    assert(batch_neg_900.quote_amount == 0, 'Batch -900: quote amount');

    assert(batch_neg_1000.liquidity == liq_bid_alice_n1000, 'Batch -1000: liquidity');
    assert(!batch_neg_1000.filled, 'Batch -1000: filled');
    assert(batch_neg_1000.limit == OFFSET - 1000, 'Batch -1000: limit');
    assert(batch_neg_1000.is_bid, 'Batch -1000: is bid');
    assert(
        approx_eq_pct(batch_neg_1000.base_amount, 2443546643746210866206315207, 22),
        'Batch -1000: base amount'
    );
    assert(
        approx_eq_pct(batch_neg_1000.quote_amount, 7538089126968944009689895111, 22),
        'Batch -1000: quote amount'
    );
    assert(
        approx_eq_pct(market_base_reserves, 29875035954502256465732409400, 22),
        'Market base reserves'
    );
    assert(
        approx_eq_pct(market_quote_reserves, 7538089126968944009689895111, 22),
        'Market quote reserves'
    );
    assert(alice_base_balance == alice_base_start + base_collect_1, 'Alice base balance');
    assert(
        approx_eq_pct(to_e28(10000000) - alice_quote_balance, 12438869274153842282609348783, 22),
        'Alice quote balance'
    );
    assert(bob_base_balance == bob_base_start, 'Bob base balance');
    assert(
        approx_eq_pct(to_e28(10000000) - bob_quote_balance, 4977538217327560986587683043, 22),
        'Bob quote balance'
    );

    // Swap 2: Buy to unfill last bid order and partially fill 2 ask orders.
    let (amount_in_2, amount_out_2, fees_2) = market_manager
        .swap(
            market_id, true, to_e28(1), true, Option::None(()), Option::None(()), Option::None(())
        );

    // Collect a partially filled ask order at 900.
    let (base_collect_2, quote_collect_2) = market_manager.collect_order(market_id, ask_bob_900);

    // Collect unfilled order at 1000.
    let (base_collect_3, quote_collect_3) = market_manager.collect_order(market_id, ask_bob_1000);

    // Fetch state again.
    market_state = market_manager.market_state(market_id);
    let order_ask_a1 = market_manager.order(ask_a1);
    let order_ask_b1 = market_manager.order(ask_bob_900);
    let order_ask_b2 = market_manager.order(ask_bob_1000);
    let batch_900 = market_manager.batch(order_ask_b1.batch_id);
    let batch_1000 = market_manager.batch(order_ask_b2.batch_id);
    market_base_reserves = market_manager.reserves(base_token.contract_address);
    market_quote_reserves = market_manager.reserves(quote_token.contract_address);

    // Verify state.
    assert(approx_eq_pct(amount_in_2, to_e28(1), 22), 'Amount in 2');
    assert(approx_eq_pct(amount_out_2, 9926480658583945067498180903, 22), 'Amount out 2');
    assert(approx_eq_pct(fees_2, 29999999999999999999999999, 22), 'Fees 2');
    assert(approx_eq_pct(base_collect_2, 1981413314869032219787879134, 22), 'Base collect 2');
    assert(approx_eq_pct(quote_collect_2, 3032274268222713479270236952, 22), 'Quote collect 2');
    assert(approx_eq_pct(base_collect_3, 9950050415362359985833343345, 22), 'Base collect 3');
    assert(quote_collect_3 == 0, 'Quote collect 3');

    assert(market_state.liquidity == to_e28(150000), 'Mkt state 2: liquidity');
    assert(market_state.curr_limit == OFFSET + 900, 'Mkt state 2: curr limit');
    assert(
        approx_eq_pct(market_state.curr_sqrt_price, 10045131407988586929877373378, 22),
        'Mkt state 2: curr sqrt price'
    );
    assert(
        approx_eq(market_state.base_fee_factor, 187406629087480932663, 1),
        'Mkt state 2: base fee factor'
    );
    assert(
        approx_eq(market_state.quote_fee_factor, 127003290922098522198, 1),
        'Mkt state 2: quote fee factor'
    );

    assert(order_ask_a1.liquidity == liq_ask_alice_900, 'Order a1: liquidity');
    assert(order_ask_b1.liquidity == 0, 'Order b1: liquidity');
    assert(order_ask_b2.liquidity == 0, 'Order b2: liquidity');

    assert(batch_900.liquidity == liq_ask_alice_900, 'Batch 900: liquidity');
    assert(batch_900.filled == false, 'Batch 900: filled');
    assert(
        approx_eq_pct(batch_900.base_amount, 2972119972303548329681818701, 22),
        'Batch 900: base amount'
    );
    assert(
        approx_eq_pct(batch_900.quote_amount, 4548411402334070218905355428, 22),
        'Batch 900: quote amount'
    );

    assert(batch_1000.liquidity == 0, 'Batch 1000: liquidity');
    assert(batch_1000.filled == false, 'Batch 1000: filled');
    assert(batch_1000.base_amount == 0, 'Batch 1000: base amount');
    assert(batch_1000.quote_amount == 0, 'Batch 1000: quote amount');

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
#[should_panic(expected: ('CreateBidDisabled', 'ENTRYPOINT_FAILED',))]
fn test_create_bid_in_bid_disabled_market() {
    let (market_manager, base_token, quote_token, market_id) = before_no_orders();
    market_manager.create_order(market_id, true, 8388000, to_e28(1));
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('CreateAskDisabled', 'ENTRYPOINT_FAILED',))]
fn test_create_ask_in_ask_disabled_market() {
    let (market_manager, base_token, quote_token, market_id) = before_no_orders();
    market_manager.create_order(market_id, false, 8388000, to_e28(1));
}

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
