// Core lib imports.
use starknet::contract_address_const;
use starknet::testing::set_contract_address;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::math::price_math;
use amm::libraries::constants::{OFFSET, MAX_LIMIT, MAX_WIDTH};
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::cairo_test::helpers::market_manager::{deploy_market_manager, create_market};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund};
use amm::tests::common::params::{owner, alice, default_token_params, default_market_params};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (_treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Fund LPs with initial token balances and approve market manager as spender.
    let initial_base_amount = 1000;
    fund(base_token, alice(), initial_base_amount);

    (market_manager, base_token, quote_token)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_sweep() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, _quote_token) = before();

    // Snapshot alice starting balance.
    let balance_start = base_token.balanceOf(alice());

    // Transfer tokens into contract.
    set_contract_address(alice());
    base_token.transfer(market_manager.contract_address, 1000);

    // Sweep tokens.
    set_contract_address(owner());
    let amount = market_manager.sweep(alice(), base_token.contract_address, 1000);

    // Snapshot alice ending balance.
    let balance_end = base_token.balanceOf(alice());

    // Check amounts recovered.
    assert(balance_start == balance_end, 'Sweep: user balance');
    assert(amount == 1000, 'Sweep: amount');
}

#[test]
#[should_panic(expected: ('OnlyOwner', 'ENTRYPOINT_FAILED',))]
fn test_sweep_not_owner() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, _quote_token) = before();

    set_contract_address(alice());
    market_manager.sweep(alice(), base_token.contract_address, 1000);
}
