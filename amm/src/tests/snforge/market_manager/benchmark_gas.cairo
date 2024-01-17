// Local imports.
use amm::libraries::constants::OFFSET;
use amm::libraries::id;
use amm::libraries::math::{fee_math, price_math};
use amm::types::i128::I128Trait;
use amm::contracts::market_manager::MarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market},
    token::{declare_token, deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, treasury, token_params, default_market_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, to_e18_u128, to_e28_u128, encode_sqrt_price};

// External imports.
use snforge_std::{
    start_prank, declare, PrintTrait, spy_events, SpyOn, EventSpy, EventAssertions, CheatTarget
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn setup_deploy_and_approve() -> (
    IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher
) {
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

    (market_manager, base_token, quote_token)
}

fn setup_create_market(
    market_manager: IMarketManagerDispatcher,
    base_token: ERC20ABIDispatcher,
    quote_token: ERC20ABIDispatcher
) -> felt252 {
    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = OFFSET;
    params.width = 1;

    create_market(market_manager, params)
}

////////////////////////////////
// TESTS
////////////////////////////////

// Benchmark cases
// Note: each benchmark case should deduct the gas cost of the before_* function from the total gas cost.
// 1. Create market
// 2. Add liquidity at previously uninitialised limit
// 3. Add liquidity at previously initialised limit
// 4. Add liquidity at prev. initialised lower + uninitialised upper limit
// 5. Remove partial liquidity from position (no fees)
// 6. Remove all liquidity from position (no fees)
// 7. Remove all liquidity from position (with fees)
// 8. Collect fees from position
// 9. Swap with zero liquidity
// 10. Swap with normal liquidity, within 1 limit
// 11. Swap with normal liquidity, 1 limit crossed
// 12. Swap with normal liquidity, 4 limits crossed 
// 13. Swap with normal liquidity, 9 limits crossed
// 14. Swap with limit order, partial fill
// 15. Swap with limit order, full fill
// 16. Swap with strategy enabled, no position updates
// 17. Swap with strategy enabled, one position update
// 18. Swap with strategy enabled, both position updates
// 19. Create limit order
// 20. Collect unfilled limit order
// 21. Collect partially filled limit order
// 22. Collect fully filled limit order

// Benchmark 1: Create market

#[test]
fn before_benchmark_create_market() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    assert(true, 'Test complete');
}

#[test]
fn benchmark_create_market() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = OFFSET;
    params.width = 1;

    create_market(market_manager, params);
}

// Benchmark 2: Add liquidity at previously uninitialised limit

#[test]
fn before_benchmark_add_liquidity_at_prev_uninitialised_limit() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    setup_create_market(market_manager, base_token, quote_token);
}

#[test]
fn benchmark_add_liquidity_at_prev_uninitialised_limit() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity_delta = I128Trait::new(to_e18_u128(10000), false);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity_delta);
}

// Benchmark 3: Add liquidity at previously initialised limit

#[test]
fn before_benchmark_add_liquidity_at_prev_initialised_limit() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );
}

#[test]
fn benchmark_add_liquidity_at_prev_initialised_limit() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );

    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity_delta = I128Trait::new(to_e18_u128(10000), false);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity_delta);
}

// Benchmark 4: Add liquidity at prev. initialised lower + uninitialised upper limit

#[test]
fn before_benchmark_add_liquidity_at_prev_initialised_lower_uninitialised_upper_limit() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );
}

#[test]
fn benchmark_add_liquidity_at_prev_initialised_lower_uninitialised_upper_limit() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );

    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 900;
    let liquidity_delta = I128Trait::new(to_e18_u128(10000), false);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity_delta);
}

// Benchmark 5: Remove partial liquidity from position (no fees)

#[test]
fn before_benchmark_remove_partial_liquidity_no_fees() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );
}

#[test]
fn benchmark_remove_partial_liquidity_no_fees() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );

    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity_delta = I128Trait::new(to_e18_u128(5000), true);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity_delta);
}

// Benchmark 6: Remove all liquidity from position (no fees)

#[test]
fn before_benchmark_remove_all_liquidity_no_fees() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );
}

#[test]
fn benchmark_remove_all_liquidity_no_fees() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );

    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity_delta = I128Trait::new(to_e18_u128(10000), true);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity_delta);
}

// Benchmark 7: Remove all liquidity from position (with fees)

#[test]
fn before_benchmark_remove_all_liquidity_with_fees() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );
    market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );
}

#[test]
fn benchmark_remove_all_liquidity_with_fees() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );
    market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity_delta = I128Trait::new(to_e18_u128(10000), true);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity_delta);
}

// Benchmark 8: Collect fees from position

#[test]
fn before_benchmark_collect_fees_from_position() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager.clone(), base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );
    market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );
}

#[test]
fn benchmark_collect_fees_from_position() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager.clone(), base_token, quote_token);
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(10000), false)
        );
    market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(0, false));
}

// Benchmark 9: Swap with zero liquidity

#[test]
fn before_benchmark_swap_with_zero_liquidity() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    setup_create_market(market_manager, base_token, quote_token);
}

#[test]
fn benchmark_swap_with_zero_liquidity() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );
}

// Benchmark 10: Swap with normal liquidity, within 1 limit

#[test]
fn before_benchmark_swap_with_normal_liquidity_within_1_limit() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager, base_token, quote_token);

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(1000), false)
        );
}

#[test]
fn benchmark_swap_with_normal_liquidity_within_1_limit() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager.clone(), base_token, quote_token);

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(1000), false)
        );
    let (amount_in, _, _) = market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );
    assert(amount_in == to_e18(1), 'Fully filled');
}

// Benchmark 11: Swap with normal liquidity, 1 limit crossed

#[test]
fn before_benchmark_swap_with_normal_liquidity_1_limit_crossed() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager.clone(), base_token, quote_token);

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 100, OFFSET + 300, I128Trait::new(to_e18_u128(1000), false)
        );
}

#[test]
fn benchmark_swap_with_normal_liquidity_1_limit_crossed() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager.clone(), base_token, quote_token);

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 1000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 100, OFFSET + 300, I128Trait::new(to_e18_u128(1000), false)
        );

    let (amount_in, _, _) = market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );

    let position_id = id::position_id(market_id, alice().into(), OFFSET + 100, OFFSET + 300);
    let (base_amount, quote_amount, _, _) = market_manager.amounts_inside_position(position_id);
    base_amount.print();
    quote_amount.print();
    assert(base_amount != 0 && quote_amount != 0, '1 limit crossed');
}

// Benchmark 12: Swap with normal liquidity, 4 limits crossed

#[test]
fn before_benchmark_swap_with_normal_liquidity_4_limits_crossed() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager.clone(), base_token, quote_token);

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 10000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 1000, OFFSET + 3000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 5000, OFFSET + 7000, I128Trait::new(to_e18_u128(1000), false)
        );
}

#[test]
fn benchmark_swap_with_normal_liquidity_4_limits_crossed() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager.clone(), base_token, quote_token);

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 10000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 1000, OFFSET + 3000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 5000, OFFSET + 7000, I128Trait::new(to_e18_u128(1000), false)
        );

    let (amount_in, _, _) = market_manager
        .swap(
            market_id, true, to_e18(10), true, Option::None(()), Option::None(()), Option::None(())
        );

    let position_id = id::position_id(market_id, alice().into(), OFFSET + 500, OFFSET + 700);
    let (base_amount, quote_amount, _, _) = market_manager.amounts_inside_position(position_id);
    assert(base_amount == 0, '4 limits crossed');
}

// Benchmark 13: Swap with normal liquidity, 9 limits crossed

#[test]
fn before_benchmark_swap_with_normal_liquidity_9_limits_crossed() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager.clone(), base_token, quote_token);

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 10000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 2000, OFFSET + 3000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 4000, OFFSET + 5000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 6000, OFFSET + 7000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 8000, OFFSET + 9000, I128Trait::new(to_e18_u128(1000), false)
        );

    let position_id = id::position_id(market_id, alice().into(), OFFSET + 8000, OFFSET + 9000);
    market_manager.amounts_inside_position(position_id);
}

#[test]
fn benchmark_swap_with_normal_liquidity_9_limits_crossed() {
    let (market_manager, base_token, quote_token) = setup_deploy_and_approve();
    let market_id = setup_create_market(market_manager.clone(), base_token, quote_token);

    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, OFFSET - 1000, OFFSET + 10000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 2000, OFFSET + 3000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 4000, OFFSET + 5000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 6000, OFFSET + 7000, I128Trait::new(to_e18_u128(1000), false)
        );
    market_manager
        .modify_position(
            market_id, OFFSET + 8000, OFFSET + 9000, I128Trait::new(to_e18_u128(1000), false)
        );

    market_manager
        .swap(
            market_id, true, to_e18(100), true, Option::None(()), Option::None(()), Option::None(())
        );

    let position_id = id::position_id(market_id, alice().into(), OFFSET + 8000, OFFSET + 9000);
    let (base_amount, _, _, _) = market_manager.amounts_inside_position(position_id);
    assert(base_amount == 0, '10 limits crossed');
}
