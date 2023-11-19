// Core lib imports.
use core::serde::Serde;
use core::traits::Into;
use core::result::ResultTrait;
use array::ArrayTrait;
use option::OptionTrait;
use traits::TryInto;
use starknet::deploy_syscall;
use starknet::ContractAddress;
use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::math::price_math;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::i256::i256;
use amm::tests::common::params::{
    CreateMarketParams, ModifyPositionParams, SwapParams, SwapMultipleParams
};

// External imports.
use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

fn deploy_market_manager(owner: ContractAddress,) -> IMarketManagerDispatcher {
    let contract = declare('MarketManager');
    let contract_address = contract.deploy(@array![owner.into()]).unwrap();
    IMarketManagerDispatcher { contract_address }
}

fn create_market(market_manager: IMarketManagerDispatcher, params: CreateMarketParams) -> felt252 {
    start_prank(market_manager.contract_address, params.owner);
    let base_whitelisted = market_manager.is_whitelisted(params.base_token);
    let quote_whitelisted = market_manager.is_whitelisted(params.quote_token);
    if !base_whitelisted {
        market_manager.whitelist(params.base_token);
    }
    if !quote_whitelisted {
        market_manager.whitelist(params.quote_token);
    }
    let market_id = market_manager
        .create_market(
            params.base_token,
            params.quote_token,
            params.width,
            params.strategy,
            params.swap_fee_rate,
            params.fee_controller,
            params.protocol_share,
            params.start_limit,
            params.allow_positions,
            params.allow_orders,
            params.is_concentrated
        );
    stop_prank(market_manager.contract_address);
    market_id
}

fn modify_position(
    market_manager: IMarketManagerDispatcher, params: ModifyPositionParams,
) -> (i256, i256, u256, u256) {
    start_prank(market_manager.contract_address, params.owner);
    let (base_amount, quote_amount, base_fees, quote_fees) = market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        );
    stop_prank(market_manager.contract_address);

    (base_amount, quote_amount, base_fees, quote_fees)
}

fn swap(market_manager: IMarketManagerDispatcher, params: SwapParams) -> (u256, u256, u256) {
    start_prank(market_manager.contract_address, params.owner);
    let (amount_in, amount_out, fees) = market_manager
        .swap(
            params.market_id,
            params.is_buy,
            params.amount,
            params.exact_input,
            params.threshold_sqrt_price,
            params.deadline,
        );
    stop_prank(market_manager.contract_address);
    (amount_in, amount_out, fees)
}

fn swap_multiple(market_manager: IMarketManagerDispatcher, params: SwapMultipleParams) -> u256 {
    start_prank(market_manager.contract_address, params.owner);
    let amount_out = market_manager
        .swap_multiple(
            params.in_token, params.out_token, params.amount, params.route, params.deadline,
        );
    stop_prank(market_manager.contract_address);
    amount_out
}
