// Core lib imports.
use traits::Into;
use option::OptionTrait;

// Local imports.
use amm::libraries::math::price_math;
use amm::types::i32::I32Trait;
use amm::libraries::constants::{MAX_SQRT_PRICE, MIN_SQRT_PRICE};

// Checks limits are different and properly ordered.
// 
// # Arguments
// * `lower_limit` - lower limit (shifted)
// * `upper_limit` - upper limit (shifted)
// * `width` - market width
// * `is_concentrated` - whether the pool allows concentrated liquidity positions
fn check_limits(lower_limit: u32, upper_limit: u32, width: u32, is_concentrated: bool) {
    let max_limit = price_math::max_limit(width);
    assert(lower_limit < upper_limit, 'LimitsUnordered');
    assert(upper_limit <= max_limit, 'UpperLimitOverflow');
    assert(lower_limit % width == 0 && upper_limit % width == 0, 'NotMultipleOfWidth');
    if !is_concentrated {
        assert(lower_limit == 0 && upper_limit == max_limit, 'LinearOnly');
    }
}

// Checks price threshold is valid with respect to current price.
//
// # Arguments
// * `threshold_sqrt_price` - threshold sqrt price
// * `curr_sqrt_price` - current sqrt price
// * `is_buy` - whether the price threshold is a buy or sell price
fn check_threshold(threshold_sqrt_price: u256, curr_sqrt_price: u256, is_buy: bool) {
    assert(
        if is_buy {
            threshold_sqrt_price > curr_sqrt_price && threshold_sqrt_price <= MAX_SQRT_PRICE
        } else {
            threshold_sqrt_price < curr_sqrt_price && threshold_sqrt_price >= MIN_SQRT_PRICE
        },
        'ThresholdInvalid'
    );
}
