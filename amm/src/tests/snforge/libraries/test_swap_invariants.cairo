use integer::BoundedU256;

use amm::libraries::constants::{MIN_SQRT_PRICE, MAX_SQRT_PRICE};
use amm::libraries::swap::compute_swap_amounts;
use amm::tests::common::utils::approx_eq;

use snforge_std::PrintTrait;

// Check following invariants:
// 1. Amount in + fee <= u256 max
// 2. If exact input, amount out <= amount remaining
//    If exact output, amount in <= amount remaining
// 3. If current price = target price, amount in = amount out = fee = 0
// 4. If next price != target price and:
//    - Exact input, amount in + fee == amount remaining
//    - Exact output, amount out == amount remaining
// 5. If target price <= curr price, target price <= next price <= curr price
//    Else if target price > curr price, curr price <= next price <= target price
#[test]
fn test_compute_swap_amounts_invariants(
    curr_sqrt_price: u128,
    target_sqrt_price: u128,
    liquidity: u128,
    amount_rem: u128,
    fee_rate: u8,
    width: u16,
) {
    // Return if invalid
    if curr_sqrt_price.into() < MIN_SQRT_PRICE
        || target_sqrt_price.into() < MIN_SQRT_PRICE
        || width == 0
        || liquidity == 0
        || amount_rem == 0 {
        return;
    }

    // Compute swap amounts
    let exact_input = amount_rem % 2 == 0; // bool fuzzing not supported, so use even/odd for rng
    let (amount_in, amount_out, fees, next_sqrt_price) = compute_swap_amounts(
        curr_sqrt_price.into(),
        target_sqrt_price.into(),
        liquidity.into(),
        amount_rem.into(),
        fee_rate.into(),
        exact_input,
        width.into(),
    );

    // Invariant 1
    assert(amount_in + fees <= BoundedU256::max(), 'Invariant 1');

    // Invariant 2
    if exact_input {
        assert(amount_in <= amount_rem.into(), 'Invariant 2a');
    } else {
        assert(amount_out <= amount_rem.into(), 'Invariant 2b');
    }

    // Invariant 3
    if curr_sqrt_price == target_sqrt_price {
        assert(amount_in == 0 && amount_out == 0 && fees == 0, 'Invariant 3');
    }

    // Invariant 4
    if next_sqrt_price != target_sqrt_price.into() {
        if exact_input {
            // Rounding error due to fee calculation which rounds down `amount_rem`
            assert(approx_eq(amount_in + fees, amount_rem.into(), 1), 'Invariant 4a');
        } else {
            assert(approx_eq(amount_out, amount_rem.into(), 1), 'Invariant 4b');
        }
    }

    // Invariant 5
    if target_sqrt_price <= curr_sqrt_price {
        assert(
            target_sqrt_price.into() <= next_sqrt_price && 
            next_sqrt_price <= curr_sqrt_price.into(),
            'Invariant 5a'
        );
    } else {
        assert(
            curr_sqrt_price.into() <= next_sqrt_price && 
            next_sqrt_price <= target_sqrt_price.into(),
            'Invariant 5b'
        );
    }
}
