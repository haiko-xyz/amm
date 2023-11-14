use amm::libraries::constants::{MAX_LIMIT, MAX_SQRT_PRICE, MIN_SQRT_PRICE};
use amm::libraries::math::price_math::{
    shift_limit, unshift_limit, limit_to_sqrt_price, sqrt_price_to_limit, max_limit
};
use snforge_std::PrintTrait;

////////////////////////////////
// TESTS
////////////////////////////////

// Checks invariants: 
// 1. Shifted max limit should be multiple of width.
// 2. Unshifted max limit should be multiple of width.
// 3. At most 1 limit between max limit and MAX_LIMIT can be multiple of width.
#[test]
fn test_max_limit_invariant(width: u16) {
    if width == 0 {
        return;
    }

    let max = max_limit(width.into());

    assert(max % width.into() == 0, 'Invariant 1');
    assert(unshift_limit(max, width.into()).val % width.into() == 0, 'Invariant 2');

    let mut i = unshift_limit(max, width.into()).val;
    let mut count: u32 = 0;
    loop {
        if i >= MAX_LIMIT {
            break;
        }
        if i % width.into() == 0 {
            count += 1;
        }
        i += width.into();
    };
    assert(count <= 1, 'Invariant 3');
}

// Checks invariant: unshifting and shifting limit should result in starting value.
#[test]
fn test_unshift_and_shift_limit_invariant(limit: u32, width: u16) {
    if width == 0 || limit > max_limit(width.into()) {
        return;
    }
    let unshifted = unshift_limit(limit, width.into());
    let shifted = shift_limit(unshifted, width.into());
    assert(limit == shifted, 'Shift unshift limit');
}

// Checks invariants:
// 1. Sqrt price of limit-1 and limit+1 should be properly ordered
// 2. Sqrt price is between MIN_SQRT_PRICE and MAX_SQRT_PRICE
#[test]
fn test_limit_to_sqrt_price_invariants(limit: u32, width: u16) {
    if width == 0 || limit > max_limit(width.into()) || limit == 0 {
        return;
    }

    let sqrt_price = limit_to_sqrt_price(limit, width.into());
    let sqrt_price_minus_one = limit_to_sqrt_price(limit - 1, width.into());
    let sqrt_price_plus_one = limit_to_sqrt_price(limit + 1, width.into());

    // Invariant 1
    assert(sqrt_price_minus_one < sqrt_price_plus_one, 'Invariant 1');

    // Invariant 2
    assert(sqrt_price >= MIN_SQRT_PRICE, 'Invariant 2a');
    assert(sqrt_price <= MAX_SQRT_PRICE, 'Invariant 2b');
}

// Checks invariants:
// 1. Starting sqrt price is between sqrt prices at returned limit and limit+1
// 2. Returned limit is between min and max limits
#[test]
fn test_sqrt_price_to_limit_invariants(sqrt_price: u256, width: u16) {
    if width == 0 || sqrt_price < MIN_SQRT_PRICE || sqrt_price > MAX_SQRT_PRICE {
        return;
    }

    let limit = sqrt_price_to_limit(sqrt_price, width.into());
    let sqrt_price_at_limit = limit_to_sqrt_price(limit, width.into());
    let sqrt_price_at_limit_plus_one = limit_to_sqrt_price(limit + 1, width.into());

    // Invariant 1
    assert(sqrt_price >= sqrt_price_at_limit, 'Invariant 1a');
    assert(sqrt_price <= sqrt_price_at_limit_plus_one, 'Invariant 1b');

    // Invariant 2
    assert(limit <= max_limit(width.into()), 'Invariant 2');
}
