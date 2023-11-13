use integer::BoundedU256;

use amm::libraries::math::liquidity_math::{add_delta, liquidity_to_quote, liquidity_to_base};
use amm::libraries::constants::{MAX, ONE};
use amm::tests::common::utils::{encode_sqrt_price, approx_eq};
use amm::types::i256::I256Trait;

use debug::PrintTrait;

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
struct TestCase {
    lower_sqrt_price: u256,
    upper_sqrt_price: u256,
    liquidity: u256,
    round_up: bool,
    base_exp: u256,
    quote_exp: u256,
}

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

///////////////////////////////////////////////////
// TESTS - liquidity_to_quote, liquidity_to_base
///////////////////////////////////////////////////

fn test_cases_set1() -> Span<TestCase> {
    let cases: Span<TestCase> = array![
        TestCase {
            lower_sqrt_price: encode_sqrt_price(1, 1),
            upper_sqrt_price: encode_sqrt_price(2, 1),
            liquidity: 0,
            round_up: true,
            base_exp: 0,
            quote_exp: 0,
        },
        TestCase {
            lower_sqrt_price: encode_sqrt_price(1, 1),
            upper_sqrt_price: encode_sqrt_price(1, 1),
            liquidity: 2,
            round_up: true,
            base_exp: 0,
            quote_exp: 0,
        },
        TestCase {
            lower_sqrt_price: encode_sqrt_price(1, 2),
            upper_sqrt_price: encode_sqrt_price(50, 2),
            liquidity: 100 * ONE,
            round_up: true,
            base_exp: 1214213562373095048801688724210,
            quote_exp: 4292893218813452475599155637896,
        },
        TestCase {
            lower_sqrt_price: encode_sqrt_price(1, 2),
            upper_sqrt_price: encode_sqrt_price(50, 2),
            liquidity: 100 * ONE,
            round_up: false,
            base_exp: 1214213562373095048801688724210,
            quote_exp: 4292893218813452475599155637896,
        },
    ].span();
    cases
}

fn test_cases_set2() -> Span<TestCase> {
    let cases: Span<TestCase> = array![
        TestCase {
            lower_sqrt_price: encode_sqrt_price(1685, 1),
            upper_sqrt_price: encode_sqrt_price(2015, 1),
            liquidity: 33 * ONE,
            round_up: true,
            base_exp: 687713693369719147582043042,
            quote_exp: 1267199957555168349116319634523,
        },
        TestCase {
            lower_sqrt_price: 121639496252071918121639496252071,
            upper_sqrt_price: 233337802229883332333378022298108,
            liquidity: 2676354190899,
            round_up: true,
            base_exp: 105324756,
            quote_exp: 29894422932003441,
        },
        TestCase {
            lower_sqrt_price: 73715557888566391711047589037374,
            upper_sqrt_price: 230171892267239274781237123710089,
            liquidity: 78853949886612102384123699749718,
            round_up: true,
            base_exp: 7271184400162342693012229827,
            quote_exp: 1233719995053889776408830382749178183,
        },
        TestCase {
            lower_sqrt_price: 822372245086810000000000000000000000000000000000000000000000000000000000,
            upper_sqrt_price: 1802908542837070000000000000000000000000000000000000000000000000000000000,
            liquidity: 1349167646237,
            round_up: true,
            base_exp: 1,
            quote_exp: 132290784888566048265477162000000000000000000000000000000
        },
        TestCase {
            lower_sqrt_price: 42045765511869000000000000000000,
            upper_sqrt_price: 183131552704515000000000000000000,
            liquidity: 474518159348736546111389172398901274095791231015231000000000000000000,
            round_up: true,
            base_exp: 86946211086165655591010015832212364180061819198653137971033493500,
            quote_exp: 6694776804892192838968383171335234269706615406494047211195719122600000000,
        }
    ].span();
    cases
}

#[test]
#[available_gas(2000000000)]
fn test_liquidity_to_quote_cases_set1() {
    let cases = test_cases_set1();
    test_liquidity_to_quote_cases(cases);
}

#[test]
#[available_gas(2000000000)]
fn test_liquidity_to_quote_cases_set2() {
    let cases = test_cases_set2();
    test_liquidity_to_quote_cases(cases);
}

fn test_liquidity_to_quote_cases(cases: Span<TestCase>) {
    let mut i = 0;
    loop {
        if i == cases.len() { break; }
        let case = *cases.at(i);
        let quote = liquidity_to_quote(
            case.lower_sqrt_price,
            case.upper_sqrt_price,
            I256Trait::new(case.liquidity, false),
            case.round_up
        ).val;
        assert(approx_eq(quote, case.quote_exp, 10), 'l->q 00' + i.into());
        i += 1;
    };
}

/////////////////////////////////////
// TESTS - liquidity_to_base
/////////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_liquidity_to_base_cases_set1() {
    let cases = test_cases_set1();
    test_liquidity_to_base_cases(cases);
}

#[test]
#[available_gas(2000000000)]
fn test_liquidity_to_base_cases_set2() {
    let cases = test_cases_set2();
    test_liquidity_to_base_cases(cases);
}

fn test_liquidity_to_base_cases(cases: Span<TestCase>) {
    let mut i = 0;
    loop {
        if i == cases.len() { break; }
        let case = *cases.at(i);
        let base = liquidity_to_base(
            case.lower_sqrt_price,
            case.upper_sqrt_price,
            I256Trait::new(case.liquidity, false),
            case.round_up
        ).val;
        base.print();
        assert(approx_eq(base, case.base_exp, 100), 'l->b 00' + i.into());
        i += 1;
    };
}

#[test]
#[should_panic(expected: ('MulDivByZero',))]
#[available_gas(2000000000)]
fn test_base_amount_delta_start_price_0() {
    let start = 0;
    let end = encode_sqrt_price(2, 1);
    let liq = I256Trait::new(100 * ONE, false);
    liquidity_to_base(start, end, liq, true) == I256Trait::new(0, false);
}
