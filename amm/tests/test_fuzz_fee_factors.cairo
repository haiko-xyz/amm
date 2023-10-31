// Core lib imports.
use starknet::testing::set_contract_address;
use cmp::{min, max};

// Local imports.
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT};
use amm::libraries::id;
use amm::libraries::math::fee_math;
use amm::types::i256::I256Trait;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IERC20::{IERC20Dispatcher, IERC20DispatcherTrait};
use amm::tests::helpers::actions::market_manager::{
    deploy_market_manager, create_market, modify_position, swap, swap_multiple
};
use amm::tests::helpers::actions::token::{deploy_token, fund, approve};
use amm::tests::helpers::params::{
    owner, alice, treasury, token_params, default_market_params, modify_position_params, 
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::helpers::utils::{to_e28, to_e18, encode_sqrt_price};

use debug::PrintTrait;

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, felt252, IERC20Dispatcher, IERC20Dispatcher) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Fund LP with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(5000000000000000000000000000000000000000000);
    let initial_quote_amount = to_e28(100000000000000000000000000000000000000000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = OFFSET + 32768;
    params.width = 1;

    let market_id = create_market(market_manager, params);

    (market_manager, market_id, base_token, quote_token)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
// #[fuzzer(runs: 30, seed: 88)]
fn test_fee_factor_invariants(
    pos1_limit1: u16,
    pos1_limit2: u16,
    pos1_liquidity: u256,
    pos2_limit1: u16,
    pos2_limit2: u16,
    pos2_liquidity: u256,
    pos3_limit1: u16,
    pos3_limit2: u16,
    pos3_liquidity: u256,
    pos4_limit1: u16,
    pos4_limit2: u16,
    pos4_liquidity: u256,
    pos5_limit1: u16,
    pos5_limit2: u16,
    pos5_liquidity: u256,
    swap1_amount: u256,
    swap2_amount: u256,
    swap3_amount: u256,
    swap4_amount: u256,
    swap5_amount: u256,
    swap6_amount: u256,
    swap7_amount: u256,
    swap8_amount: u256,
    swap9_amount: u256,
    swap10_amount: u256,
) {
    let (market_manager, market_id, base_token, quote_token) = before();

    // Initialise position params.
    let pos1_lower_limit = OFFSET - 32768 + min(pos1_limit1, pos1_limit2).into();
    let pos1_upper_limit = OFFSET - 32768 + max(pos1_limit1, pos1_limit2).into();
    let pos2_lower_limit = OFFSET - 32768 + min(pos2_limit1, pos2_limit2).into();
    let pos2_upper_limit = OFFSET - 32768 + max(pos2_limit1, pos2_limit2).into();
    let pos3_lower_limit = OFFSET - 32768 + min(pos3_limit1, pos3_limit2).into();
    let pos3_upper_limit = OFFSET - 32768 + max(pos3_limit1, pos3_limit2).into();
    let pos4_lower_limit = OFFSET - 32768 + min(pos4_limit1, pos4_limit2).into();
    let pos4_upper_limit = OFFSET - 32768 + max(pos4_limit1, pos4_limit2).into();
    let pos5_lower_limit = OFFSET - 32768 + min(pos5_limit1, pos5_limit2).into();
    let pos5_upper_limit = OFFSET - 32768 + max(pos5_limit1, pos5_limit2).into();
    let mut position_params = array![
        (pos1_lower_limit, pos1_upper_limit, pos1_liquidity),
        (pos2_lower_limit, pos2_upper_limit, pos2_liquidity),
        (pos3_lower_limit, pos3_upper_limit, pos3_liquidity),
        (pos4_lower_limit, pos4_upper_limit, pos4_liquidity),
        (pos5_lower_limit, pos5_upper_limit, pos5_liquidity),
    ].span();

    // Place positions.
    let mut i = 0;
    loop {
        if i >= position_params.len() {
            break;
        }
        let (lower_limit, upper_limit, liquidity) = *position_params.at(i);
        let mut params = modify_position_params(
            alice(), market_id, lower_limit, upper_limit, I256Trait::new(liquidity, false)
        );
        modify_position(market_manager, params);
        i += 1;
    };

    // Execute swaps and check fee factor invariants.
    let swap_amounts = array![
        swap1_amount, swap2_amount, swap3_amount, swap4_amount, swap5_amount,
        swap6_amount, swap7_amount, swap8_amount, swap9_amount, swap10_amount,
    ];
    // Loop through swaps.
    let mut j = 0;
    loop {
        if j >= swap_amounts.len() {
            break;
        }

        // Execute swap.
        let amount = *swap_amounts.at(j);
        let mut params = swap_params(
            alice(), market_id, true, true, amount, Option::None(()), Option::None(())
        );
        swap(market_manager, params);

        // Check fee factor invariants.
        // Loop through positions.
        let mut k = 0;
        loop {
            if k >= position_params.len() {
                break;
            }

            // Fetch market state and limit info.
            let (lower_limit, upper_limit, liquidity) = *position_params.at(k);
            let lower_limit_info = market_manager.limit_info(market_id, lower_limit);
            let upper_limit_info = market_manager.limit_info(market_id, upper_limit);
            let market_state = market_manager.market_state(market_id);

            // Invariant 1: fee factor inside position is never negative.
            // Checks are performed inside of this fn so they are not repeated here.
            let (base_fee_factor, quote_fee_factor) = fee_math::get_fee_inside(
                lower_limit_info,
                upper_limit_info,
                lower_limit,
                upper_limit,
                market_state.curr_limit,
                market_state.base_fee_factor,
                market_state.quote_fee_factor,
            );
            k += 1;
        };
        j += 1;
    };
}