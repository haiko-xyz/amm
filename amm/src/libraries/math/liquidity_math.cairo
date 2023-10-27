// Core lib imports.
use traits::TryInto;
use option::OptionTrait;
use integer::BoundedU256;
use integer::{u256_wide_mul, u512_safe_div_rem_by_u256, u256_try_as_non_zero};

// Local imports.
use amm::libraries::math::{math, fee_math, price_math, liquidity_math};
use amm::libraries::constants::{ONE, MAX};
use amm::types::core::{MarketState, LimitInfo, Position};
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
fn liquidity_to_quote_amount(
    lower_sqrt_price: u256, upper_sqrt_price: u256, liquidity_delta: i256, round_up: bool,
) -> i256 {
    let abs_quote_amount = math::mul_div(
        liquidity_delta.val, upper_sqrt_price - lower_sqrt_price, ONE, round_up
    );
    i256 { val: abs_quote_amount, sign: liquidity_delta.sign }
}

// Calculate the amount of base tokens received for a given liquidity delta and price range.
// Does not implement checks for non-zero price.
//
// # Arguments
// * `lower_sqrt_price` - starting sqrt price of the range
// * `upper_sqrt_price` - ending sqrt price of the range
// * `liquidity_delta` - liquidity delta to apply
// * `round_up` - whether to round up or down
//
// # Returns
// * `base_amount` - amount of base tokens transferred out (-ve) or in (+ve) from / to pool
fn liquidity_to_base_amount(
    lower_sqrt_price: u256, upper_sqrt_price: u256, liquidity_delta: i256, round_up: bool,
) -> i256 {
    if lower_sqrt_price == upper_sqrt_price {
        return i256 { val: 0, sign: false };
    }

    let product = u256_wide_mul(lower_sqrt_price, upper_sqrt_price);
    let (q, r) = u512_safe_div_rem_by_u256(
        product, u256_try_as_non_zero(upper_sqrt_price - lower_sqrt_price).expect('MulDivByZero')
    );

    // Switch between formulas depending on whether denominator is zero.
    let q_u256 = u256 { low: q.limb0, high: q.limb1 };
    let abs_base_amount = if q_u256 == 0 || q.limb2 != 0 || q.limb3 != 0 {
        math::mul_div(
            math::mul_div(liquidity_delta.val, ONE, lower_sqrt_price, round_up),
            upper_sqrt_price - lower_sqrt_price,
            upper_sqrt_price,
            round_up
        )
    } else {
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
fn quote_amount_to_liquidity(
    lower_sqrt_price: u256, upper_sqrt_price: u256, quote_amount: u256
) -> u256 {
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
fn base_amount_to_liquidity(
    lower_sqrt_price: u256, upper_sqrt_price: u256, base_amount: u256
) -> u256 {
    if lower_sqrt_price == upper_sqrt_price {
        return 0;
    }
    // math::mul_div(
    //     math::mul_div(base_amount, lower_sqrt_price, ONE, false),
    //     upper_sqrt_price,
    //     upper_sqrt_price - lower_sqrt_price,
    //     false
    // )
    math::mul_div(
        base_amount,
        math::mul_div(
            lower_sqrt_price, upper_sqrt_price, upper_sqrt_price - lower_sqrt_price, false
        ),
        ONE,
        false,
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
    curr_limit: u32,
    curr_sqrt_price: u256,
    liquidity_delta: i256,
    lower_limit: u32,
    upper_limit: u32,
    width: u32,
) -> (i256, i256) {
    // Case 1: price range is below current price, all liquidity is quote token
    if upper_limit <= curr_limit {
        let quote_amount = liquidity_math::liquidity_to_quote_amount(
            price_math::limit_to_sqrt_price(lower_limit, width),
            price_math::limit_to_sqrt_price(upper_limit, width),
            liquidity_delta,
            !liquidity_delta.sign,
        );
        (I256Zeroable::zero(), quote_amount)
    } // Case 2: price range contains current price
    else if lower_limit <= curr_limit {
        let base_amount = liquidity_math::liquidity_to_base_amount(
            curr_sqrt_price,
            price_math::limit_to_sqrt_price(upper_limit, width),
            liquidity_delta,
            !liquidity_delta.sign
        );
        let quote_amount = liquidity_math::liquidity_to_quote_amount(
            price_math::limit_to_sqrt_price(lower_limit, width),
            curr_sqrt_price,
            liquidity_delta,
            !liquidity_delta.sign
        );
        (base_amount, quote_amount)
    } // Case 3: price range is above current price, all liquidity is base token
    else {
        let base_amount = liquidity_math::liquidity_to_base_amount(
            price_math::limit_to_sqrt_price(lower_limit, width),
            price_math::limit_to_sqrt_price(upper_limit, width),
            liquidity_delta,
            !liquidity_delta.sign
        );
        (base_amount, I256Zeroable::zero())
    }
}

// Get token amounts inside a position.
//
// # Arguments
// * `owner` - user address (or batch id for limit orders)
// * `market_id` - market id
// * `lower_limit` - lower limit of position
// * `upper_limit` - upper limit of position
//
// # Returns
// * `base_amount` - base tokens in position, excluding accrued fees
// * `quote_amount` - quote tokens in position, excluding accrued fees
// * `base_fees` - base tokens accrued in fees
// * `quote_fees` - quote tokens accrued in fees
fn amounts_inside_position(
    market_state: @MarketState,
    width: u32,
    position: @Position,
    lower_limit_info: LimitInfo,
    upper_limit_info: LimitInfo,
) -> (u256, u256, u256, u256) {
    // Get fee factors and calculate accrued fees.
    let (base_fee_factor, quote_fee_factor) = fee_math::get_fee_inside(
        lower_limit_info,
        upper_limit_info,
        *position.lower_limit,
        *position.upper_limit,
        *market_state.curr_limit,
        *market_state.base_fee_factor,
        *market_state.quote_fee_factor,
    );

    // Calculate fees accrued since last update.
    // Includes various asserts for debugging u256_overflow errors - can be removed later.
    assert(base_fee_factor >= *position.base_fee_factor_last, 'AmtsInsideBaseFeeFactor');
    let base_fees = math::mul_div(
        (base_fee_factor - *position.base_fee_factor_last), *position.liquidity.into(), ONE, false
    );
    assert(quote_fee_factor >= *position.quote_fee_factor_last, 'AmtsInsideQuoteFeeFactor');
    let quote_fees = math::mul_div(
        (quote_fee_factor - *position.quote_fee_factor_last), *position.liquidity.into(), ONE, false
    );

    // Calculate amounts inside position.
    let (base_amount, quote_amount) = liquidity_math::liquidity_to_amounts(
        *market_state.curr_limit,
        *market_state.curr_sqrt_price,
        I256Trait::new(*position.liquidity, false),
        *position.lower_limit,
        *position.upper_limit,
        width,
    );

    // Return amounts
    (base_amount.val, quote_amount.val, base_fees, quote_fees)
}
