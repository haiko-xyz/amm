// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::math::{price_math, fee_math};
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT, MIN_LIMIT};
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::core::LimitInfo;
use amm::types::i256::{i256, I256Trait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position, swap
};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::params::{
    owner, alice, treasury, default_token_params, default_market_params, modify_position_params,
    swap_params
};
use amm::tests::common::utils::to_e28;

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before(
    width: u32
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
    params.start_limit = OFFSET - 0; // initial limit
    let market_id = create_market(market_manager, params);

    // Fund LP with initial token balances and approve market manager as spender.
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
#[available_gas(1000000000)]
fn test_reinitialise_fee_factor() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    // Create position
    let lower_limit = OFFSET - 1000;
    let upper_limit = OFFSET + 1000;
    let liq_abs = 100000;
    let mut liquidity = I256Trait::new(liq_abs, false);
    let mut params = modify_position_params(
        alice(), market_id, lower_limit, upper_limit, liquidity
    );
    modify_position(market_manager, params);

    // Swap so fee factors of position are non-zero.
    let mut is_buy = false;
    let exact_input = true;
    let amount = 100000;
    let mut swap_params = swap_params(
        alice(),
        market_id,
        is_buy,
        exact_input,
        amount,
        Option::None(()),
        Option::None(()),
        Option::None(()),
    );
    let (amount_in, amount_out, fee) = swap(market_manager, swap_params);

    // Swap back.
    is_buy = true;
    swap_params =
        swap_params(
            alice(),
            market_id,
            is_buy,
            exact_input,
            amount,
            Option::None(()),
            Option::None(()),
            Option::None(()),
        );
    swap(market_manager, swap_params);
    print_fee_factors(market_manager, market_id, lower_limit, upper_limit);

    // Remove position.
    liquidity = I256Trait::new(liq_abs, true);
    params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);
    print_fee_factors(market_manager, market_id, lower_limit, upper_limit);

    // Adding liquidity to same limits should re-initialise fee factors.
    liquidity = I256Trait::new(liq_abs, false);
    params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);
    print_fee_factors(market_manager, market_id, lower_limit, upper_limit);
}

////////////////////////////////
// INTERNAL HELPERS
////////////////////////////////

fn print_fee_factors(
    market_manager: IMarketManagerDispatcher,
    market_id: felt252,
    lower_limit: u32,
    upper_limit: u32,
) {
    let market_state = market_manager.market_state(market_id);
    'global base ff'.print();
    market_state.base_fee_factor.print();
    'global quote ff'.print();
    market_state.quote_fee_factor.print();

    let lower_limit_info = market_manager.limit_info(market_id, lower_limit);
    let upper_limit_info = market_manager.limit_info(market_id, upper_limit);
    'lower base ff'.print();
    lower_limit_info.base_fee_factor.print();
    'lower quote ff'.print();
    lower_limit_info.quote_fee_factor.print();
    'upper base ff'.print();
    upper_limit_info.base_fee_factor.print();
    'upper quote ff'.print();
    upper_limit_info.quote_fee_factor.print();

    let position = market_manager.position(market_id, alice().into(), lower_limit, upper_limit);
    'position base ff last'.print();
    position.base_fee_factor_last.print();
    'position quote ff last'.print();
    position.quote_fee_factor_last.print();
    let (pos_base_fee_factor, pos_quote_fee_factor) = fee_math::get_fee_inside(
        lower_limit_info,
        upper_limit_info,
        lower_limit,
        upper_limit,
        market_state.curr_limit,
        market_state.base_fee_factor,
        market_state.quote_fee_factor,
    );
    'position base ff'.print();
    pos_base_fee_factor.print();
    'position quote ff'.print();
    pos_quote_fee_factor.print();
}
