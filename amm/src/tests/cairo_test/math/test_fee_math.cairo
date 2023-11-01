use integer::BoundedU256;

use amm::libraries::math::fee_math::calc_fee;
use amm::libraries::math::fee_math::gross_to_net;
use amm::libraries::math::fee_math::get_fee_inside;
use amm::types::core::LimitInfo;
use amm::types::i256::I256Zeroable;


////////////////////////////////
// TESTS - calc_fee
////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_calc_fee_cases() {
    let mut fee = calc_fee(0, 0);
    assert(fee == 0, 'calc_fee(0,0)');

    fee = calc_fee(1, 0);
    assert(fee == 0, 'calc_fee(1,0)');

    fee = calc_fee(0, 1);
    assert(fee == 0, 'calc_fee(0,1)');

    fee = calc_fee(1, 1000);
    assert(fee == 0, 'calc_fee(1,1000)');

    fee = calc_fee(3749, 241);
    assert(fee == 90, 'calc_fee(3749,241)');

    fee = calc_fee(100000, 100);
    assert(fee == 1000, 'calc_fee(10000,100)');

    fee = calc_fee(BoundedU256::max(), 3333);
    assert(
        fee == 38593503342797487934676209303395679687494885889057999994351212749837446108990,
        'calc_fee(MAX,3333)'
    );

    fee = calc_fee(BoundedU256::max(), 10000);
    assert(fee == BoundedU256::max(), 'calc_fee(MAX,10000)');
}

#[test]
#[should_panic(expected: ('FeeRateOverflow',))]
#[available_gas(2000000000)]
fn test_calc_FeeOverflow() {
    calc_fee(50000, 10001);
}

////////////////////////////////
// TESTS - gross_to_net
////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_gross_to_net_cases() {
    let mut net = gross_to_net(0, 0);
    assert(net == 0, 'gross_to_net(0,0)');

    net = gross_to_net(5500, 0);
    assert(net == 5500, 'gross_to_net(5500,0)');

    net = gross_to_net(0, 5000);
    assert(net == 0, 'gross_to_net(0,5000)');

    net = gross_to_net(5500, 1000);
    assert(net == 4950, 'gross_to_net(5500,1000)');

    net = gross_to_net(37490, 241);
    assert(net == 36587, 'gross_to_net(37490,241)');

    net = gross_to_net(100000, 100);
    assert(net == 99000, 'gross_to_net(10000,100)');

    net = gross_to_net(BoundedU256::max(), 3333);
    // TODO: check why result below is 1 less than it should be
    assert(
        net == 77198585894518707488894775705292228165775098776582564045106371258075683530945,
        'gross_to_net(MAX,3333)'
    );

    net = gross_to_net(BoundedU256::max(), 10000);
    assert(net == 0, 'gross_to_net(MAX,10000)');
}

#[test]
#[should_panic(expected: ('FeeRateOverflow',))]
#[available_gas(2000000000)]
fn test_gross_to_net_overflow() {
    gross_to_net(50000, 10001);
}

////////////////////////////////
// TESTS - get_fee_inside
////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_get_fee_inside_cases() {
    let mut lower_limit_info = empty_limit_info();
    let mut upper_limit_info = empty_limit_info();

    // Position is below current price
    let (mut base_factor, mut quote_factor) = get_fee_inside(
        lower_limit_info, upper_limit_info, 0, 10, 15, 100, 200
    );
    assert(base_factor == 0 && quote_factor == 0, 'gfi(0,10,15,100,200)');

    // Position is above current price
    let (base_factor, quote_factor) = get_fee_inside(
        lower_limit_info, upper_limit_info, 5, 10, 0, 100, 200
    );
    assert(base_factor == 0 && quote_factor == 0, 'gfi(5,10,0,100,200)');

    // Position wraps current price, no fees accrued outside
    let (base_factor, quote_factor) = get_fee_inside(
        lower_limit_info, upper_limit_info, 0, 10, 5, 100, 200
    );
    assert(base_factor == 100 && quote_factor == 200, 'gfi(0,10,5,100,200)');

    // Position wraps current price, fees accrued above
    upper_limit_info.base_fee_factor = 25;
    upper_limit_info.quote_fee_factor = 50;
    let (base_factor, quote_factor) = get_fee_inside(
        lower_limit_info, upper_limit_info, 0, 10, 5, 100, 200
    );
    assert(base_factor == 75 && quote_factor == 150, 'gfi(0,10,5,100-25,200-50)');

    // Position wraps current price, fees accrued below
    upper_limit_info.base_fee_factor = 0;
    upper_limit_info.quote_fee_factor = 0;
    lower_limit_info.base_fee_factor = 12;
    lower_limit_info.quote_fee_factor = 24;
    let (base_factor, quote_factor) = get_fee_inside(
        lower_limit_info, upper_limit_info, 0, 10, 5, 100, 200
    );
    assert(base_factor == 88 && quote_factor == 176, 'gfi(0,10,5,100-12,200-24)');

    // Position wraps current price, fees accrued above and below
    upper_limit_info.base_fee_factor = 25;
    upper_limit_info.quote_fee_factor = 50;
    let (base_factor, quote_factor) = get_fee_inside(
        lower_limit_info, upper_limit_info, 0, 10, 5, 100, 200
    );
    assert(base_factor == 63 && quote_factor == 126, 'gfi(0,10,5,100-12-25,200-24-50)');
}

////////////////////////////////
// INTERNAL HELPERS
////////////////////////////////

fn empty_limit_info() -> LimitInfo {
    LimitInfo {
        liquidity: 0,
        liquidity_delta: I256Zeroable::zero(),
        quote_fee_factor: 0,
        base_fee_factor: 0,
        nonce: 0,
    }
}
