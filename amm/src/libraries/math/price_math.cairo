// Core lib imports.
use traits::{Into, TryInto};
use option::OptionTrait;
use integer::U32IntoFelt252;
use integer::BoundedU256;

// Local imports.
use amm::libraries::math::math;
use amm::libraries::math::price_math;
use amm::libraries::math::bit_math;
use amm::types::i32::{i32, I32Trait, I32Zeroable};
use amm::types::i128::{i128, I128Trait};
use amm::libraries::constants::{
    ONE, ONE_SQUARED, HALF, MAX_LIMIT, MIN_LIMIT, OFFSET, MAX_LIMIT_SHIFTED, Q128, MIN_SQRT_PRICE,
    MAX_SQRT_PRICE, LOG2_1_00001, MAX_WIDTH
};

////////////////////////////////
// FUNCTIONS
////////////////////////////////

// Convert limit from i32 (range -7,906,625 to 7,906,625) to u32 (range 0 to 15,813,251).
//
// # Arguments
// * `limit` - unshifted limit
// * `width` - limit width
//
// # Returns
// * `shifted_limit` - shifted limit
fn shift_limit(limit: i32, width: u32) -> u32 {
    assert(limit >= I32Trait::new(MIN_LIMIT, true), 'ShiftLimitUnderflow');
    assert(limit <= I32Trait::new(MAX_LIMIT, false), 'ShiftLimitOF');
    let shifted: i32 = limit + I32Trait::new(offset(width), false);
    shifted.val
}

// Convert limit from u32 (range 0 to 15,813,251) to i32 (range -7,906,625 to 7,906,625).
//
// # Arguments
// * `limit` - shifted limit
// * `width` - limit width
//
// # Returns
// * `unshifted_limit` - unshifted limit
fn unshift_limit(limit: u32, width: u32) -> i32 {
    let unshifted: i32 = I32Trait::new(limit, false) - I32Trait::new(offset(width), false);
    assert(unshifted.val <= MAX_LIMIT / width * width, 'UnshiftLimitOF');
    unshifted
}

// Calculate offset used to shift limit.
//
// # Arguments
// * `width` - limit width
//
// # Returns
// * `offset` - offset to shift limit by
fn offset(width: u32) -> u32 {
    OFFSET / width * width
}

// Returns the maximum shifted limit given a price width.
// Note a corresponding `min_limit` function does not exist because it is always 0.
//
// # Arguments
// * `width` - limit width of market
//
// # Returns
// * `max_limit` - offset to shift limit by
fn max_limit(width: u32) -> u32 {
    offset(width) + MAX_LIMIT / width * width
}

// Convert limit to sqrt price.
//   Formula: price = 1.00001 ^ (limit / 2)
//
// # Arguments
// * `limit` - shifted limit
// * `width` - limit width
//
// # Returns
// * `sqrt_price` - sqrt price encoded as UD47x28
fn limit_to_sqrt_price(limit: u32, width: u32) -> u256 {
    // Check limit ID is in range
    assert(width <= MAX_WIDTH, 'WidthOF');
    assert(limit <= max_limit(width), 'LimitOF');

    // Unshift limit
    let unshifted = unshift_limit(limit, width);

    // Calculate sqrt price
    _exp1_00001(unshifted)
}

// Convert sqrt price to limit.
// Returns the highest limit such that the corresponding sqrt price is less than or equal to the 
// input sqrt price.
// 
// # Arguments
// * `sqrt_price` - sqrt price encoded as UD47x28
// * `width` - limit width
//
// # Returns
// * `limit` - shifted limit
fn sqrt_price_to_limit(sqrt_price: u256, width: u32) -> u32 {
    assert(sqrt_price >= MIN_SQRT_PRICE && sqrt_price <= MAX_SQRT_PRICE, 'SqrtPriceOF');

    // Handle special case
    if sqrt_price == MAX_SQRT_PRICE {
        return MAX_LIMIT_SHIFTED;
    }

    // If sqrt price is less than 1, calculate reciprocal and flip sign.
    let sign: bool = sqrt_price < ONE;
    let rebased = if sign {
        ONE_SQUARED / sqrt_price
    } else {
        sqrt_price
    };

    let log2: u256 = _log2(rebased);

    let limit = math::mul_div(log2, 2 * ONE, LOG2_1_00001, sign);

    // We need to round up for negative sqrt prices
    let remainder: u256 = limit % ONE;
    let unsigned_limit: u256 = limit / ONE + if (remainder != 0 && sign) {
        1
    } else {
        0
    };

    let signed_limit: i32 = I32Trait::new(unsigned_limit.try_into().unwrap(), sign);
    shift_limit(signed_limit, width)
}

// Convert price to limit.
// 
// # Arguments
// * `price` - price encoded as UD47x28
// * `width` - limit width
// * `round_up` - round up if true, round down if false
//
// # Returns
// * `limit` - shifted limit
fn price_to_limit(price: u256, width: u32, round_up: bool) -> u32 {
    let sign: bool = price < ONE;
    let rebased = if sign {
        ONE_SQUARED / price
    } else {
        price
    };

    let log2: u256 = _log2(rebased);

    let limit = math::mul_div(log2, ONE, LOG2_1_00001, false);

    // Rounding up for negative prices is equivalent to rounding down for positive prices
    let remainder: u256 = limit % ONE;
    let unsigned_limit: u256 = limit / ONE
        + if (remainder != 0 && (!sign && round_up) || (sign && !round_up)) {
            1
        } else {
            0
        };

    let signed_limit: i32 = I32Trait::new(unsigned_limit.try_into().unwrap(), sign);
    shift_limit(signed_limit, width)
}

////////////////////////////////
// INTERNAL HELPERS
////////////////////////////////

// Helper function to calculate the binary logarithm.
fn _log2(x: u256) -> u256 {
    // Calculate the integer part of the logarithm.
    let n: u256 = bit_math::msb(x / ONE).into();

    // This is the integer part of the logarithm.
    let result_uint: u256 = n * ONE;

    // Calculate y = x / 2^n.
    let y = x / math::pow(2, n);

    // If y is the unit number, the fractional part is zero.
    if y == ONE {
        result_uint
    } else {
        // Calculate the fractional part via the iterative approximation.
        let delta = HALF;
        let final_result_uint = _log2_helper(y, result_uint, delta);
        final_result_uint
    }
}

// Helper function to recursively calculate the logarithm.
fn _log2_helper(y: u256, result_uint: u256, delta: u256,) -> u256 {
    if delta <= 0 {
        result_uint
    } else {
        let mut y = (y * y) / ONE;
        let mut result_uint = result_uint;
        if y >= 2 * ONE {
            result_uint += delta;
            y /= 2;
        }
        _log2_helper(y, result_uint, delta / 2)
    }
}

// Helper function to calculate the exponent 1.00001 ^ x.
//
// # Arguments
// * `x` - Exponent
//
// # Returns
// * `result` - Result of exponentiation
fn _exp1_00001(x: i32) -> u256 {
    let mut result: u256 = if x.val & 0x1 != 0 {
        0xffffac1d5317ab9e72ee0f7589b88f87
    } else {
        0x100000000000000000000000000000000
    };

    if x.val & 0x2 != 0 {
        result = math::mul_div(result, 0xffff583ac1ac1c114b9160ddeb4791b7, Q128, false);
    }
    if x.val & 0x4 != 0 {
        result = math::mul_div(result, 0xfffeb075f14b276d06cdbc6b138e4c4b, Q128, false);
    }
    if x.val & 0x8 != 0 {
        result = math::mul_div(result, 0xfffd60ed9a60ebcb383de6edb7557ef0, Q128, false);
    }
    if x.val & 0x10 != 0 {
        result = math::mul_div(result, 0xfffac1e213e349a0cf1e3d3ec62bf25c, Q128, false);
    }
    if x.val & 0x20 != 0 {
        result = math::mul_div(result, 0xfff583dfa4044e3dfe90c4057e3e4c27, Q128, false);
    }
    if x.val & 0x40 != 0 {
        result = math::mul_div(result, 0xffeb082d36bf2958d476ee75c4da258a, Q128, false);
    }
    if x.val & 0x80 != 0 {
        result = math::mul_div(result, 0xffd61212165632bd1dda4c1abdf5f9f2, Q128, false);
    }
    if x.val & 0x100 != 0 {
        result = math::mul_div(result, 0xffac2b0240039d9cdadb751e0acc14c5, Q128, false);
    }
    if x.val & 0x200 != 0 {
        result = math::mul_div(result, 0xff5871784dc6fa608dca410bdecb9ff5, Q128, false);
    }
    if x.val & 0x400 != 0 {
        result = math::mul_div(result, 0xfeb1509bdff34ccb280fad9a309403d0, Q128, false);
    }
    if x.val & 0x800 != 0 {
        result = math::mul_div(result, 0xfd6456c5e15445b458f4403d279c1a89, Q128, false);
    }
    if x.val & 0x1000 != 0 {
        result = math::mul_div(result, 0xfacf7ad7076227f61d95f764e8d7e35b, Q128, false);
    }
    if x.val & 0x2000 != 0 {
        result = math::mul_div(result, 0xf5b9e413dd1b4e7046f8f721e1f1b295, Q128, false);
    }
    if x.val & 0x4000 != 0 {
        result = math::mul_div(result, 0xebdd5589751f38fd7adce84988dba856, Q128, false);
    }
    if x.val & 0x8000 != 0 {
        result = math::mul_div(result, 0xd9501a6728f01c1f121094aacf4c9476, Q128, false);
    }
    if x.val & 0x10000 != 0 {
        result = math::mul_div(result, 0xb878e5d36699c3a0fd844110d8b99460, Q128, false);
    }
    if x.val & 0x20000 != 0 {
        result = math::mul_div(result, 0x84ee037828011d8035f12eb571b46c2b, Q128, false);
    }
    if x.val & 0x40000 != 0 {
        result = math::mul_div(result, 0x450650de5cb791d4a002074d7f179cb3, Q128, false);
    }
    if x.val & 0x80000 != 0 {
        result = math::mul_div(result, 0x129c67bfc1f3084f1f52dd418a4a8f6d, Q128, false);
    }
    if x.val & 0x100000 != 0 {
        result = math::mul_div(result, 0x15a5e2593066b11cd1c3ea05eb95f75, Q128, false);
    }
    if x.val & 0x200000 != 0 {
        result = math::mul_div(result, 0x1d4a2a0310ad5f70ad53ef4d3dcf3, Q128, false);
    }
    if x.val & 0x400000 != 0 {
        result = math::mul_div(result, 0x359e3010271ed5cfce08f99ab, Q128, false);
    }
    if x.val & 0x800000 != 0 {
        result = math::mul_div(result, 0xb3ae1a60d291e4872, Q128, false);
    }
    if x.val & 0x1000000 != 0 {
        result = math::mul_div(result, 0x7e, Q128, false);
    }

    // Take reciprocal if exponent is negative
    if !x.sign && x.val != 0 {
        result = BoundedU256::max() / result;
    }

    // Convert to UD47x28
    math::mul_div(result, ONE, math::pow(2, 128), true)
}
