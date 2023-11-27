use cmp::{min, max};

use amm::libraries::math::price_math::{limit_to_sqrt_price, max_limit};
use amm::libraries::math::liquidity_math::{
    liquidity_to_base, liquidity_to_quote, base_to_liquidity, quote_to_liquidity
};
use amm::types::i128::I128Trait;
use snforge_std::PrintTrait;

////////////////////////////////
// TESTS
////////////////////////////////

// Check for following invariants:
// 1. Liquidity to base (rounding up) is never lower than liquidity to base (rounding down)
// 2. Converting liquidity to base (rounding down), then back to liquidity, results in lower amount.
#[test]
fn test_liquidity_to_base_invariants(liquidity: u128, width: u16, rand1: u32, rand2: u32) {
    if width == 0 {
        return;
    }

    let lower_limit = min(rand1, rand2) / 256;
    let upper_limit = max(rand1, rand2) / 256;

    if lower_limit > max_limit(width.into()) || upper_limit > max_limit(width.into()) {
        return;
    }

    let lower_sqrt_price = limit_to_sqrt_price(lower_limit, width.into());
    let upper_sqrt_price = limit_to_sqrt_price(upper_limit, width.into());
    let liquidity_i128 = I128Trait::new(liquidity.into(), false);

    let base_round_down = liquidity_to_base(
        lower_sqrt_price, upper_sqrt_price, liquidity_i128, false
    );
    let base_round_up = liquidity_to_base(lower_sqrt_price, upper_sqrt_price, liquidity_i128, true);
    assert(base_round_down <= base_round_up, 'Base rnd down <= base rnd up');

    if liquidity == 0 {
        return;
    }
    let liquidity_deriv = base_to_liquidity(
        lower_sqrt_price, upper_sqrt_price, base_round_down.val, false
    );
    assert(liquidity_deriv <= liquidity.into(), 'Liquidity deriv <= liquidity');
}

// Check for following invariants:
// 1. Liquidity to quote (rounding up) is never lower than liquidity to quote (rounding down)
// 2. Converting liquidity to quote (rounding down), then back to liquidity, results in lower amount.
#[test]
fn test_liquidity_to_quote_invariants(liquidity: u128, width: u16, rand1: u32, rand2: u32) {
    if width == 0 {
        return;
    }

    let lower_limit = min(rand1, rand2) / 256;
    let upper_limit = max(rand1, rand2) / 256;

    if lower_limit > max_limit(width.into()) || upper_limit > max_limit(width.into()) {
        return;
    }

    let lower_sqrt_price = limit_to_sqrt_price(lower_limit, width.into());
    let upper_sqrt_price = limit_to_sqrt_price(upper_limit, width.into());
    let liquidity_i128 = I128Trait::new(liquidity.into(), false);

    let quote_round_down = liquidity_to_quote(
        lower_sqrt_price, upper_sqrt_price, liquidity_i128, false
    );
    let quote_round_up = liquidity_to_quote(
        lower_sqrt_price, upper_sqrt_price, liquidity_i128, true
    );
    assert(quote_round_down <= quote_round_up, 'Quote rnd down <= base rnd up');

    if liquidity == 0 {
        return;
    }
    let liquidity_deriv = quote_to_liquidity(
        lower_sqrt_price, upper_sqrt_price, quote_round_down.val, false
    );
    assert(liquidity_deriv <= liquidity.into(), 'Liquidity deriv <= liquidity');
}
