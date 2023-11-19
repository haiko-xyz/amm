// Core lib imports.
use starknet::testing::set_contract_address;
use integer::BoundedU256;
use debug::PrintTrait;

// Local imports.
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT};
use amm::types::i256::I256Trait;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position, swap, swap_multiple
};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::params::{
    owner, alice, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params
};
use amm::tests::common::utils::{to_e28, to_e18, approx_eq_pct};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (
    IMarketManagerDispatcher,
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    felt252,
    felt252,
) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let max = BoundedU256::max();
    let eth_params = token_params('Ethereum', 'ETH', max, treasury());
    let btc_params = token_params('Bitcoin', 'BTC', max, treasury());
    let usdc_params = token_params('USDC', 'USDC', max, treasury());
    let eth = deploy_token(eth_params);
    let btc = deploy_token(btc_params);
    let usdc = deploy_token(usdc_params);

    // Fund LP with initial token balances and approve market manager as spender.
    let initial_eth = max;
    let initial_btc = max;
    let initial_usdc = max;
    fund(eth, alice(), initial_eth);
    fund(btc, alice(), initial_btc);
    fund(usdc, alice(), initial_usdc);
    approve(eth, alice(), market_manager.contract_address, initial_eth);
    approve(btc, alice(), market_manager.contract_address, initial_btc);
    approve(usdc, alice(), market_manager.contract_address, initial_usdc);

    // Create ETH/USDC market.
    let mut eth_usdc_market_params = default_market_params();
    eth_usdc_market_params.base_token = eth.contract_address;
    eth_usdc_market_params.quote_token = usdc.contract_address;
    eth_usdc_market_params.start_limit = OFFSET + 737780;
    let eth_usdc_market_id = create_market(market_manager, eth_usdc_market_params);

    // Create BTC/USDC market.
    let mut btc_usdc_market_params = default_market_params();
    btc_usdc_market_params.base_token = btc.contract_address;
    btc_usdc_market_params.quote_token = usdc.contract_address;
    btc_usdc_market_params.start_limit = OFFSET + 1016590;
    let btc_usdc_market_id = create_market(market_manager, btc_usdc_market_params);

    (market_manager, eth, btc, usdc, eth_usdc_market_id, btc_usdc_market_id)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(15000000000)]
fn test_swap_multiple() {
    let (market_manager, eth, btc, usdc, eth_usdc_id, btc_usdc_id) = before();

    // Add liquidity positions.
    set_contract_address(alice());
    let mut eth_usdc_position_params = modify_position_params(
        alice(),
        eth_usdc_id,
        OFFSET + 730000,
        OFFSET + 740000,
        I256Trait::new(to_e28(20000000), false)
    );
    modify_position(market_manager, eth_usdc_position_params);

    let mut btc_usdc_position_params = modify_position_params(
        alice(),
        btc_usdc_id,
        OFFSET + 1010000,
        OFFSET + 1020000,
        I256Trait::new(to_e28(1000000), false)
    );
    modify_position(market_manager, btc_usdc_position_params);

    // Swap ETH for BTC.
    set_contract_address(alice());
    let mut swap_params = swap_multiple_params(
        alice(),
        eth.contract_address,
        btc.contract_address,
        to_e18(1),
        array![eth_usdc_id, btc_usdc_id].span(),
        Option::None(())
    );
    let amount_out = swap_multiple(market_manager, swap_params);

    // Check amount out
    assert(approx_eq_pct(amount_out, 61170203579856634, 14), 'Swap multiple: amount out');
}

#[test]
#[should_panic(expected: ('RouteMismatch', 'ENTRYPOINT_FAILED',))]
#[available_gas(15000000000)]
fn test_swap_multiple_invalid_path() {
    let (market_manager, eth, btc, usdc, eth_usdc_id, btc_usdc_id) = before();

    // Swap ETH for BTC - wrong path order.
    set_contract_address(alice());
    let mut swap_params = swap_multiple_params(
        alice(),
        eth.contract_address,
        btc.contract_address,
        to_e18(1),
        array![btc_usdc_id, eth_usdc_id].span(),
        Option::None(())
    );
    let amount_out = swap_multiple(market_manager, swap_params);
}
