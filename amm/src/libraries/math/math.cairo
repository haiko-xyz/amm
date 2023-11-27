// Core lib imports.
use integer::{u256_wide_mul, u512_safe_div_rem_by_u256, u256_try_as_non_zero};
use integer::U256DivRem;
use integer::BoundedU256;
use option::OptionTrait;

// Raises u256 number to the power of exponent using the exponentiation by squaring algorithm.
// 
// # Arguments
// * `quote` - The quote number.
// * `exp` - The exponent.
//
// # Returns
// * `u256` - The result of the exponentiation.
fn pow(quote: u256, exp: u256) -> u256 {
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
fn mul_div(a: u256, b: u256, c: u256, round_up: bool) -> u256 {
    let product = u256_wide_mul(a, b);
    let (q, r) = u512_safe_div_rem_by_u256(product, u256_try_as_non_zero(c).expect('MulDivByZero'));
    if round_up && r > 0 {
        let result = u256 { low: q.limb0, high: q.limb1 };
        assert(result != BoundedU256::max() && q.limb2 == 0 && q.limb3 == 0, 'MulDivOF');
        u256 { low: q.limb0, high: q.limb1 } + 1
    } else {
        assert(q.limb2 == 0 && q.limb3 == 0, 'MulDivOF');
        u256 { low: q.limb0, high: q.limb1 }
    }
}
