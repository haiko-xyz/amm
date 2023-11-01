use amm::libraries::liquidity::{max_liquidity_per_limit};
use amm::libraries::constants::{MAX_UNSCALED, MAX_NUM_LIMITS};

////////////////////////////////
// TESTS
////////////////////////////////
use debug::PrintTrait;

#[test]
#[available_gas(2000000000)]
fn test_max_liquidity_per_limit_cases() {
    assert(
        max_liquidity_per_limit(
            1
        ) == 21567958619271024503752993468195228502029,
        'max_liq(1)'
    );

    assert(
        max_liquidity_per_limit(
            10
        ) == 215679521915199968391504837100250822575298,
        'max_liq(10)'
    );

    assert(
        max_liquidity_per_limit(
            250
        ) == 5391978406273571672498953617391214450411634,
        'max_liq(250)'
    );

    assert(max_liquidity_per_limit(MAX_NUM_LIMITS) == MAX_UNSCALED, 'max_liq(MAX)');
}
