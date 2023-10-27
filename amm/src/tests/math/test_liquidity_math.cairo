use integer::BoundedU256;

use amm::libraries::math::liquidity_math::{
    add_delta, liquidity_to_quote_amount, liquidity_to_base_amount
};
use amm::libraries::constants::MAX;
use amm::tests::helpers::utils::encode_sqrt_price;
use amm::types::i256::I256Trait;


////////////////////////////////
// CONSTANTS
////////////////////////////////

const ONE: u256 = 10000000000000000000000000000;

////////////////////////////////
// TESTS - add_delta
////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_add_delta_cases() {
    let mut liquidity = 0;
    let mut delta = I256Trait::new(0, false);
    add_delta(ref liquidity, delta);
    assert(liquidity == 0, '0 + 0');

    liquidity = 10;
    delta = I256Trait::new(0, false);
    add_delta(ref liquidity, delta);
    assert(liquidity == 10, '10 + 0');

    liquidity = 0;
    delta = I256Trait::new(10, false);
    add_delta(ref liquidity, delta);
    assert(liquidity == 10, '0 + 10');

    liquidity = 10;
    delta = I256Trait::new(10, false);
    add_delta(ref liquidity, delta);
    assert(liquidity == 20, '10 + 10');

    liquidity = 10;
    delta = I256Trait::new(10, true);
    add_delta(ref liquidity, delta);
    assert(liquidity == 0, '10 + -10');

    liquidity = MAX - 5;
    delta = I256Trait::new(5, false);
    add_delta(ref liquidity, delta);
    assert(liquidity == MAX, 'max-5 + 5');
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
#[available_gas(2000000000)]
fn test_add_delta_underflow() {
    let mut liquidity = 0;
    let delta = I256Trait::new(1, true);
    add_delta(ref liquidity, delta);
}

#[test]
#[should_panic(expected: ('AddDeltaOverflow',))]
#[available_gas(2000000000)]
fn test_AddDeltaOverflow() {
    let mut liquidity = MAX - 5;
    let delta = I256Trait::new(10, false);
    add_delta(ref liquidity, delta);
}


////////////////////////////////////
// TESTS - liquidity_to_quote_amount
////////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_liquidity_to_quote_amount_cases() {
    let mut start = encode_sqrt_price(1, 1);
    let mut end = encode_sqrt_price(2, 1);
    let mut liq = I256Trait::new(0, false);
    assert(
        liquidity_to_quote_amount(start, end, liq, true) == I256Trait::new(0, false), 'bd(1,/2,0,T)'
    );

    end = encode_sqrt_price(1, 1);
    liq = I256Trait::new(2, false);
    assert(
        liquidity_to_quote_amount(start, end, liq, true) == I256Trait::new(0, false), 'bd(1,1,2,T)'
    );

    let start = encode_sqrt_price(1, 2);
    let end = encode_sqrt_price(50, 2);
    let liq = I256Trait::new(100 * ONE, false);
    // no rounding occurs as we divide by ONE
    assert(
        liquidity_to_quote_amount(
            start, end, liq, true
        ) == I256Trait::new(4292893218813452475599155637900, false),
        'bd(/.5,/25,100,T)'
    );
    assert(
        liquidity_to_quote_amount(
            start, end, liq, false
        ) == I256Trait::new(4292893218813452475599155637900, false),
        'bd(/.5,/25,100,F)'
    );
}

/////////////////////////////////////
// TESTS - liquidity_to_base_amount
/////////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_liquidity_to_base_amount_cases() {
    let mut start = encode_sqrt_price(1, 1);
    let mut end = encode_sqrt_price(2, 1);
    let mut liq = I256Trait::new(0, false);
    assert(
        liquidity_to_base_amount(start, end, liq, true) == I256Trait::new(0, false), 'qd(1,/2,0,T)'
    );

    end = encode_sqrt_price(1, 1);
    liq = I256Trait::new(2, false);
    assert(
        liquidity_to_base_amount(start, end, liq, true) == I256Trait::new(0, false), 'qd(1,1,2,T)'
    );

    let start = encode_sqrt_price(1, 2);
    let end = encode_sqrt_price(50, 2);
    let liq = I256Trait::new(100 * ONE, false);
    assert(
        liquidity_to_base_amount(
            start, end, liq, true
        ) == I256Trait::new(1214213562373095048801688724266, false),
        'qd(/.5,/25,100,T)'
    );
    assert(
        liquidity_to_base_amount(
            start, end, liq, false
        ) == I256Trait::new(1214213562373095048801688724117, false),
        'qd(/.5,/25,100,F)'
    );
}

#[test]
#[should_panic(expected: ('MulDivByZero',))]
#[available_gas(2000000000)]
fn test_base_amount_delta_start_price_0() {
    let start = 0;
    let end = encode_sqrt_price(2, 1);
    let liq = I256Trait::new(100 * ONE, false);
    liquidity_to_base_amount(start, end, liq, true) == I256Trait::new(0, false);
}
