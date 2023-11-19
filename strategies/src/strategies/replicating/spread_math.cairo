// Core lib imports.
use cmp::{min, max};

// Local imports.
use amm::libraries::math::{price_math, math};
use amm::libraries::constants::ONE;


// Calculate bid and ask limits based on the reference price, delta and minimum spread.
//
// # Arguments
// `curr_limit` - current market limit
// `new_limit` - new limit based on reference price
// `bid_delta` - bid delta
// `ask_delta` - ask delta
// `min_spread` - minimum spread
// `width` - market width
// 
// # Returns
// `bid_limit` - bid limit
// `ask_limit` - ask limit
fn calc_bid_ask(
    curr_limit: u32, new_limit: u32, bid_delta: u32, ask_delta: u32, min_spread: u32, width: u32,
) -> (u32, u32) {
    // Calculate optimal bid and ask limits. These are the limits that would be placed 
    // before coercing them to respect market width.
    let bid_spread = min_spread + bid_delta;
    let ask_spread = min_spread + ask_delta;
    let raw_bid_limit = if bid_spread > new_limit || curr_limit < width {
        0
    } else {
        min(new_limit - bid_spread, curr_limit)
    };
    let raw_ask_limit = min(
        max(new_limit + width + ask_spread, curr_limit + width), price_math::max_limit(width)
    );

    // At this point, bid and ask limits may not respect market width. Coerce them to do so.
    let bid_limit = raw_bid_limit / width * width;
    let ask_limit_rem = if raw_ask_limit % width == 0 {
        0
    } else {
        1
    };
    let ask_limit = (raw_ask_limit / width + ask_limit_rem) * width;

    // Return the bid and ask limits.
    (bid_limit, ask_limit)
}

// Calculate the single-sided spread to add to either the bid or ask positions based on delta,
// i.e. the portfolio imbalance factor.
// 
// # Arguments
// `max_delta` - maximum allowed delta
// `base_amount` - amount of base assets owned by strategy
// `quote_amount` - amount of quote assets owned by strategy
// `price` - current reference price
//
// # Returns
// `bid_spread` - spread to add to bid position
// `ask_spread` - spread to add to ask position
fn delta_spread(max_delta: u32, base_amount: u256, quote_amount: u256, price: u256,) -> (u32, u32) {
    let base_in_quote = math::mul_div(base_amount, price, ONE, false);
    let is_bid_delta = base_in_quote < quote_amount;

    let diff = max(base_in_quote, quote_amount) - min(base_in_quote, quote_amount);
    let imbalance_pct = math::mul_div(diff, 10000, base_in_quote + quote_amount, false);
    let spread: u32 = math::mul_div(max_delta.into(), imbalance_pct, 10000, false)
        .try_into()
        .unwrap();

    let bid_spread = if is_bid_delta {
        spread
    } else {
        0
    };
    let ask_spread = if !is_bid_delta {
        spread
    } else {
        0
    };

    (bid_spread, ask_spread)
}
