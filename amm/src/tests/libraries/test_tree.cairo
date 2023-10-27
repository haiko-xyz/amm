use core::result::ResultTrait;
use traits::TryInto;
use option::OptionTrait;
use array::ArrayTrait;
use starknet::deploy_syscall;

use amm::libraries::constants::{OFFSET, MAX_LIMIT, MIN_LIMIT};
use amm::libraries::tree::_get_segment_and_position;
use amm::tests::helpers::actions::params;
use amm::tests::helpers::actions::token::deploy_token;
use amm::tests::helpers::actions::market_manager::{deploy_market_manager, create_market};
use amm::interfaces::IERC20::{IERC20Dispatcher, IERC20DispatcherTrait};
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::helpers::contracts::tree_contract::{
    TestTreeContract, ITestTreeContractDispatcher, ITestTreeContractDispatcherTrait
};


////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (
    IMarketManagerDispatcher,
    IERC20Dispatcher,
    IERC20Dispatcher,
    felt252,
    ITestTreeContractDispatcher
) {
    // Deploy and initialise market.
    let market_manager = deploy_market_manager(params::owner());

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = params::default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Create market.
    let mut default_market_params = params::default_market_params();
    default_market_params.base_token = base_token.contract_address;
    default_market_params.quote_token = quote_token.contract_address;
    let market_id = create_market(market_manager, default_market_params);

    // Deploy test tree contract.
    let empty_array = ArrayTrait::<felt252>::new();
    let (deployed_address, _) = deploy_syscall(
        TestTreeContract::TEST_CLASS_HASH.try_into().unwrap(), 0, empty_array.span(), false
    )
        .unwrap();
    let tree_contract = ITestTreeContractDispatcher { contract_address: deployed_address };

    (market_manager, base_token, quote_token, market_id, tree_contract)
}

// Setup test cases.
fn setup_test_cases(tree_contract: ITestTreeContractDispatcher, market_id: felt252) {
    tree_contract.flip(market_id, 1, OFFSET - 250);
    tree_contract.flip(market_id, 1, OFFSET - 100);
    tree_contract.flip(market_id, 1, OFFSET - 24);
    tree_contract.flip(market_id, 1, OFFSET - 1);
    tree_contract.flip(market_id, 1, OFFSET + 10);
    tree_contract.flip(market_id, 1, OFFSET + 125);
    tree_contract.flip(market_id, 1, OFFSET + 126);
    tree_contract.flip(market_id, 1, OFFSET + 149);
    tree_contract.flip(market_id, 1, OFFSET + 210);
    tree_contract.flip(market_id, 1, OFFSET + 375);
    tree_contract.flip(market_id, 1, OFFSET + 660);
    tree_contract.flip(market_id, 1, OFFSET + MAX_LIMIT);
}

////////////////////////////////////
// TESTS - get and flip bit
////////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_get_and_flip_bit() {
    let (market_manager, base_token, quote_token, market_id, tree_contract) = before();

    let mut limit = 1;
    assert(tree_contract.get(market_id, 1, limit) == false, 'get(1, init)');

    tree_contract.flip(market_id, 1, limit);
    assert(tree_contract.get(market_id, 1, limit) == true, 'get(1, T)');

    tree_contract.flip(market_id, 1, limit);
    assert(tree_contract.get(market_id, 1, limit) == false, 'get(1, F)');

    tree_contract.flip(market_id, 1, 2);
    assert(tree_contract.get(market_id, 1, 2) == true, 'get(2, T)');
    assert(tree_contract.get(market_id, 1, 1) == false, 'get(1, F)');

    tree_contract.flip(market_id, 1, 257);
    assert(tree_contract.get(market_id, 1, 257) == true, 'get(257, T)');
    assert(tree_contract.get(market_id, 1, 1) == false, 'get(1, F)');

    limit = OFFSET + 200;
    tree_contract.flip(market_id, 1, limit);

    tree_contract.flip(market_id, 1, OFFSET + 220);
    assert(tree_contract.get(market_id, 1, limit) == true, 'get(OFFSET + 200, T)');

    tree_contract.flip(market_id, 1, OFFSET + 226);
    assert(tree_contract.get(market_id, 1, limit) == true, 'get(OFFSET + 200, T)');
}

////////////////////////////////
// TESTS - next_limit
////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_next_limit_buy_cases_width_1() {
    let (market_manager, base_token, quote_token, market_id, tree_contract) = before();

    // Setup some initial test cases.
    setup_test_cases(tree_contract, market_id);

    // Returns direct next limit if initialised.
    let mut start_limit = OFFSET + 125;
    let next_limit = tree_contract.next_limit(market_id, true, 1, start_limit);
    assert(next_limit.unwrap() == OFFSET + 126, 'next_limit(125,1,buy)');

    // Returns next limit if initialised.
    start_limit = OFFSET + 126;
    let next_limit = tree_contract.next_limit(market_id, true, 1, start_limit);
    assert(next_limit.unwrap() == OFFSET + 149, 'next_limit(126,1,buy)');

    // Returns next word's initialised limit if on the boundary.
    start_limit = OFFSET + 256;
    let next_limit = tree_contract.next_limit(market_id, true, 1, start_limit);
    assert(next_limit.unwrap() == OFFSET + 375, 'next_limit(256,1,buy)');

    // Returns next word's initialised limit.
    start_limit = OFFSET + 510;
    let next_limit = tree_contract.next_limit(market_id, true, 1, start_limit);
    assert(next_limit.unwrap() == OFFSET + 660, 'next_limit(640,1,buy)');

    // Returns max.
    start_limit = OFFSET + 660;
    let next_limit = tree_contract.next_limit(market_id, true, 1, start_limit);
    assert(next_limit.unwrap() == OFFSET + MAX_LIMIT, 'next_limit(660,1,buy)');
}

#[test]
#[available_gas(2000000000)]
fn test_next_limit_sell_cases_width_1() {
    let (market_manager, base_token, quote_token, market_id, tree_contract) = before();

    // Setup some initial test cases.
    setup_test_cases(tree_contract, market_id);

    // Returns self if initialised.
    let mut start_limit = OFFSET + 126;
    let next_limit = tree_contract.next_limit(market_id, false, 1, start_limit);
    assert(next_limit.unwrap() == OFFSET + 126, 'next_limit(126,1,sell)');

    // Returns next word's initialised limit if on the boundary.
    start_limit = OFFSET + 257;
    let next_limit = tree_contract.next_limit(market_id, false, 1, start_limit);
    assert(next_limit.unwrap() == OFFSET + 210, 'next_limit(120,1,sell)');

    // Returns next word's initialised limit.
    start_limit = OFFSET + 550;
    let next_limit = tree_contract.next_limit(market_id, false, 1, start_limit);
    assert(next_limit.unwrap() == OFFSET + 375, 'next_limit(550,1,sell)');
}

////////////////////////////////////
// TESTS - _get_segment_and_position
////////////////////////////////////

#[test]
#[available_gas(2000000000)]
fn test_get_segment_and_position_cases() {
    let (mut segment, mut position) = _get_segment_and_position(OFFSET - MIN_LIMIT);
    assert(segment == 0 && position == 0, 'seg_pos(MIN)');

    let (segment, position) = _get_segment_and_position(OFFSET - 248100);
    assert(segment == 31798 && position == 220, 'seg_pos(-248100)');

    let (segment, position) = _get_segment_and_position(OFFSET - 1050);
    assert(segment == 32763 && position == 230, 'seg_pos(-1050)');

    let (segment, position) = _get_segment_and_position(OFFSET - 1);
    assert(segment == 32767 && position == 255, 'seg_pos(-1)');

    let (segment, position) = _get_segment_and_position(OFFSET + 9794);
    assert(segment == 32806 && position == 66, 'seg_pos(9794)');

    let (segment, position) = _get_segment_and_position(OFFSET + 254839);
    assert(segment == 33763 && position == 119, 'seg_pos(254839)');

    let (segment, position) = _get_segment_and_position(OFFSET + 1857300);
    assert(segment == 40023 && position == 20, 'seg_pos(1857300)');

    let (segment, position) = _get_segment_and_position(OFFSET + MAX_LIMIT);
    assert(segment == 65535 && position == 255, 'seg_pos(MAX)');
}

#[test]
#[available_gas(2000000000)]
#[should_panic(expected: ('SEG_POS_LIMIT_OVERFLOW',))]
fn test__get_segment_and_position_overflow() {
    _get_segment_and_position(OFFSET + MAX_LIMIT + 1);
}
