// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::set_contract_address;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::math::price_math;
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT, MIN_LIMIT};
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::core::LimitInfo;
use amm::types::i256::{i256, I256Trait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position
};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::params::{
    owner, alice, treasury, default_token_params, default_market_params, modify_position_params
};
use amm::tests::common::utils::to_e28;

// External imports.
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

#[derive(Drop, Copy)]
struct TestCase {
    lower_limit: u32,
    upper_limit: u32,
    liquidity: u256,
    base_exp: u256,
    quote_exp: u256,
}

////////////////////////////////
// SETUP
////////////////////////////////

fn before(width: u32) -> (IMarketManagerDispatcher, IERC20Dispatcher, IERC20Dispatcher, felt252) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.width = width;
    params.start_limit = OFFSET - 230260; // initial limit
    let market_id = create_market(market_manager, params);

    // Fund LP with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000);
    let initial_quote_amount = to_e28(10000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);

    (market_manager, base_token, quote_token, market_id)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(1000000000)]
fn test_modify_position_above_curr_price_cases() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create position
    let mut lower_limit = OFFSET - 229760;
    let mut upper_limit = OFFSET - 0;
    let mut liquidity = I256Trait::new(10000, false);
    let mut base_exp = I256Trait::new(21544, false);
    let mut quote_exp = I256Trait::new(0, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        1
    );

    // Create another position with different end limit
    lower_limit = OFFSET - 229760;
    upper_limit = OFFSET - 123000;
    liquidity = I256Trait::new(10000, false);
    base_exp = I256Trait::new(13048, false);
    quote_exp = I256Trait::new(0, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        2
    );

    // Create another position at different price range (max limit)
    lower_limit = OFFSET + MAX_LIMIT - 1;
    upper_limit = OFFSET + MAX_LIMIT;
    liquidity = I256Trait::new(100000000000000000000000000000, false);
    base_exp = I256Trait::new(304391, false);
    quote_exp = I256Trait::new(0, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        3
    );

    // Remove partial liquidity from first position
    lower_limit = OFFSET - 229760;
    upper_limit = OFFSET - 0;
    liquidity = I256Trait::new(5000, true);
    base_exp = I256Trait::new(10771, true);
    quote_exp = I256Trait::new(0, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        4
    );

    // Remove remaining liquidity from first position, check end limit is empty
    lower_limit = OFFSET - 229760;
    upper_limit = OFFSET - 0;
    liquidity = I256Trait::new(5000, true);
    base_exp = I256Trait::new(10771, true);
    quote_exp = I256Trait::new(0, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        5
    );
    assert(
        market_manager.limit_info(market_id, upper_limit).liquidity == 0,
        'Create pos: end limit liq=0 5'
    );
    assert(
        market_manager.limit_info(market_id, upper_limit).liquidity_delta.val == 0,
        'Create pos: end limit liq D=0 5'
    );
    assert(
        market_manager.limit_info(market_id, lower_limit).liquidity != 0,
        'Create pos: start liq !=0 5'
    );

    // Remove liquidity from second position, check start limit is empty
    lower_limit = OFFSET - 229760;
    upper_limit = OFFSET - 123000;
    liquidity = I256Trait::new(10000, true);
    base_exp = I256Trait::new(13047, true);
    quote_exp = I256Trait::new(0, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        6
    );
    assert(
        market_manager.limit_info(market_id, lower_limit).liquidity == 0,
        'Create pos: start liq=0 6'
    );
    assert(
        market_manager.limit_info(market_id, lower_limit).liquidity_delta.val == 0,
        'Create pos: start liq D=0 6'
    );
}

#[test]
#[available_gas(100000000)]
fn test_modify_position_wraps_curr_price_cases() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create position
    let mut lower_limit = OFFSET - 236000;
    let mut upper_limit = OFFSET - 224000;
    let mut liquidity = I256Trait::new(50000, false);
    let mut base_exp = I256Trait::new(4873, false);
    let mut quote_exp = I256Trait::new(448, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        1
    );

    // Create second position that spans entire range (min limit to max limit)
    lower_limit = OFFSET - MIN_LIMIT;
    upper_limit = OFFSET + MAX_LIMIT;
    liquidity = I256Trait::new(50000, false);
    base_exp = I256Trait::new(158115, false);
    quote_exp = I256Trait::new(15812, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        2
    );

    // Remove liquidity from second position, check start and end limits are empty
    lower_limit = OFFSET - MIN_LIMIT;
    upper_limit = OFFSET + MAX_LIMIT;
    liquidity = I256Trait::new(50000, true);
    base_exp = I256Trait::new(158114, true);
    quote_exp = I256Trait::new(15811, true);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        3
    );
    assert(
        market_manager.limit_info(market_id, lower_limit).liquidity == 0,
        'Create pos: start liq=0 3'
    );
    assert(
        market_manager.limit_info(market_id, upper_limit).liquidity == 0, 'Create pos: end liq=0 3'
    );
}

#[test]
#[available_gas(100000000)]
fn test_modify_position_below_curr_price_cases() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create position
    let mut lower_limit = OFFSET - 460000;
    let mut upper_limit = OFFSET - 235000;
    let mut liquidity = I256Trait::new(20000, false);
    let mut base_exp = I256Trait::new(0, false);
    let mut quote_exp = I256Trait::new(4172, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        1
    );

    // Create second position at exact same price range
    liquidity = I256Trait::new(15000, false);
    base_exp = I256Trait::new(0, false);
    quote_exp = I256Trait::new(3129, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        2
    );

    // Create third position at different price range (min limit)
    lower_limit = OFFSET - MIN_LIMIT;
    upper_limit = OFFSET - MIN_LIMIT + 1;
    liquidity = I256Trait::new(100000000000000000000000000000, false);
    base_exp = I256Trait::new(0, false);
    quote_exp = I256Trait::new(304390, false);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        3
    );

    // Remove all liquidity from first and second positions, check start and end limits are empty
    lower_limit = OFFSET - 460000;
    upper_limit = OFFSET - 235000;
    liquidity = I256Trait::new(35000, true);
    base_exp = I256Trait::new(0, false);
    quote_exp = I256Trait::new(7299, true);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        4
    );
    assert(
        market_manager.limit_info(market_id, lower_limit).liquidity == 0,
        'Create pos: start liq=0 4'
    );
    assert(
        market_manager.limit_info(market_id, upper_limit).liquidity == 0, 'Create pos: end liq=0 4'
    );
    assert(
        market_manager.limit_info(market_id, lower_limit).liquidity_delta.val == 0,
        'Create pos: start liqD=0 4'
    );
    assert(
        market_manager.limit_info(market_id, upper_limit).liquidity_delta.val == 0,
        'Create pos: end liqD=0 4'
    );

    // Remove liquidity from third position
    lower_limit = OFFSET - MIN_LIMIT;
    upper_limit = OFFSET - MIN_LIMIT + 1;
    liquidity = I256Trait::new(40000000000000000000000000000, true);
    base_exp = I256Trait::new(0, false);
    quote_exp = I256Trait::new(121756, true);
    _modify_position_and_run_checks(
        market_manager,
        market_id,
        base_token,
        quote_token,
        lower_limit,
        upper_limit,
        liquidity,
        base_exp,
        quote_exp,
        5
    );
}

#[test]
#[available_gas(100000000)]
fn test_modify_position_accumulates_protocol_fees() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create position
    let lower_limit = OFFSET - MIN_LIMIT;
    let upper_limit = OFFSET + MAX_LIMIT;
    let liquidity = I256Trait::new(to_e28(1), false);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity);

    // Execute some swaps
    let mut is_buy = true;
    let mut amount = to_e28(1);
    let exact_input = true;
    market_manager.swap(market_id, is_buy, amount, exact_input, Option::None(()), Option::None(()));
    is_buy = false;
    market_manager.swap(market_id, is_buy, amount, exact_input, Option::None(()), Option::None(()));

    // Check protocol fees
    let base_protocol_fees = market_manager.protocol_fees(market_manager.base_token(market_id));
    let quote_protocol_fees = market_manager.protocol_fees(market_manager.quote_token(market_id));
    assert(base_protocol_fees == 60000000000000000000000, 'Base protocol fees');
    assert(quote_protocol_fees == 60000000000000000000000, 'Quote protocol fees');
}

#[test]
#[available_gas(100000000)]
fn test_modify_position_zero_protocol_fees() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);
    set_contract_address(owner());
    market_manager.set_protocol_share(market_id, 0);

    // Create position
    set_contract_address(alice());
    let lower_limit = OFFSET - MIN_LIMIT;
    let upper_limit = OFFSET + MAX_LIMIT;
    let liquidity = I256Trait::new(to_e28(1), false);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity);

    // Execute some swaps
    let mut is_buy = true;
    let mut amount = to_e28(1);
    let exact_input = true;
    market_manager.swap(market_id, is_buy, amount, exact_input, Option::None(()), Option::None(()));
    is_buy = false;
    market_manager.swap(market_id, is_buy, amount, exact_input, Option::None(()), Option::None(()));

    // Check protocol fees
    let base_protocol_fees = market_manager.protocol_fees(market_manager.base_token(market_id));
    let quote_protocol_fees = market_manager.protocol_fees(market_manager.quote_token(market_id));
    assert(base_protocol_fees == 0, 'Base protocol fees');
    assert(quote_protocol_fees == 0, 'Quote protocol fees');
}

#[test]
#[available_gas(1000000000)]
fn test_modify_position_collect_position_fees() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);
    set_contract_address(owner());
    market_manager.set_protocol_share(market_id, 0);

    // Create position
    set_contract_address(alice());
    let lower_limit = OFFSET - MIN_LIMIT;
    let upper_limit = OFFSET + MAX_LIMIT;
    let liquidity = I256Trait::new(to_e28(1), false);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity);

    // Execute some swaps
    let mut is_buy = true;
    let exact_input = true;
    let mut amount = to_e28(1);
    market_manager.swap(market_id, is_buy, amount, exact_input, Option::None(()), Option::None(()));
    is_buy = false;
    market_manager.swap(market_id, is_buy, amount, exact_input, Option::None(()), Option::None(()));

    // Poke position to collect fees.
    let (base_amount, quote_amount, _, _) = market_manager
        .modify_position(market_id, lower_limit, upper_limit, I256Trait::new(0, false));

    // Run checks
    let base_fees_exp = 30000000000000000000000000;
    let quote_fees_exp = 30000000000000000000000000;
    let position = market_manager.position(market_id, alice().into(), lower_limit, upper_limit);

    assert(base_amount.val == base_fees_exp, 'Base fees');
    assert(quote_amount.val == quote_fees_exp, 'Quote fees');
    assert(position.liquidity == liquidity.val, 'Liquidity');
    assert(position.base_fee_factor_last == base_fees_exp, 'Base fee factor');
    assert(position.quote_fee_factor_last == quote_fees_exp, 'Quote fee factor');
}

////////////////////////////////
// TESTS - Failure cases
////////////////////////////////

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('LimitsUnordered', 'ENTRYPOINT_FAILED',))]
fn test_modify_position_limits_unordered() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create position
    let lower_limit = OFFSET + 1235;
    let upper_limit = OFFSET - 1235;
    let liquidity = I256Trait::new(20000, false);
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('NotMultipleOfWidth', 'ENTRYPOINT_FAILED',))]
fn test_modify_position_lower_limit_not_multiple_of_width() {
    let width = 25;
    let (market_manager, base_token, quote_token, market_id) = before(width);

    // Create position
    let lower_limit = OFFSET - 46;
    let upper_limit = OFFSET;
    let liquidity = I256Trait::new(10000000000000000000000000000, false);
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('NotMultipleOfWidth', 'ENTRYPOINT_FAILED',))]
fn test_modify_position_upper_limit_not_multiple_of_width() {
    let width = 25;
    let (market_manager, base_token, quote_token, market_id) = before(width);

    // Create position
    let lower_limit = OFFSET;
    let upper_limit = OFFSET + 49;
    let liquidity = I256Trait::new(10000000000000000000000000000, false);
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('UpperLimitOverflow', 'ENTRYPOINT_FAILED',))]
fn test_modify_position_upper_limit_overflow() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create position
    let lower_limit = OFFSET + 1235;
    let upper_limit = OFFSET + MAX_LIMIT + 1;
    let liquidity = I256Trait::new(10000000000000000000000000000, false);
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('LiqDeltaOverflow', 'ENTRYPOINT_FAILED',))]
fn test_modify_position_delta_overflow() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create position
    let lower_limit = OFFSET + 1235;
    let upper_limit = OFFSET + 2500;
    let liquidity = I256Trait::new(MAX + 1, false);
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('LimitLiqOverflow', 'ENTRYPOINT_FAILED',))]
fn test_modify_position_liq_at_limit_overflow_width_1() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create position
    let lower_limit = OFFSET + 1235;
    let upper_limit = OFFSET + 2500;
    let liquidity = I256Trait::new(
        215679599048216897853083520487672751001849517548985635466894530753707, false
    );
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('LimitLiqOverflow', 'ENTRYPOINT_FAILED',))]
fn test_modify_position_liq_at_limit_overflow_width_25() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 25);

    // Create position
    let lower_limit = 8388575;
    let upper_limit = 8388600;
    let liquidity = I256Trait::new(
        5391986440943200102664956187771026056941394884607090101542536769168491, false
    );
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);
}

////////////////////////////////
// HELPERS
////////////////////////////////

fn _modify_position_and_run_checks(
    market_manager: IMarketManagerDispatcher,
    market_id: felt252,
    base_token: IERC20Dispatcher,
    quote_token: IERC20Dispatcher,
    lower_limit: u32,
    upper_limit: u32,
    liquidity: i256,
    base_exp: i256,
    quote_exp: i256,
    n: felt252,
) {
    // Snapshot state before
    let (base_bal_bef, quote_bal_bef, lower_limit_bef, upper_limit_bef) = _snapshot_state(
        market_manager, market_id, base_token, quote_token, lower_limit, upper_limit
    );

    // Create position
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    let (base_amount, quote_amount, base_fees, quote_fees) = modify_position(
        market_manager, params
    );

    // Snapshot state after
    let (base_bal_aft, quote_bal_aft, lower_limit_aft, upper_limit_aft) = _snapshot_state(
        market_manager, market_id, base_token, quote_token, lower_limit, upper_limit
    );

    // Run checks
    assert(base_bal_aft == _add_delta(base_bal_bef, base_exp), 'Create pos: base 0' + n);
    assert(quote_bal_aft == _add_delta(quote_bal_bef, quote_exp), 'Create pos: quote 0' + n);
    assert(
        lower_limit_aft.liquidity == _add_delta(lower_limit_bef.liquidity, liquidity),
        'Create pos: start limit liq 0' + n
    );
    assert(
        upper_limit_aft.liquidity == _add_delta(upper_limit_bef.liquidity, liquidity),
        'Create pos: end limit liq 0' + n
    );
    assert(
        lower_limit_aft.liquidity_delta == lower_limit_bef.liquidity_delta + liquidity,
        'Create pos: start limit liq D 0' + n
    );
    assert(
        upper_limit_aft.liquidity_delta == upper_limit_bef.liquidity_delta - liquidity,
        'Create pos: end limit liq D 0' + n
    );
}

fn _snapshot_state(
    market_manager: IMarketManagerDispatcher,
    market_id: felt252,
    base_token: IERC20Dispatcher,
    quote_token: IERC20Dispatcher,
    lower_limit: u32,
    upper_limit: u32
) -> (u256, u256, LimitInfo, LimitInfo) {
    let base_balance = base_token.balance_of(market_manager.contract_address);
    let quote_balance = quote_token.balance_of(market_manager.contract_address);
    let lower_limit_info = market_manager.limit_info(market_id, lower_limit);
    let upper_limit_info = market_manager.limit_info(market_id, upper_limit);

    (base_balance, quote_balance, lower_limit_info, upper_limit_info)
}

fn _add_delta(liquidity: u256, delta: i256) -> u256 {
    if delta.sign {
        liquidity - delta.val
    } else {
        liquidity + delta.val
    }
}
