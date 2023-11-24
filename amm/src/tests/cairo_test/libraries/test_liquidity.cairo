use integer::BoundedU256;

use amm::libraries::liquidity::max_liquidity_per_limit;
use amm::libraries::constants::{MAX_NUM_LIMITS, MAX_SCALED};

////////////////////////////////
// TESTS
////////////////////////////////
use debug::PrintTrait;

#[test]
#[available_gas(2000000000)]
fn test_max_liquidity_per_limit_cases() {
    assert(
        max_liquidity_per_limit(1) == 7322472098704826441038024692625691444047146577616491,
        'max_liq(1)'
    );

    assert(
        max_liquidity_per_limit(10) == 73224679311739764870476413471155162093881960244529315,
        'max_liq(10)'
    );

    assert(
        max_liquidity_per_limit(250) == 1830589199691975138703812960582538777836500216043895469,
        'max_liq(250)'
    );

    assert(max_liquidity_per_limit(MAX_NUM_LIMITS) == MAX_SCALED, 'max_liq(MAX)');
}
