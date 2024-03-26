// Core lib imports.
use core::integer::{BoundedInt, u256_wide_mul, u512_safe_div_rem_by_u256};
use core::zeroable::NonZero;

// Raises u256 number to the power of exponent using the exponentiation by squaring algorithm.
// 
// # Arguments
// * `quote` - The quote number.
// * `exp` - The exponent.
//
// # Returns
// * `u256` - The result of the exponentiation.
pub fn pow(quote: u256, exp: u256) -> u256 {
    if exp == 0 {
        1
    } else if exp == 1 {
        quote
    } else if exp % 2 == 0 {
        let half = pow(quote, exp / 2);
        half * half
    } else {
        quote * pow(quote, exp - 1)
    }
}

// Multiplies two u256 numbers and divides the result by a third. Optionally rounds up to the nearest integer.
//
// # Arguments
// * `a` - The first multiplicand.
// * `b` - The second multiplicand.
// * `c` - The divisor.
//
// # Returns
// * `result` - Result.
pub fn mul_div(a: u256, b: u256, c: u256, round_up: bool) -> u256 {
    let product = u256_wide_mul(a, b);
    let denominator: NonZero<u256> = c.try_into().expect('MulDivByZero');
    let (q, r) = u512_safe_div_rem_by_u256(product, denominator);
    if round_up && r > 0 {
        let result = u256 { low: q.limb0, high: q.limb1 };
        assert(result != BoundedInt::max() && q.limb2 == 0 && q.limb3 == 0, 'MulDivOF');
        u256 { low: q.limb0, high: q.limb1 } + 1
    } else {
        assert(q.limb2 == 0 && q.limb3 == 0, 'MulDivOF');
        u256 { low: q.limb0, high: q.limb1 }
    }
}
