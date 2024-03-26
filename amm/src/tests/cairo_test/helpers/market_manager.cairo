// Core lib imports.
use starknet::syscalls::deploy_syscall;
use starknet::ContractAddress;
use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::id;
use amm::libraries::math::price_math;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::core::MarketInfo;
use amm::types::i256::i256;
use amm::tests::cairo_test::helpers::{market_manager, token};
use amm::tests::common::params::{
    CreateMarketParams, ModifyPositionParams, SwapParams, SwapMultipleParams, TransferOwnerParams
};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

pub fn deploy_market_manager(owner: ContractAddress,) -> IMarketManagerDispatcher {
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    owner.serialize(ref constructor_calldata);
    'Haiko Liquidity Positions'.serialize(ref constructor_calldata);
    'HAIKO-LP'.serialize(ref constructor_calldata);

    let (deployed_address, _) = deploy_syscall(
        MarketManager::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), false
    )
        .unwrap();

    IMarketManagerDispatcher { contract_address: deployed_address }
}

pub fn deploy_market_manager_with_salt(
    owner: ContractAddress, salt: felt252
) -> IMarketManagerDispatcher {
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    owner.serialize(ref constructor_calldata);
    'Haiko Liquidity Positions'.serialize(ref constructor_calldata);
    'HAIKO-LP'.serialize(ref constructor_calldata);

    let (deployed_address, _) = deploy_syscall(
        MarketManager::TEST_CLASS_HASH.try_into().unwrap(), salt, constructor_calldata.span(), false
    )
        .unwrap();

    IMarketManagerDispatcher { contract_address: deployed_address }
}

pub fn create_market(market_manager: IMarketManagerDispatcher, params: CreateMarketParams) -> felt252 {
    set_contract_address(params.owner);
    let market_id = id::market_id(
        MarketInfo {
            base_token: params.base_token,
            quote_token: params.quote_token,
            width: params.width,
            strategy: params.strategy,
            swap_fee_rate: params.swap_fee_rate,
            fee_controller: params.fee_controller,
            controller: params.controller,
        }
    );
    let whitelisted = market_manager.is_market_whitelisted(market_id);
    if !whitelisted {
        market_manager.whitelist_markets(array![market_id])
    }
    create_market_without_whitelisting(market_manager, params)
}

pub fn create_market_without_whitelisting(
    market_manager: IMarketManagerDispatcher, params: CreateMarketParams
) -> felt252 {
    set_contract_address(params.owner);
    market_manager
        .create_market(
            params.base_token,
            params.quote_token,
            params.width,
            params.strategy,
            params.swap_fee_rate,
            params.fee_controller,
            params.start_limit,
            params.controller,
            params.market_configs,
        )
}

pub fn modify_position(
    market_manager: IMarketManagerDispatcher, params: ModifyPositionParams,
) -> (i256, i256, u256, u256) {
    set_contract_address(params.owner);
    market_manager
        .modify_position(
            params.market_id, params.lower_limit, params.upper_limit, params.liquidity_delta,
        )
}

pub fn swap(market_manager: IMarketManagerDispatcher, params: SwapParams) -> (u256, u256, u256) {
    set_contract_address(params.owner);
    market_manager
        .swap(
            params.market_id,
            params.is_buy,
            params.amount,
            params.exact_input,
            params.threshold_sqrt_price,
            params.threshold_amount,
            params.deadline,
        )
}

pub fn swap_multiple(market_manager: IMarketManagerDispatcher, params: SwapMultipleParams) -> u256 {
    set_contract_address(params.owner);
    market_manager
        .swap_multiple(
            params.in_token,
            params.out_token,
            params.amount,
            params.route,
            params.threshold_amount,
            params.deadline,
        )
}

pub fn transfer_owner(market_manager: IMarketManagerDispatcher, params: TransferOwnerParams) -> () {
    set_contract_address(params.owner);
    market_manager.transfer_owner(params.new_owner);
}

pub fn accept_owner(market_manager: IMarketManagerDispatcher, new_owner: ContractAddress) -> () {
    set_contract_address(new_owner);
    market_manager.accept_owner();
}
