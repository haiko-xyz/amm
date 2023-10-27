use amm::libraries::liquidity::{max_liquidity_per_limit};
use amm::libraries::constants::{MAX, MAX_NUM_LIMITS};

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_max_liquidity_per_limit_cases() {
    assert(
        max_liquidity_per_limit(
            1
        ) == 215679586192710245037529934681952285020293520212746125572932066370044,
        'max_liq(1)'
    );

    assert(
        max_liquidity_per_limit(
            10
        ) == 2156795219151999683915048371002508225752981573655282275105219731209647,
        'max_liq(10)'
    );

    assert(
        max_liquidity_per_limit(
            250
        ) == 53919784062735716724989536173912144504116344331104434414967879984570070,
        'max_liq(250)'
    );

    assert(max_liquidity_per_limit(MAX_NUM_LIMITS) == MAX, 'max_liq(MAX)');
}
