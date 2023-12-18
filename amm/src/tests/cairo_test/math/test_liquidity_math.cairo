use integer::BoundedU128;
use debug::PrintTrait;

use amm::libraries::math::price_math::limit_to_sqrt_price;
use amm::libraries::math::liquidity_math::{
    add_delta, liquidity_to_quote, liquidity_to_base, base_to_liquidity, quote_to_liquidity,
    liquidity_to_amounts, max_liquidity_per_limit
};
use amm::libraries::constants::{ONE, OFFSET, MAX_NUM_LIMITS, MAX_SCALED};
use amm::tests::common::utils::{encode_sqrt_price, approx_eq, to_e28_u128};
use amm::types::i128::I128Trait;
use amm::types::i256::I256Trait;

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
struct TestCase {
    lower_sqrt_price: u256,
    upper_sqrt_price: u256,
    liquidity: u128,
    round_up: bool,
    base_amount: u256,
    quote_amount: u256,
}

////////////////////////////////
// TESTS - add_delta
////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_add_delta_cases() {
    let mut liquidity = 0;
    let mut delta = I128Trait::new(0, false);
    add_delta(ref liquidity, delta);
    assert(liquidity == 0, '0 + 0');

    liquidity = 10;
    delta = I128Trait::new(0, false);
    add_delta(ref liquidity, delta);
    assert(liquidity == 10, '10 + 0');

    liquidity = 0;
    delta = I128Trait::new(10, false);
    add_delta(ref liquidity, delta);
    assert(liquidity == 10, '0 + 10');

    liquidity = 10;
    delta = I128Trait::new(10, false);
    add_delta(ref liquidity, delta);
    assert(liquidity == 20, '10 + 10');

    liquidity = 10;
    delta = I128Trait::new(10, true);
    add_delta(ref liquidity, delta);
    assert(liquidity == 0, '10 + -10');

    let max = BoundedU128::max();
    liquidity = max - 5;
    delta = I128Trait::new(5, false);
    add_delta(ref liquidity, delta);
    assert(liquidity == max, 'max-5 + 5');
}

#[test]
#[should_panic(expected: ('u128_sub Overflow',))]
#[available_gas(2000000000)]
fn test_add_delta_underflow() {
    let mut liquidity = 0;
    let delta = I128Trait::new(1, true);
    add_delta(ref liquidity, delta);
}

/////////////////////////////////////
// TEST CASES
/////////////////////////////////////

fn test_cases_set1() -> Span<TestCase> {
    let one: u128 = 10000000000000000000000000000;
    let cases: Span<TestCase> = array![
        TestCase {
            lower_sqrt_price: encode_sqrt_price(1, 1),
            upper_sqrt_price: encode_sqrt_price(2, 1),
            liquidity: 0,
            round_up: true,
            base_amount: 0,
            quote_amount: 0,
        },
        TestCase {
            lower_sqrt_price: encode_sqrt_price(1, 1),
            upper_sqrt_price: encode_sqrt_price(1, 1),
            liquidity: 2,
            round_up: true,
            base_amount: 0,
            quote_amount: 0,
        },
        TestCase {
            lower_sqrt_price: encode_sqrt_price(1, 2),
            upper_sqrt_price: encode_sqrt_price(50, 2),
            liquidity: to_e28_u128(100),
            round_up: true,
            base_amount: 1214213562373095048801688724210,
            quote_amount: 4292893218813452475599155637896,
        },
        TestCase {
            lower_sqrt_price: encode_sqrt_price(1, 2),
            upper_sqrt_price: encode_sqrt_price(50, 2),
            liquidity: to_e28_u128(100),
            round_up: false,
            base_amount: 1214213562373095048801688724210,
            quote_amount: 4292893218813452475599155637896,
        },
    ]
        .span();
    cases
}

fn test_cases_set2() -> Span<TestCase> {
    let cases: Span<TestCase> = array![
        TestCase {
            lower_sqrt_price: encode_sqrt_price(1685, 1),
            upper_sqrt_price: encode_sqrt_price(2015, 1),
            liquidity: to_e28_u128(33),
            round_up: true,
            base_amount: 687713693369719147582043042,
            quote_amount: 1267199957555168349116319634523,
        },
        TestCase {
            lower_sqrt_price: 121639496252071918121639496252071,
            upper_sqrt_price: 233337802229883332333378022298108,
            liquidity: 2676354190899,
            round_up: true,
            base_amount: 105324756,
            quote_amount: 29894422932003441,
        },
        TestCase {
            lower_sqrt_price: 73715557888566391711047589037374,
            upper_sqrt_price: 230171892267239274781237123710089,
            liquidity: 78853949886612102384123699749718,
            round_up: true,
            base_amount: 7271184400162342693012229827,
            quote_amount: 1233719995053889776408830382749178183,
        },
        TestCase {
            lower_sqrt_price: 822372245086810000000000000000000000000000000000000000000000000000000000,
            upper_sqrt_price: 1802908542837070000000000000000000000000000000000000000000000000000000000,
            liquidity: 1349167646237,
            round_up: true,
            base_amount: 1,
            quote_amount: 132290784888566048265477162000000000000000000000000000000
        },
    ]
        .span();
    cases
}

/////////////////////////////////////
// TESTS - liquidity_to_quote
/////////////////////////////////////

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
        if i == cases.len() {
            break;
        }
        let case = *cases.at(i);
        let quote = liquidity_to_quote(
            case.lower_sqrt_price,
            case.upper_sqrt_price,
            I128Trait::new(case.liquidity, false),
            case.round_up
        )
            .val;
        assert(approx_eq(quote, case.quote_amount, 10), 'l->q 00' + i.into());
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
        if i == cases.len() {
            break;
        }
        let case = *cases.at(i);
        let base = liquidity_to_base(
            case.lower_sqrt_price,
            case.upper_sqrt_price,
            I128Trait::new(case.liquidity, false),
            case.round_up
        )
            .val;
        assert(approx_eq(base, case.base_amount, 100), 'l->b 00' + i.into());
        i += 1;
    };
}

#[test]
#[should_panic(expected: ('MulDivByZero',))]
#[available_gas(2000000000)]
fn test_base_amount_delta_start_price_0() {
    let start = 0;
    let end = encode_sqrt_price(2, 1);
    let liq = I128Trait::new(to_e28_u128(100), false);
    liquidity_to_base(start, end, liq, true) == I256Trait::new(0, false);
}

/////////////////////////////////////
// TESTS - quote_to_liquidity
/////////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_quote_to_liquidity_set1() {
    let cases = test_cases_set1();
    test_quote_to_liquidity_cases(cases);
}

#[test]
#[available_gas(2000000000)]
fn test_quote_to_liquidity_cases_set2() {
    let cases = test_cases_set2();
    test_quote_to_liquidity_cases(cases);
}

fn test_quote_to_liquidity_cases(cases: Span<TestCase>) {
    let mut i = 0;
    loop {
        if i == cases.len() {
            break;
        }
        let case = *cases.at(i);
        if case.quote_amount == 0 {
            i += 1;
            continue;
        }
        let liquidity = quote_to_liquidity(
            case.lower_sqrt_price, case.upper_sqrt_price, case.quote_amount, false
        );
        assert(approx_eq(liquidity.into(), case.liquidity.into(), 100), 'q->l 00' + i.into());
        i += 1;
    };
}

/////////////////////////////////////
// TESTS - base_to_liquidity
/////////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_base_to_liquidity_set1() {
    let cases = test_cases_set1();
    test_base_to_liquidity_cases(cases);
}

#[test]
#[available_gas(2000000000)]
fn test_base_to_liquidity_cases_set2() {
    let cases = test_cases_set2();
    test_base_to_liquidity_cases(cases);
}

fn test_base_to_liquidity_cases(cases: Span<TestCase>) {
    let mut i = 0;
    loop {
        if i == cases.len() {
            break;
        }
        let case = *cases.at(i);
        if case.base_amount == 0 || case.base_amount < 10000000000 {
            i += 1;
            continue;
        }
        let liquidity = base_to_liquidity(
            case.lower_sqrt_price, case.upper_sqrt_price, case.base_amount, false
        );
        assert(approx_eq(liquidity.into(), case.liquidity.into(), 10000), 'b->l 00' + i.into());
        i += 1;
    };
}

/////////////////////////////////////
// TESTS - liquidity_to_amounts
/////////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_liquidity_to_amounts() {
    // Case 1: Position range is above curr price.
    let curr_limit = OFFSET + 80000;
    let width = 1;
    let curr_sqrt_price = limit_to_sqrt_price(curr_limit, width);
    let mut lower_sqrt_price = limit_to_sqrt_price(OFFSET + 85000, width);
    let mut upper_sqrt_price = limit_to_sqrt_price(OFFSET + 90000, width);
    let liquidity = I128Trait::new(10000, false);
    let (mut base_amount, mut quote_amount) = liquidity_to_amounts(
        liquidity, curr_sqrt_price, lower_sqrt_price, upper_sqrt_price
    );
    assert(base_amount.val == 162, 'above base');
    assert(quote_amount.val == 0, 'above quote');

    // Case 2: Position range is below curr price.
    lower_sqrt_price = limit_to_sqrt_price(OFFSET + 70000, width);
    upper_sqrt_price = limit_to_sqrt_price(OFFSET + 75000, width);
    let (base_amount, quote_amount) = liquidity_to_amounts(
        liquidity, curr_sqrt_price, lower_sqrt_price, upper_sqrt_price
    );
    assert(base_amount.val == 0, 'below base');
    assert(quote_amount.val == 360, 'below quote');

    // Case 3: Position range wraps curr price.
    lower_sqrt_price = limit_to_sqrt_price(OFFSET + 75000, width);
    upper_sqrt_price = limit_to_sqrt_price(OFFSET + 85000, width);
    let (base_amount, quote_amount) = liquidity_to_amounts(
        liquidity, curr_sqrt_price, lower_sqrt_price, upper_sqrt_price
    );
    assert(approx_eq(base_amount.val, 166, 1), 'wrap base');
    assert(quote_amount.val == 369, 'wrap quote');
}

#[test]
#[available_gas(2000000000)]
fn test_max_liquidity_per_limit() {
    assert(max_liquidity_per_limit(1) == 21518811465203357833463505223041, 'max_liq(1)');

    assert(max_liquidity_per_limit(10) == 215187992179309303371584738018453, 'max_liq(10)');

    assert(max_liquidity_per_limit(250) == 5379618157285522867539991264295826, 'max_liq(250)');

    assert(max_liquidity_per_limit(MAX_NUM_LIMITS) == BoundedU128::max(), 'max_liq(MAX)');
}
