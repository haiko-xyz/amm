// Core lib imports.
use cmp::{min, max};

// Local imports.
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT};
use amm::libraries::id;
use amm::libraries::math::fee_math;
use amm::types::i256::I256Trait;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use super::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap, swap_multiple},
    token::{declare_token, deploy_token, fund, approve},
};
use amm::tests::helpers::params::{
    owner, alice, treasury, token_params, default_market_params, modify_position_params, 
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::helpers::utils::{to_e28, to_e18, encode_sqrt_price};

// External imports.
use snforge_std::{start_prank, PrintTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

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
fn test_fee_factor_invariants(
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

    // 'Start limit'.print();
    // market_manager.market_state(market_id).curr_limit.print();

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
        (pos1_lower_limit, pos1_upper_limit, pos1_liquidity.into() * 1000000),
        (pos2_lower_limit, pos2_upper_limit, pos2_liquidity.into() * 1000000),
        (pos3_lower_limit, pos3_upper_limit, pos3_liquidity.into() * 1000000),
        (pos4_lower_limit, pos4_upper_limit, pos4_liquidity.into() * 1000000),
        (pos5_lower_limit, pos5_upper_limit, pos5_liquidity.into() * 1000000),
    ].span();

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
            // 'Position'.print();
            // lower_limit.print();
            // upper_limit.print();
            // liquidity.print();
            let mut params = modify_position_params(
                alice(), market_id, lower_limit, upper_limit, I256Trait::new(liquidity.into(), false)
            );
            modify_position(market_manager, params);
        }
        // Move to next position.
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

        // Snapshot state before.
        let (market_state_bef, position_states_bef) = snapshot_state(
            market_manager, market_id, position_params
        );

        // Execute swap, skipping fail cases.
        let amount = *swap_amounts.at(j);
        let is_buy = amount % 2 == 0;
        if amount != 0 {
            // 'Swap'.print();
            // amount.print();
            // is_buy.print();
            let mut params = swap_params(
                alice(), market_id, is_buy, true, amount.into(), Option::None(()), Option::None(())
            );
            swap(market_manager, params);

            // Snapshot state after.
            let (market_state_aft, position_states_aft) = snapshot_state(
                market_manager, market_id, position_params
            );

            // Check fee factor invariants.
            // Loop through positions.
            let mut k = 0;
            loop {
                if k >= position_params.len() {
                    break;
                }

                // Invariant 1: fee factor inside position is never negative.
                // No actual checks need to be performed here as it would have failed on snapshot.

                // Invariant 2: fee factor inside position always increases after swap.
                let before = *position_states_bef.at(k);
                let after = *position_states_aft.at(k);
                assert(after.base_fee_factor >= before.base_fee_factor, 'Invariant 2: base');
                assert(after.quote_fee_factor >= before.quote_fee_factor, 'Invariant 2: quote');

                k += 1;
            };
        }
        j += 1;
    };
}

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
struct MarketState {
    curr_limit: u32,
    base_fee_factor: u256,
    quote_fee_factor: u256,
}

#[derive(Drop, Copy)]
struct LimitState {
    base_fee_factor: u256,
    quote_fee_factor: u256,
}

#[derive(Drop, Copy)]
struct PositionState {
    base_fee_factor: u256,
    quote_fee_factor: u256,
    lower_limit: LimitState,
    upper_limit: LimitState,
}

////////////////////////////////
// INTERNAL HELPERS
////////////////////////////////

// Returns global state of market and all positions.
fn snapshot_state(
    market_manager: IMarketManagerDispatcher,
    market_id: felt252,
    position_params: Span<(u32, u32, u256)>
) -> (MarketState, Span<PositionState>) {
    // Fetch market state.
    let market_state_full = market_manager.market_state(market_id);
    let market_state = MarketState {
        curr_limit: market_state_full.curr_limit,
        base_fee_factor: market_state_full.base_fee_factor,
        quote_fee_factor: market_state_full.quote_fee_factor,
    };

    // Fetch position states.
    let mut i = 0;
    let mut position_states = array![];
    loop {
        if i >= position_params.len() {
            break;
        }

        // Fetch position params.
        let (lower_limit, upper_limit, liquidity) = *position_params.at(i);

        // Fetch limit info.
        let lower_limit_info = market_manager.limit_info(market_id, lower_limit);
        let upper_limit_info = market_manager.limit_info(market_id, upper_limit);

        // Fetch fee factors.
        let (base_fee_factor, quote_fee_factor) = fee_math::get_fee_inside(
            lower_limit_info,
            upper_limit_info,
            lower_limit,
            upper_limit,
            market_state.curr_limit,
            market_state.base_fee_factor,
            market_state.quote_fee_factor,
        );

        // Append position state.
        position_states.append(PositionState {
            base_fee_factor,
            quote_fee_factor,
            lower_limit: LimitState {
                base_fee_factor: lower_limit_info.base_fee_factor,
                quote_fee_factor: lower_limit_info.quote_fee_factor,
            },
            upper_limit: LimitState {
                base_fee_factor: upper_limit_info.base_fee_factor,
                quote_fee_factor: upper_limit_info.quote_fee_factor,
            },
        });

        i += 1;
    };

    // Return global state and position states.
    (market_state, position_states.span())
}