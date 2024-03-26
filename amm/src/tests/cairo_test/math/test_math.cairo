use core::integer::BoundedInt;

use amm::libraries::math::math::{pow, mul_div};


////////////////////////////////
// CONSTANTS
////////////////////////////////

const ONE: u256 = 10000000000000000000000000000;

////////////////////////////////
// TESTS - pow
////////////////////////////////

#[test]
fn test_pow() {
    assert(pow(0, 0) == 1, 'pow(0,0)');
    assert(pow(0, 1) == 0, 'pow(0,1)');
    assert(pow(0, 31953) == 0, 'pow(0,31953)');
    assert(pow(1, 0) == 1, 'pow(1,0)');
    assert(pow(1, 1) == 1, 'pow(1,1)');
    assert(pow(1, 31953) == 1, 'pow(1,31953)');
    assert(pow(2, 3) == 8, 'pow(2,3)');
    assert(pow(10, 4) == 10000, 'pow(10,4)');
    assert(pow(BoundedInt::max(), 1) == BoundedInt::max(), 'pow(MAX,1)');
    assert(
        pow(
            340282366920938463463374607431768211455, 2
        ) == 115792089237316195423570985008687907852589419931798687112530834793049593217025,
        'pow(sqrt(MAX - 1),2)'
    );
}

////////////////////////////////
// TESTS - mul_div
////////////////////////////////

#[test]
fn test_mul_div() {
    assert(mul_div(1, 1, 1, false) == 1, 'mul_div(1,1,1,F)');
    assert(mul_div(1, 1, 1, true) == 1, 'mul_div(1,1,1,T)');
    assert(mul_div(ONE, 1, 2, false) == ONE / 2, 'mul_div(ONE,1,2,F)');
    assert(mul_div(ONE, 1, 2, true) == ONE / 2, 'mul_div(ONE,1,2,T)');
    assert(mul_div(ONE, 5, 30, false) == ONE / 6, 'mul_div(ONE,5,30,F)');
    assert(mul_div(ONE, 5, 30, true) == ONE / 6 + 1, 'mul_div(ONE,5,30,T)');
    assert(mul_div(ONE, ONE * ONE, 5 * ONE, false) == ONE * ONE / 5, 'mul_div(ONE,ONE_SQ,5*ONE,F)');
    assert(mul_div(ONE, ONE * ONE, 5 * ONE, true) == ONE * ONE / 5, 'mul_div(ONE,ONE_SQ,5*ONE,T)');
    assert(mul_div(ONE, ONE * ONE, 3 * ONE, false) == ONE * ONE / 3, 'mul_div(ONE,ONE_SQ,3*ONE,F)');
    assert(
        mul_div(ONE, ONE * ONE, 3 * ONE, true) == ONE * ONE / 3 + 1, 'mul_div(ONE,ONE_SQ,3*ONE,T)'
    );
    assert(
        mul_div(
            BoundedInt::max(), BoundedInt::max(), BoundedInt::max(), false
        ) == BoundedInt::max(),
        'mul_div(MAX,MAX,MAX,F)'
    );
    assert(
        mul_div(BoundedInt::max(), BoundedInt::max(), BoundedInt::max(), true) == BoundedInt::max(),
        'mul_div(MAX,MAX,MAX,T)'
    );
}

#[test]
#[should_panic(expected: ('MulDivByZero',))]
fn test_mul_div_denominator_0() {
    mul_div(1, 1, 0, false);
}

#[test]
#[should_panic(expected: ('MulDivByZero',))]
fn test_mul_div_denominator_0_roundup() {
    mul_div(1, 1, 0, true);
}

#[test]
#[should_panic(expected: ('MulDivOF',))]
fn test_mul_div_numerator_overflow() {
    mul_div(BoundedInt::max(), BoundedInt::max(), 1, false);
}

#[test]
#[should_panic(expected: ('MulDivOF',))]
fn test_mul_div_numerator_overflow_roundup() {
    mul_div(BoundedInt::max(), BoundedInt::max(), 1, true);
}

#[test]
#[should_panic(expected: ('MulDivOF',))]
fn test_mul_div_result_overflow_roundup() {
    mul_div(BoundedInt::max() / 2 + 1, 2, 1, true);
}

#[test]
#[should_panic(expected: ('MulDivOF',))]
fn test_mul_div_result_overflow_roundup_alt() {
    mul_div(BoundedInt::max(), BoundedInt::max(), BoundedInt::max() - 1, true);
}

