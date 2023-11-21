// Core lib imports.
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::libraries::math::math;
use amm::libraries::constants::OFFSET;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::core::{MarketState, OrderBatch};
use amm::types::i256::{i256, I256Trait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position
};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::params::{
    owner, alice, treasury, default_token_params, default_market_params, modify_position_params
};
use amm::tests::common::utils::{to_e18, to_e28};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
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
    params.start_limit = OFFSET - 0; // initial limit
    let market_id = create_market(market_manager, params);

    // Fund LPs with initial token balances and approve market manager as spender.
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
#[available_gas(100000000)]
fn test_collect_protocol_fees() {
    let (market_manager, base_token, quote_token, market_id) = before();

    // Set protocol share.
    set_contract_address(owner());
    market_manager.set_protocol_share(market_id, 30);

    // Create position.
    set_contract_address(alice());
    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity = I256Trait::new(to_e18(100000), false);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity);

    // Execute swap.
    market_manager.swap(market_id, true, to_e18(1), true, Option::None(()), Option::None(()));

    // Collect protocol fees.
    set_contract_address(owner());
    let quote_fees = market_manager.protocol_fees(quote_token.contract_address);
    let fee = market_manager
        .collect_protocol_fees(owner(), quote_token.contract_address, quote_fees);
    assert(fee == quote_fees && fee == 9000000000000, 'Fee amount');
    assert(quote_token.balance_of(owner()) == fee, 'Fee balance');
}

#[test]
#[available_gas(100000000)]
fn test_collect_protocol_fees_all_fees() {
    let (market_manager, base_token, quote_token, market_id) = before();

    // Set protocol share.
    set_contract_address(owner());
    market_manager.set_protocol_share(market_id, 10000);

    // Create position.
    set_contract_address(alice());
    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity = I256Trait::new(to_e18(100000), false);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity);

    // Execute swap.
    market_manager.swap(market_id, true, to_e18(1), true, Option::None(()), Option::None(()));

    // Collect protocol fees.
    set_contract_address(owner());
    let fee_exp = 3000000000000000;
    let fee = market_manager.collect_protocol_fees(owner(), quote_token.contract_address, fee_exp);
    assert(fee == fee_exp, 'Fee amount');
}

#[test]
#[available_gas(100000000)]
fn test_collect_protocol_fees_request_zero_amount() {
    let (market_manager, base_token, quote_token, market_id) = before();

    // Create position.
    set_contract_address(alice());
    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity = I256Trait::new(to_e18(100000), false);
    market_manager.modify_position(market_id, lower_limit, upper_limit, liquidity);

    // Execute swap.
    market_manager.swap(market_id, true, to_e18(1), true, Option::None(()), Option::None(()));

    // Collect protocol fees.
    set_contract_address(owner());
    let fee = market_manager.collect_protocol_fees(owner(), quote_token.contract_address, 0);
    assert(fee == 0, 'Fee amount');
}

#[test]
#[available_gas(100000000)]
fn test_collect_protocol_fees_non_available() {
    let (market_manager, base_token, quote_token, market_id) = before();

    // Collect protocol fees.
    set_contract_address(owner());
    let fee = market_manager.collect_protocol_fees(owner(), quote_token.contract_address, 10000);
    assert(fee == 0, 'Fee amount');
}

#[test]
#[should_panic(expected: ('OnlyOwner', 'ENTRYPOINT_FAILED',))]
#[available_gas(100000000)]
fn test_collect_protocol_fees_not_owner() {
    let (market_manager, base_token, quote_token, market_id) = before();

    // Collect protocol fees.
    set_contract_address(alice());
    market_manager.collect_protocol_fees(owner(), quote_token.contract_address, 10000);
}

#[test]
#[should_panic(expected: ('OnlyOwner', 'ENTRYPOINT_FAILED',))]
#[available_gas(100000000)]
fn test_set_protocol_share_not_owner() {
    let (market_manager, base_token, quote_token, market_id) = before();

    set_contract_address(alice());
    market_manager.set_protocol_share(market_id, 10000);
}
