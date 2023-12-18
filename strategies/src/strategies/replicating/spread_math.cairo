// Core lib imports.
use cmp::{min, max};

// Local imports.
use amm::libraries::math::{price_math, math};
use amm::libraries::constants::ONE;
use amm::types::i32::{i32, I32Trait};
use amm::types::i256::I256Trait;
use strategies::strategies::replicating::{
    replicating_strategy::ReplicatingStrategy::ContractState,
};

////////////////////////////////
// CONSTANTS
///////////////////////////////

const DENOMINATOR: u256 = 10000;

const VOL_DENOMINATOR: u256 = 10000000000;

////////////////////////////////
// FUNCTIONS
///////////////////////////////

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
    let ask_spread = min_spread + width + if inv_delta.sign {
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
// `price` - current reference price (base 10 ** 28)
//
// # Returns
// `inv_delta` - inventory delta (+ve if ask spread, -ve if bid spread)
fn delta_spread(max_delta: u32, base_amount: u256, quote_amount: u256, price: u256) -> i32 {
    let base_in_quote = math::mul_div(base_amount, price, ONE, false);
    let is_bid_delta = base_in_quote < quote_amount;

    let diff = max(base_in_quote, quote_amount) - min(base_in_quote, quote_amount);
    let imbalance_pct = math::mul_div(diff, DENOMINATOR, base_in_quote + quote_amount, false);
    let spread: u32 = math::mul_div(max_delta.into(), imbalance_pct, DENOMINATOR, false)
        .try_into()
        .unwrap();

    // Constrain to width and return.
    I32Trait::new(spread, is_bid_delta)
}

use debug::PrintTrait;
// Note: Volatility-based limits are currently disabled as they are not fully supported by the oracle.
// // Unpack `Limits` enum into number of limits.
// // If range is Fixed, it is taken as is. 
// // If range is Variable, the number of limits is computed as:
// //    base * (vol / default_vol) * multiplier                   (if is_min_base = false)
// //    base * max(vol, default_vol) / default_vol * multiplier   (if is_min_base = true)
// //
// //
// // # Arguments
// // * `range` - Limits enum defining parameters for number of limits
// // * `vol` - volatility of market (expressed as a percentage base 10^10, e.g. 7076538586 = 70%)
// // * `is_min_base` - whether number of limits should be floored at `base` as minimum value 
// // * `width` - width of market
// fn unpack_limits(range: Limits, vol: u256, width: u32) -> u32 {
//     match range {
//         Limits::Fixed(v) => v / width * width,
//         Limits::Vol((
//             base, default_vol, multiplier, is_min_base
//         )) => {
//             // Run checks.
//             assert(default_vol != 0, 'DefaultVolZero');

//             // Handle 0 volatility edge case.
//             if vol == 0 {
//                 if is_min_base {
//                     return base / width * width;
//                 } else {
//                     return 0;
//                 }
//             }

//             // Calculate coefficient to multiply base by.
//             let numerator = if is_min_base {
//                 max(vol, default_vol.into())
//             } else {
//                 vol
//             };
//             let mut coefficient = I256Trait::new(
//                 math::mul_div(numerator, VOL_DENOMINATOR, default_vol.into(), false), false
//             );
//             coefficient -= I256Trait::new(VOL_DENOMINATOR, false);
//             coefficient.val = math::mul_div(coefficient.val, multiplier.into(), DENOMINATOR, false);
//             coefficient += I256Trait::new(VOL_DENOMINATOR, false);

//             // Calculate raw limit
//             let limits = math::mul_div(base.into(), coefficient.val, VOL_DENOMINATOR, false);

//             // Coerce limit to correct width.
//             (limits / width.into() * width.into()).try_into().unwrap()
//         }
//     }
// }


