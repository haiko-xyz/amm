use core::box::BoxTrait;
use core::traits::Into;
use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
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

fn before(number_of_markets: u256) -> (
    IMarketManagerDispatcher,
    Array<ERC20ABIDispatcher>,
    Array<felt252>
) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let max = BoundedU256::max();

    let mut tokens = ArrayTrait::<ERC20ABIDispatcher>::new();
    let mut market_ids = ArrayTrait::<felt252>::new();
    let mut index = 0;
    loop {
        if index == number_of_markets{
            break();
        }

        if index == 0 { 
            let token_params = token_params('Ethereum', 'ETH', max, treasury());
            let token = deploy_token(token_params);
            let initial_fund = max;
            fund(token, alice(), initial_fund);
            approve(token, alice(), market_manager.contract_address, initial_fund);
            tokens.append(token);
        }
        let token_params = token_params(index.try_into().unwrap(), index.try_into().unwrap(), max, treasury());
        let token = deploy_token(token_params);
        let initial_fund = max;
        fund(token, alice(), initial_fund);
        approve(token, alice(), market_manager.contract_address, initial_fund);
        tokens.append(token);

        // Create market.
        let mut market_params = default_market_params();
        market_params.base_token = *tokens.at(tokens.len() - 2).contract_address;
        market_params.quote_token = *tokens.at(tokens.len() - 1).contract_address;
        market_params.start_limit = OFFSET + 737780;
        let market_id = create_market(market_manager, market_params);

        market_ids.append(market_id);

        // Add liquidity positions.
        set_contract_address(alice());
        let mut position_params = modify_position_params(
            alice(),
            market_id,
            OFFSET + 730000,
            OFFSET + 740000,
            I256Trait::new(to_e28(20000000), false)
        );
        modify_position(market_manager, position_params);
        index += 1;
    };

    (market_manager, tokens, market_ids)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(15000000000)]
fn test_swap_multiple_two_markets() {
    let (market_manager, tokens, market_ids) = before(2);


    // Swap ETH for BTC.
    set_contract_address(alice());
    let mut swap_params = swap_multiple_params(
        alice(),
        *tokens.at(0).contract_address,
        *tokens.at(tokens.len() - 1).contract_address,
        to_e18(1),
        market_ids.span(),
        Option::None(())
    );

    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    swap_multiple(market_manager, swap_params);
    'swap_multiple with 2 gas used'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // should be around 59689424
}

#[test]
#[available_gas(15000000000)]
fn test_swap_multiple_ten_markets() {
    let (market_manager, tokens, market_ids) = before(10);


    // Swap ETH for BTC.
    set_contract_address(alice());
    let mut swap_params = swap_multiple_params(
        alice(),
        *tokens.at(0).contract_address,
        *tokens.at(tokens.len() - 1).contract_address,
        to_e18(1),
        market_ids.span(),
        Option::None(())
    );

    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    swap_multiple(market_manager, swap_params);
    'swap_multiple with 10 gas used'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // should be around 326121372
}