use integer::BoundedU128;
use cmp::{min, max};
use integer::{u256_wide_mul, u512_safe_div_rem_by_u256, u256_try_as_non_zero};

use amm::libraries::math::math::mul_div;

////////////////////////////////
// TESTS
////////////////////////////////

// Checks for following invariants:
// 1. If (x * y) % d > 0, then muldiv ceil - floor = 1.
//    If (x * y) % d = 0, then muldiv ceil = floor
// 2. mul_div(floor, d, y, false) <= x
//    mul_div(ceil, d, y, true) >= x
// 3. mul_div(floor, d, x, false) <= y
//    mul_div(ceil, d, x, true) >= y 
#[test]
fn test_mul_div_invariants(x: u256, y: u256, d: u256,) {
    if d == 0 {
        return;
    }

    // Return if overflow
    let (overflow, rem) = check_for_overflow(x, y, d);
    if overflow {
        return;
    }

    // Invariant 1
    let ceil = mul_div(x, y, d, true);
    let floor = mul_div(x, y, d, false);
    if rem > 0 {
        assert(ceil - floor == 1, 'Ceil - floor == 1');
    } else {
        assert(ceil == floor, 'Ceil == floor');
    }

    // Invariant 2
    if y != 0 {
        let (overflow_2, _) = check_for_overflow(ceil, d, y);
        if overflow_2 {
            return;
        }

        let x1 = mul_div(floor, d, y, false);
        let x2 = mul_div(ceil, d, y, true);
        assert(x1 <= x, 'x1 <= x');
        assert(x2 >= x, 'x2 >= x');
    }

    // Invariant 3
    if x != 0 {
        let (overflow_3, _) = check_for_overflow(ceil, d, x);
        if overflow_3 {
            return;
        }

        let y1 = mul_div(floor, d, x, false);
        let y2 = mul_div(ceil, d, x, true);
        assert(y1 <= y, 'y1 <= y');
        assert(y2 >= y, 'y2 >= y');
    }
}

////////////////////////////////
// HELPERS
////////////////////////////////

// Helper function to check for overflow on `mul_div`.
//
// # Arguments
// * `x` - first operand
// * `y` - second operand
// * `d` - divisor
//
// # Returns
// * `overflow` - true if overflow occured
// * `rem` - remainder of mul div operation
fn check_for_overflow(x: u256, y: u256, d: u256) -> (bool, u256) {
    let prod = u256_wide_mul(x, y);
    let (q, rem) = u512_safe_div_rem_by_u256(prod, u256_try_as_non_zero(d).unwrap());
    if q.limb2 != 0 || q.limb3 != 0 {
        return (true, rem);
    }
    return (false, rem);
}
