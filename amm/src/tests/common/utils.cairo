use cmp::min;
use clone::Clone;

use amm::libraries::math::math;

//////////////////////////////
// CONSTANTS
//////////////////////////////

const Q128: u256 = 340282366920938463463374607431768211456;

const Q100: u256 = 1267650600228229401496703205376;

const Q64: u256 = 18446744073709551616;

const Q32: u256 = 4294967296;

const Q16: u256 = 65536;

const E18: u256 = 1000000000000000000;

const ONE: u256 = 10000000000000000000000000000;

const ONE_SQUARED: u256 = 100000000000000000000000000000000000000000000000000000000;

//////////////////////////////
// FUNCTIONS
//////////////////////////////

fn encode_sqrt_price(quote_reserves: u256, base_reserves: u256) -> u256 {
    _sqrt(math::mul_div(quote_reserves, ONE_SQUARED, base_reserves, false))
}

fn approx_eq(x: u256, y: u256, threshold: u256) -> bool {
    if x > y {
        x - y <= threshold
    } else {
        y - x <= threshold
    }
}

fn approx_eq_pct(x: u256, y: u256, precision: u256) -> bool {
    if x > y {
        (math::mul_div(x, ONE, y, false) - ONE) / math::pow(10, 28 - precision) == 0
    } else {
        (math::mul_div(y, ONE, x, false) - ONE) / math::pow(10, 28 - precision) == 0
    }
}

fn to_e18(x: u256) -> u256 {
    x * E18
}

fn to_e28(x: u256) -> u256 {
    x * ONE
}

////////////////////////////////
// INTERNAL HELPERS
////////////////////////////////

// Calculates the square root of x.
//
// # Arguments
// * `x` - The number to calculate the square root of.
//
// # Returns
// * `result` - The square root of x.
fn _sqrt(x: u256) -> u256 {
    if x == 0 {
        return 0;
    }

    let mut x_aux = x.clone();
    let mut result = 1;
    if x_aux >= Q128 {
        x_aux /= Q128;
        result *= Q64;
    }
    if x_aux >= Q64 {
        x_aux /= Q64;
        result *= Q32;
    }
    if (x_aux >= Q32) {
        x_aux /= Q32;
        result *= Q16;
    }
    if (x_aux >= Q16) {
        x_aux /= Q16;
        result *= 256;
    }
    if (x_aux >= 256) {
        x_aux /= 256;
        result *= 16;
    }
    if (x_aux >= 16) {
        x_aux /= 16;
        result *= 4;
    }
    if (x_aux >= 4) {
        result *= 2;
    }

    result = (result + x / result) / 2;
    result = (result + x / result) / 2;
    result = (result + x / result) / 2;
    result = (result + x / result) / 2;
    result = (result + x / result) / 2;
    result = (result + x / result) / 2;
    result = (result + x / result) / 2;

    // If x is not a perfect square, round the result toward zero.
    let rounded_result = x / result;

    min(result, rounded_result)
}
