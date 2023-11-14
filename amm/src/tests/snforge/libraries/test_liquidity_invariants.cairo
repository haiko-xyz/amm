// Core lib imports.
use cmp::{min, max};

// Local imports.
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT};
use amm::libraries::math::fee_math;
use amm::libraries::id;
use amm::libraries::liquidity as liquidity_helpers;
use amm::types::i256::I256Trait;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap, swap_multiple},
    token::{declare_token, deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, encode_sqrt_price};

// External imports.
use snforge_std::{start_prank, PrintTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, felt252, IERC20Dispatcher, IERC20Dispatcher) {
    // Deploy market manager.
    let market_manager = deploy_market_manager(owner());

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let erc20_class = declare_token();
    let base_token = deploy_token(erc20_class, base_token_params);
    let quote_token = deploy_token(erc20_class, quote_token_params);

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
    params.start_limit = OFFSET;
    params.width = 1;

    let market_id = create_market(market_manager, params);

    (market_manager, market_id, base_token, quote_token)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_amounts_inside_position_invariants(
    pos1_limit1: u16,
    pos1_limit2: u16,
    pos1_liquidity: u32,
    pos2_limit1: u16,
    pos2_limit2: u16,
    pos2_liquidity: u32,
    pos3_limit1: u16,
    pos3_limit2: u16,
    pos3_liquidity: u32,
    pos4_limit1: u16,
    pos4_limit2: u16,
    pos4_liquidity: u32,
    pos5_limit1: u16,
    pos5_limit2: u16,
    pos5_liquidity: u32,
    swap1_amount: u32,
    swap2_amount: u32,
    swap3_amount: u32,
    swap4_amount: u32,
    swap5_amount: u32,
    swap6_amount: u32,
    swap7_amount: u32,
    swap8_amount: u32,
    swap9_amount: u32,
    swap10_amount: u32,
) {
    let (market_manager, market_id, base_token, quote_token) = before();

    // Initialise position params.
    let pos1_lower_limit = OFFSET - 32768 + min(pos1_limit1, pos1_limit2).into();
    let pos1_upper_limit = OFFSET - 32768 + max(pos1_limit1, pos1_limit2).into();
    let pos1_liquidity: u256 = pos1_liquidity.into() * 1000000;
    let pos2_lower_limit = OFFSET - 32768 + min(pos2_limit1, pos2_limit2).into();
    let pos2_upper_limit = OFFSET - 32768 + max(pos2_limit1, pos2_limit2).into();
    let pos2_liquidity: u256 = pos2_liquidity.into() * 1000000;
    let pos3_lower_limit = OFFSET - 32768 + min(pos3_limit1, pos3_limit2).into();
    let pos3_upper_limit = OFFSET - 32768 + max(pos3_limit1, pos3_limit2).into();
    let pos3_liquidity: u256 = pos3_liquidity.into() * 1000000;
    let pos4_lower_limit = OFFSET - 32768 + min(pos4_limit1, pos4_limit2).into();
    let pos4_upper_limit = OFFSET - 32768 + max(pos4_limit1, pos4_limit2).into();
    let pos4_liquidity: u256 = pos4_liquidity.into() * 1000000;
    let pos5_lower_limit = OFFSET - 32768 + min(pos5_limit1, pos5_limit2).into();
    let pos5_upper_limit = OFFSET - 32768 + max(pos5_limit1, pos5_limit2).into();
    let pos5_liquidity: u256 = pos5_liquidity.into() * 1000000;

    let mut position_params = array![
        (pos1_lower_limit, pos1_upper_limit, pos1_liquidity),
        (pos2_lower_limit, pos2_upper_limit, pos2_liquidity),
        (pos3_lower_limit, pos3_upper_limit, pos3_liquidity),
        (pos4_lower_limit, pos4_upper_limit, pos4_liquidity),
        (pos5_lower_limit, pos5_upper_limit, pos5_liquidity),
    ]
        .span();

    // Place positions.
    let mut i = 0;
    loop {
        if i >= position_params.len() {
            break;
        }
        // Fetch position params.
        let (lower_limit, upper_limit, liquidity) = *position_params.at(i);

        // Place position if not fail case.
        if lower_limit != upper_limit && liquidity != 0 {
            let mut params = modify_position_params(
                alice(),
                market_id,
                lower_limit,
                upper_limit,
                I256Trait::new(liquidity.into(), false)
            );
            modify_position(market_manager, params);
        }
        // Move to next position.
        i += 1;
    };

    // Execute swaps.
    let swap_amounts = array![
        swap1_amount,
        swap2_amount,
        swap3_amount,
        swap4_amount,
        swap5_amount,
        swap6_amount,
        swap7_amount,
        swap8_amount,
        swap9_amount,
        swap10_amount,
    ]
        .span();
    let mut j = 0;
    loop {
        if j >= swap_amounts.len() {
            break;
        }

        // Execute swap, skipping fail cases.
        let amount = *swap_amounts.at(j);
        let is_buy = amount % 2 == 0;
        if amount != 0 {
            let mut params = swap_params(
                alice(), market_id, is_buy, true, amount.into(), Option::None(()), Option::None(())
            );
            swap(market_manager, params);
        }
        j += 1;
    };

    // Iteratively remove liquidity from each position and check amount inside position invariant.
    let mut m = 0;
    loop {
        if m >= position_params.len() {
            break;
        }

        // Fetch position params.
        let (lower_limit, upper_limit, liquidity) = *position_params.at(m);

        // Skip fail cases.
        if lower_limit != upper_limit && liquidity != 0 {
            // Calculate amount inside position.
            let position_id = id::position_id(market_id, alice().into(), lower_limit, upper_limit);
            let (base_amount_exp, quote_amount_exp) = market_manager.amounts_inside_position(
                market_id, position_id, lower_limit, upper_limit
            );

            // Remove liquidity.
            let mut params = modify_position_params(
                alice(), market_id, lower_limit, upper_limit, I256Trait::new(liquidity, true)
            );
            let (base_amount, quote_amount, _, _) = modify_position(market_manager, params);

            // Check amount inside position match withdrawn.
            'base_amount_exp'.print();
            base_amount_exp.print();
            'base_amount'.print();
            base_amount.val.print();

            assert(base_amount_exp == base_amount.val, 'Invariant: base');
            assert(quote_amount_exp == quote_amount.val, 'Invariant: quote');

            // Execute swap to randomise market conditions.
            let amount = *swap_amounts.at(m);
            let is_buy = amount % 2 == 0;
            let mut params = swap_params(
                alice(), market_id, is_buy, true, amount.into(), Option::None(()), Option::None(())
            );
        }

        m += 1;
    };
}