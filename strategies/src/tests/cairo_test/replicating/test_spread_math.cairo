use amm::types::i32::I32Trait;
use amm::tests::common::utils::{to_e28, to_e18};
use strategies::strategies::replicating::spread_math::{calc_bid_ask, delta_spread, unpack_limits};
use strategies::strategies::replicating::types::Limits;

use debug::PrintTrait;

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(100000000)]
fn test_calc_bid_ask() {
    // New limit is equal to current limit
    let mut curr_limit = 500;
    let mut new_limit = 500;
    let mut min_spread = 1;
    let mut range = 50;
    let mut inv_delta = I32Trait::new(0, false);
    let mut width = 1;
    let (mut bid_lower, mut bid_upper, mut ask_lower, mut ask_upper) = calc_bid_ask(
        curr_limit, new_limit, min_spread, range, inv_delta, width
    );
    assert(bid_lower == 449, 'Bid lower 1');
    assert(bid_upper == 499, 'Bid upper 1');
    assert(ask_lower == 502, 'Ask lower 1');
    assert(ask_upper == 552, 'Ask upper 1');

    // Bid crosses the spread
    new_limit = 510;
    let (bid_lower, bid_upper, ask_lower, ask_upper) = calc_bid_ask(
        curr_limit, new_limit, min_spread, range, inv_delta, width
    );
    assert(bid_lower == 450, 'Bid lower 2');
    assert(bid_upper == 500, 'Bid upper 2');
    assert(ask_lower == 512, 'Ask lower 2');
    assert(ask_upper == 562, 'Ask upper 2');

    // Ask crosses the spread
    new_limit = 490;
    let (bid_lower, bid_upper, ask_lower, ask_upper) = calc_bid_ask(
        curr_limit, new_limit, min_spread, range, inv_delta, width
    );
    assert(bid_lower == 439, 'Bid lower 3');
    assert(bid_upper == 489, 'Bid upper 3');
    assert(ask_lower == 501, 'Ask lower 3');
    assert(ask_upper == 551, 'Ask upper 3');

    // Zero min spread
    new_limit = 500;
    min_spread = 0;
    let (bid_lower, bid_upper, ask_lower, ask_upper) = calc_bid_ask(
        curr_limit, new_limit, min_spread, range, inv_delta, width
    );
    assert(bid_lower == 450, 'Bid lower 4');
    assert(bid_upper == 500, 'Bid upper 4');
    assert(ask_lower == 501, 'Ask lower 4');
    assert(ask_upper == 551, 'Ask upper 4');

    // Bid inventory delta
    inv_delta = I32Trait::new(10, true);
    let (bid_lower, bid_upper, ask_lower, ask_upper) = calc_bid_ask(
        curr_limit, new_limit, min_spread, range, inv_delta, width
    );
    assert(bid_lower == 440, 'Bid lower 5');
    assert(bid_upper == 490, 'Bid upper 5');
    assert(ask_lower == 501, 'Ask lower 5');
    assert(ask_upper == 551, 'Ask upper 5');

    // Ask inventory delta
    inv_delta = I32Trait::new(10, false);
    let (bid_lower, bid_upper, ask_lower, ask_upper) = calc_bid_ask(
        curr_limit, new_limit, min_spread, range, inv_delta, width
    );
    assert(bid_lower == 450, 'Bid lower 6');
    assert(bid_upper == 500, 'Bid upper 6');
    assert(ask_lower == 511, 'Ask lower 6');
    assert(ask_upper == 561, 'Ask upper 6');

    // Different range
    inv_delta = I32Trait::new(0, true);
    range = 2;
    let (bid_lower, bid_upper, ask_lower, ask_upper) = calc_bid_ask(
        curr_limit, new_limit, min_spread, range, inv_delta, width
    );
    assert(bid_lower == 498, 'Bid lower 7');
    assert(bid_upper == 500, 'Bid upper 7');
    assert(ask_lower == 501, 'Ask lower 7');
    assert(ask_upper == 503, 'Ask upper 7');

    // Width 10
    width = 10;
    range = 100;
    min_spread = 10;
    let (bid_lower, bid_upper, ask_lower, ask_upper) = calc_bid_ask(
        curr_limit, new_limit, min_spread, range, inv_delta, width
    );
    assert(bid_lower == 390, 'Bid lower 8');
    assert(bid_upper == 490, 'Bid upper 8');
    assert(ask_lower == 520, 'Ask lower 8');
    assert(ask_upper == 620, 'Ask upper 8');

    // Min spread not multiple of delta
    width = 10;
    min_spread = 14;
    let (bid_lower, bid_upper, ask_lower, ask_upper) = calc_bid_ask(
        curr_limit, new_limit, min_spread, range, inv_delta, width
    );
    assert(bid_lower == 380, 'Bid lower 9');
    assert(bid_upper == 480, 'Bid upper 9');
    assert(ask_lower == 530, 'Ask lower 9');
    assert(ask_upper == 630, 'Ask upper 9');

    // Delta not multiple of width
    inv_delta = I32Trait::new(12, true);
    let (bid_lower, bid_upper, ask_lower, ask_upper) = calc_bid_ask(
        curr_limit, new_limit, min_spread, range, inv_delta, width
    );
    assert(bid_lower == 370, 'Bid lower 10');
    assert(bid_upper == 470, 'Bid upper 10');
    assert(ask_lower == 530, 'Ask lower 10');
    assert(ask_upper == 630, 'Ask upper 10');
}

#[test]
#[available_gas(100000000)]
fn test_delta_spread() {
    // Equal amounts
    let mut max_delta = 2000;
    let mut base_amount = to_e18(1);
    let mut quote_amount = to_e18(2000);
    let mut price = to_e28(2000);
    let mut inv_delta = delta_spread(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(0, false), 'Inv delta 1');

    // Skewed to base
    base_amount = to_e18(2);
    inv_delta = delta_spread(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(666, false), 'Inv delta 2');

    // Skewed to quote
    base_amount = to_e18(1);
    quote_amount = to_e18(3600);
    inv_delta = delta_spread(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(571, true), 'Inv delta 3');

    // All base
    quote_amount = 0;
    inv_delta = delta_spread(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(2000, false), 'Inv delta 4');

    // All quote
    quote_amount = to_e18(2000);
    base_amount = 0;
    inv_delta = delta_spread(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(2000, true), 'Inv delta 5');

    // Small token values
    base_amount = 1;
    quote_amount = 3;
    price = to_e28(2);
    inv_delta = delta_spread(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(400, true), 'Inv delta 6');

    // Large token values
    base_amount = to_e28(1000);
    quote_amount = to_e28(20000);
    inv_delta = delta_spread(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(1636, true), 'Inv delta 7');

    // Near max delta
    base_amount = to_e18(50);
    quote_amount = 0;
    max_delta = 7906600;
    inv_delta = delta_spread(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(7906600, false), 'Inv delta 8');

    // Zero delta
    max_delta = 0;
    inv_delta = delta_spread(max_delta, base_amount, quote_amount, price);
    assert(inv_delta == I32Trait::new(0, false), 'Inv delta 9');
}

#[test]
#[available_gas(100000000)]
fn test_unpack_limits_cases() {
    // Fixed limits
    let mut range = Limits::Fixed(100);
    let mut vol = 0;
    let mut width = 10;
    let limits = unpack_limits(range, vol, width);
    assert(limits == 100, 'Unpack limits 1');

    // Variable limits
    // Base not floored
    vol = 7000000000;
    range = Limits::Vol((100, 5000000000, 8000, false));
    let limits = unpack_limits(range, vol, width);
    assert(limits == 130, 'Unpack limits 2');

    vol = 5000000000;
    let limits = unpack_limits(range, vol, width);
    assert(limits == 100, 'Unpack limits 3');

    vol = 3000000000;
    let limits = unpack_limits(range, vol, width);
    assert(limits == 60, 'Unpack limits 4');

    // Zero vol
    vol = 0;
    let limits = unpack_limits(range, vol, width);
    assert(limits == 0, 'Unpack limits 5');

    // Capped at minimum
    vol = 3000000000;
    range = Limits::Vol((100, 5000000000, 8000, true));
    let limits = unpack_limits(range, vol, width);
    assert(limits == 100, 'Unpack limits 6');

    // Capped at minimum with 0 vol
    vol = 0;
    let limits = unpack_limits(range, vol, width);
    assert(limits == 100, 'Unpack limits 7');
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('DefaultVolZero',))]
fn test_unpack_limits_zero_vol() {
    let range = Limits::Vol((100, 0, 8000, false));
    let vol = 0;
    let width = 10;
    let limits = unpack_limits(range, vol, width);
}
