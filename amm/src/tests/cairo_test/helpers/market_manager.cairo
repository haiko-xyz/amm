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
use amm::tests::cairo_test::helpers::{market_manager, token};
use amm::tests::common::params::{
    CreateMarketParams, ModifyPositionParams, SwapParams, SwapMultipleParams
};

// External imports.
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

fn deploy_market_manager(owner: ContractAddress,) -> IMarketManagerDispatcher {
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    owner.serialize(ref constructor_calldata);
    let (deployed_address, _) = deploy_syscall(
        MarketManager::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), false
    )
        .unwrap();

    IMarketManagerDispatcher { contract_address: deployed_address }
}

fn create_market(market_manager: IMarketManagerDispatcher, params: CreateMarketParams) -> felt252 {
    set_contract_address(params.owner);
    market_manager
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
        )
}

fn modify_position(
    market_manager: IMarketManagerDispatcher, params: ModifyPositionParams,
) -> (i256, i256, u256, u256) {
    set_contract_address(params.owner);
    market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        )
}

fn swap(market_manager: IMarketManagerDispatcher, params: SwapParams) -> (u256, u256, u256) {
    set_contract_address(params.owner);
    market_manager
        .swap(
            params.market_id,
            params.is_buy,
            params.amount,
            params.exact_input,
            params.threshold_sqrt_price,
            params.deadline,
        )
}

fn swap_multiple(market_manager: IMarketManagerDispatcher, params: SwapMultipleParams) -> u256 {
    set_contract_address(params.owner);
    market_manager
        .swap_multiple(
            params.in_token,
            params.out_token,
            params.amount,
            params.route,
            params.deadline,
        )
}
