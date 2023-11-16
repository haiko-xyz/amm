// Core lib imports.
use traits::TryInto;
use option::OptionTrait;
use integer::BoundedU256;
use integer::{u256_wide_mul, u512_safe_div_rem_by_u256, u256_try_as_non_zero};

// Local imports.
use amm::libraries::math::{math, fee_math, price_math, liquidity_math};
use amm::libraries::constants::{ONE, MAX};
use amm::types::core::{MarketState, LimitInfo};
use amm::types::i256::{i256, I256Trait, I256Zeroable};

// Add signed i256 delta to unsigned u256 amount.
//
// # Arguments
// * `amount` - starting amount.
// * `liquidity_delta` - Liquidity delta to apply
fn add_delta(ref amount: u256, delta: i256) {
    if delta.sign {
        amount -= delta.val;
    } else {
        assert(MAX - amount >= delta.val, 'AddDeltaOverflow');
        amount += delta.val;
    }
}

// Calculate the amount of quote tokens received for a given liquidity delta and price range.
// 
// # Arguments
// * `lower_sqrt_price` - starting sqrt price of the range
// * `upper_sqrt_price` - ending sqrt price of the range
// * `liquidity_delta` - liquidity delta to apply
// * `round_up` - whether to round up or down
// 
// # Returns
// * `quote_amount` - amount of quote tokens transferred out (-ve) or in (+ve) from / to pool
fn liquidity_to_quote(
    lower_sqrt_price: u256, upper_sqrt_price: u256, liquidity_delta: i256, round_up: bool,
) -> i256 {
    let abs_quote_amount = math::mul_div(
        liquidity_delta.val, upper_sqrt_price - lower_sqrt_price, ONE, round_up
    );
    i256 { val: abs_quote_amount, sign: liquidity_delta.sign }
}

// Calculate the amount of base tokens received for a given liquidity delta and price range.
//
// # Arguments
// * `lower_sqrt_price` - starting sqrt price of the range
// * `upper_sqrt_price` - ending sqrt price of the range
// * `liquidity_delta` - liquidity delta to apply
// * `round_up` - whether to round up or down
//
// # Returns
// * `base_amount` - amount of base tokens transferred out (-ve) or in (+ve) from / to pool
fn liquidity_to_base(
    lower_sqrt_price: u256, upper_sqrt_price: u256, liquidity_delta: i256, round_up: bool,
) -> i256 {
    if lower_sqrt_price == upper_sqrt_price {
        return i256 { val: 0, sign: false };
    }

    // Switch between formulas depending on magnitude of price, to maintain precision.
    let abs_base_amount = if lower_sqrt_price > ONE || upper_sqrt_price > ONE {
        math::mul_div(
            math::mul_div(
                liquidity_delta.val, upper_sqrt_price - lower_sqrt_price, lower_sqrt_price, round_up
            ),
            ONE,
            upper_sqrt_price,
            round_up
        )
    } else {
        let product = u256_wide_mul(lower_sqrt_price, upper_sqrt_price);
        let (q, r) = u512_safe_div_rem_by_u256(
            product,
            u256_try_as_non_zero(upper_sqrt_price - lower_sqrt_price).expect('MulDivByZero')
        );
        let q_u256 = u256 { low: q.limb0, high: q.limb1 };
        let denominator = q_u256 + if r != 0 && !round_up {
            1
        } else {
            0
        };
        math::mul_div(liquidity_delta.val, ONE, denominator, round_up)
    };

    i256 { val: abs_base_amount, sign: liquidity_delta.sign }
}

// Calculate liquidity delta corresponding to amount of quote tokens over given price range.
// 
// # Arguments
// * `lower_sqrt_price` - starting sqrt price of the range
// * `upper_sqrt_price` - ending sqrt price of the range
// * `quote_amount` - amount of quote tokens
// 
// # Returns
// * `liquidity_delta` - liquidity delta
fn quote_to_liquidity(lower_sqrt_price: u256, upper_sqrt_price: u256, quote_amount: u256) -> u256 {
    math::mul_div(quote_amount, ONE, upper_sqrt_price - lower_sqrt_price, false)
}

// Calculate liquidity delta corresponding to amount of base tokens over given price range.
// 
// # Arguments
// * `lower_sqrt_price` - starting sqrt price of the range
// * `upper_sqrt_price` - ending sqrt price of the range
// * `base_amount` - amount of base tokens
// 
// # Returns
// * `liquidity_delta` - liquidity delta
fn base_to_liquidity(lower_sqrt_price: u256, upper_sqrt_price: u256, base_amount: u256) -> u256 {
    if lower_sqrt_price == upper_sqrt_price {
        return 0;
    }
    math::mul_div(
        math::mul_div(base_amount, upper_sqrt_price, ONE, false),
        lower_sqrt_price,
        upper_sqrt_price - lower_sqrt_price,
        false
    )
}

// Calculate the amount of tokens received for a given liquidity delta and price range.
//
// # Arguments
// * `curr_limit` - current limit of market
// * `curr_sqrt_price` - current sqrt price of market
// * `liquidity_delta` - liquidity delta to apply
// * `lower_limit` - starting limit of the range
// * `upper_limit` - ending limit of the range
// * `width` - width of the price range
//
// # Returns
// * `base_amount` - amount of base tokens transferred out (-ve) or in (+ve)
// * `quote_amount` - amount of quote tokens transferred out (-ve) or in (+ve)
fn liquidity_to_amounts(
    liquidity_delta: i256,
    curr_sqrt_price: u256,
    lower_sqrt_price: u256,
    upper_sqrt_price: u256,
    width: u32,
) -> (i256, i256) {
    // Case 1: price range is below current price, all liquidity is quote token
    if upper_sqrt_price <= curr_sqrt_price {
        let quote_amount = liquidity_math::liquidity_to_quote(
            lower_sqrt_price, upper_sqrt_price, liquidity_delta, !liquidity_delta.sign,
        );
        (I256Zeroable::zero(), quote_amount)
    } // Case 2: price range contains current price
    else if lower_sqrt_price <= curr_sqrt_price {
        let base_amount = liquidity_math::liquidity_to_base(
            curr_sqrt_price, upper_sqrt_price, liquidity_delta, !liquidity_delta.sign
        );
        let quote_amount = liquidity_math::liquidity_to_quote(
            lower_sqrt_price, curr_sqrt_price, liquidity_delta, !liquidity_delta.sign
        );
        (base_amount, quote_amount)
    } // Case 3: price range is above current price, all liquidity is base token
    else {
        let base_amount = liquidity_math::liquidity_to_base(
            lower_sqrt_price, upper_sqrt_price, liquidity_delta, !liquidity_delta.sign
        );
        (base_amount, I256Zeroable::zero())
    }
}
