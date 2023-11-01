use amm::libraries::limit_prices::{check_limits, check_threshold};
use amm::libraries::constants::{
    OFFSET, MAX_LIMIT, MAX_LIMIT_SHIFTED, MIN_SQRT_PRICE, MAX_SQRT_PRICE
};

////////////////////////////////
// TESTS - check_limits
////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_check_limits_cases() {
    check_limits(0, 1, 1, true);
    check_limits(1, 2, 1, true);
    check_limits(MAX_LIMIT_SHIFTED - 1, MAX_LIMIT_SHIFTED, 1, true);
    check_limits(10, 1000, 10, true);
    check_limits(5, 10, 5, true);
}

#[test]
#[available_gas(2000000000)]
#[should_panic(expected: ('LimitsUnordered',))]
fn test_check_limits_limits_equal() {
    check_limits(1, 1, 1, true);
}

#[test]
#[available_gas(2000000000)]
#[should_panic(expected: ('LimitsUnordered',))]
fn test_check_limits_wrong_order() {
    check_limits(2, 1, 1, true);
}

#[test]
#[available_gas(2000000000)]
#[should_panic(expected: ('UpperLimitOverflow',))]
fn test_check_limits_upper_limit_overflow() {
    check_limits(1, OFFSET + MAX_LIMIT + 1, 1, true);
}

////////////////////////////////
// TESTS - check_threshold
////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_check_threshold_cases() {
    check_threshold(17000000000, 16000000000, true);
    check_threshold(MIN_SQRT_PRICE + 1, MIN_SQRT_PRICE, true);
    check_threshold(MAX_SQRT_PRICE, MAX_SQRT_PRICE - 1, true);

    check_threshold(12000000000, 16000000000, false);
    check_threshold(MIN_SQRT_PRICE, MIN_SQRT_PRICE + 1, false);
    check_threshold(MAX_SQRT_PRICE - 1, MAX_SQRT_PRICE, false);
}

#[test]
#[available_gas(2000000000)]
#[should_panic(expected: ('ThresholdInvalid',))]
fn test_check_threshold_current_exceeds_bid() {
    check_threshold(1200000000, 1600000000, true);
}

#[test]
#[available_gas(2000000000)]
#[should_panic(expected: ('ThresholdInvalid',))]
fn test_check_threshold_current_equals_bid() {
    check_threshold(1600000000, 1600000000, true);
}

#[test]
#[available_gas(2000000000)]
#[should_panic(expected: ('ThresholdInvalid',))]
fn test_check_threshold_ask_equals_current() {
    check_threshold(1600000000, 1600000000, false);
}

#[test]
#[available_gas(2000000000)]
#[should_panic(expected: ('ThresholdInvalid',))]
fn test_check_threshold_ask_exceeds_current() {
    check_threshold(2000000000, 1600000000, false);
}

#[test]
#[available_gas(2000000000)]
#[should_panic(expected: ('ThresholdInvalid',))]
fn test_check_threshold_bid_overflow() {
    check_threshold(MAX_SQRT_PRICE + 1, 1600000000, true);
}

#[test]
#[available_gas(2000000000)]
#[should_panic(expected: ('ThresholdInvalid',))]
fn test_check_threshold_ask_underflow() {
    check_threshold(MIN_SQRT_PRICE - 1, 1600000000, false);
}
