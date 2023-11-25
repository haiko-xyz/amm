// Core lib imports.
use cmp::{min, max};
use starknet::ContractAddress;
use dict::{Felt252Dict, Felt252DictTrait};

// Local imports.
use amm::libraries::constants::{OFFSET, MAX_LIMIT};
use amm::libraries::math::fee_math;
use amm::libraries::id;
use amm::libraries::liquidity as liquidity_helpers;
use amm::types::core::{MarketState, LimitInfo};
use amm::types::i256::{i256, I256Trait, I256Zeroable};
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap, swap_multiple},
    token::{declare_token, deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, approx_eq};

// External imports.
use snforge_std::{start_prank, PrintTrait, declare, ContractClass, ContractClassTrait};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let manager_class = declare('MarketManager');
    let market_manager = deploy_market_manager(manager_class, owner);

    // Deploy tokens.
    let erc20_class = declare_token();
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(erc20_class, base_token_params);
    let quote_token = deploy_token(erc20_class, quote_token_params);

    (market_manager, base_token, quote_token)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_create_market() {
    let (market_manager, base_token, quote_token) = before();

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.width = 1;
    params.start_limit = OFFSET - 230260; // initial limit

    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    let market_id = create_market(market_manager, params);
    
    'create_market gas used'.print();
    (gas_before - testing::get_available_gas()).print(); 
}
