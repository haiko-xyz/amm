// Core lib imports.
use cmp::{min, max};

// Local imports.
use amm::libraries::math::{price_math, math};
use amm::libraries::constants::ONE;
use amm::types::i32::{i32, I32Trait};
use strategies::strategies::replicating::types::Limits;
use strategies::strategies::replicating::{
    replicating_strategy::ReplicatingStrategy::ContractState,
};

// Calculate bid and ask limits based on the reference price, delta and minimum spread.
//
// # Arguments
// `curr_limit` - current market limit
// `new_limit` - new limit based on reference price
// `min_spread` - minimum spread
// `range` - range of positions
// `inv_delta` - inventory delta
// `width` - market width
// 
// # Returns
// `bid_lower` - bid lower limit
// `bid_upper` - bid upper limit
// `ask_lower` - ask lower limit
// `ask_upper` - ask upper limit
fn calc_bid_ask(
    curr_limit: u32, new_limit: u32, min_spread: u32, range: u32, inv_delta: i32, width: u32,
) -> (u32, u32, u32, u32) {
    // Calculate optimal bid and ask limits. These are the limits that would be placed 
    // before coercing them to respect market width.
    let bid_spread = min_spread + if inv_delta.sign {
        inv_delta.val
    } else {
        0
    };
    let ask_spread = min_spread + if inv_delta.sign {
        0
    } else {
        inv_delta.val
    };
    let raw_bid_limit = if bid_spread > new_limit || curr_limit < width {
        0
    } else {
        min(new_limit - bid_spread, curr_limit)
    };
    let raw_ask_limit = min(
        max(new_limit + ask_spread, curr_limit + width), price_math::max_limit(width)
    );

    // At this point, bid and ask limits may not respect market width. Coerce them to do so.
    let bid_upper = raw_bid_limit / width * width;
    let ask_limit_rem = if raw_ask_limit % width == 0 {
        0
    } else {
        1
    };
    let ask_lower = (raw_ask_limit / width + ask_limit_rem) * width;

    // Calculate remaining limits.
    let bid_lower = if bid_upper < range {
        0
    } else {
        bid_upper - range
    };
    let ask_upper = if ask_lower > price_math::max_limit(width) - range {
        price_math::max_limit(width)
    } else {
        ask_lower + range
    };

    // Return the bid and ask limits.
    (bid_lower, bid_upper, ask_lower, ask_upper)
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
// `inv_delta` - inventory delta (+ve if ask spread, -ve if bid spread)
fn delta_spread(
    max_delta: u32, base_amount: u256, quote_amount: u256, price: u256, width: u32
) -> i32 {
    let base_in_quote = math::mul_div(base_amount, price, ONE, false);
    let is_bid_delta = base_in_quote < quote_amount;

    let diff = max(base_in_quote, quote_amount) - min(base_in_quote, quote_amount);
    let imbalance_pct = math::mul_div(diff, 10000, base_in_quote + quote_amount, false);
    let spread: u32 = math::mul_div(max_delta.into(), imbalance_pct, 10000, false)
        .try_into()
        .unwrap();

    // Constrain to width and return.
    I32Trait::new(spread / width * width, is_bid_delta)
}
