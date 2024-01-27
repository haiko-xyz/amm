// Core lib imports.
use starknet::ContractAddress;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::constants::OFFSET;
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IFeeController::{IFeeControllerDispatcher, IFeeControllerDispatcherTrait};
use amm::types::i128::{i128, I128Trait};
use amm::tests::cairo_test::helpers::fee_controller::deploy_fee_controller;
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position, swap
};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::params::{
    owner, alice, treasury, default_token_params, default_market_params, modify_position_params,
    swap_params
};
use amm::tests::common::utils::{to_e18, to_e18_u128, to_e28};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before(
    swap_fee: u16
) -> (
    IMarketManagerDispatcher,
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    felt252,
    IFeeControllerDispatcher
) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (_treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Deploy fee controller.
    let fee_controller = deploy_fee_controller(swap_fee);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.width = 1;
    params.start_limit = OFFSET - 0;
    params.fee_controller = fee_controller.contract_address;
    let market_id = create_market(market_manager, params);

    // Fund LP with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(5000000000000000000000000000000000000000000);
    let initial_quote_amount = to_e28(100000000000000000000000000000000000000000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);

    (market_manager, base_token, quote_token, market_id, fee_controller)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(15000000000)]
fn test_fee_controller() {
    let fee_rate = 30;
    let (market_manager, _base_token, _quote_token, market_id, _fee_controller) = before(fee_rate);

    // Create position.
    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity = I128Trait::new(to_e18_u128(1000000), false);
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);

    // Execute swap.    
    let mut params = swap_params(
        alice(),
        market_id,
        true,
        true,
        to_e18(1),
        Option::None(()),
        Option::None(()),
        Option::None(()),
    );
    let (_amount_in, _amount_out, fees) = swap(market_manager, params);

    // Check fees.
    assert(fees == 3000000000000000, 'Fee controller fees');
}

#[test]
#[should_panic(expected: ('FeeRateOF', 'ENTRYPOINT_FAILED',))]
#[available_gas(15000000000)]
fn test_fee_controller_fee_rate_overflow() {
    let fee_rate = 10001;
    let (market_manager, _base_token, _quote_token, market_id, _fee_controller) = before(fee_rate);

    // Create position.
    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liquidity = I128Trait::new(to_e18_u128(1000000), false);
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);

    // Execute swap.    
    let mut params = swap_params(
        alice(),
        market_id,
        true,
        true,
        to_e18(1),
        Option::None(()),
        Option::None(()),
        Option::None(()),
    );
    swap(market_manager, params);
}
