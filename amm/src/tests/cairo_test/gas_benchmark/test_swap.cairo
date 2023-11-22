// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT, MIN_LIMIT};
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::i256::{i256, I256Trait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position, swap
};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::utils::approx_eq;
use amm::tests::common::params::{
    owner, alice, bob, treasury, default_token_params, default_market_params, modify_position_params, swap_params
};
use amm::tests::common::utils::to_e28;

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TYPES
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

fn _before(
    width: u32, is_concentrated: bool, allow_orders: bool, allow_positions: bool
) -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
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
    params.is_concentrated = is_concentrated;
    params.allow_orders = allow_orders;
    params.allow_positions = allow_positions;
    let market_id = create_market(market_manager, params);

    // Fund LPs with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000);
    let initial_quote_amount = to_e28(10000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    fund(base_token, bob(), initial_base_amount);
    fund(quote_token, bob(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);
    approve(base_token, bob(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, bob(), market_manager.contract_address, initial_quote_amount);

    // Create position
    let mut lower_limit = OFFSET - 229760;
    let mut upper_limit = OFFSET - 0;
    let mut liquidity = I256Trait::new(10000, false);
    let mut base_exp = I256Trait::new(21544, false);
    let mut quote_exp = I256Trait::new(0, false);

    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    
    let (base_amount, quote_amount, base_fees, quote_fees) = modify_position(
        market_manager, params
    );

    (market_manager, base_token, quote_token, market_id)
}

fn before(
    width: u32
) -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
    _before(width, true, true, true)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(1000000000)]
fn test_single_swap() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    let mut is_buy = false;
    let exact_input = true;
    let amount = 100000;
    let mut swap_params = swap_params(
        alice(), market_id, is_buy, exact_input, amount, Option::None(()), Option::None(()),
    );
    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    swap(market_manager, swap_params);

    'single swap gas used'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // should be around 19978204
}
