// Core lib imports.
use cmp::{min, max};

// Local imports.
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT};
use amm::libraries::math::fee_math;
use amm::types::core::{SwapParams, PositionInfo};
use amm::types::i256::I256Trait;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IStrategy::{IStrategyDispatcher, IStrategyDispatcherTrait};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap, swap_multiple},
    token::{declare_token, deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, encode_sqrt_price};
use strategies::strategies::replicating::{
    replicating_strategy::{IReplicatingStrategyDispatcher, IReplicatingStrategyDispatcherTrait},
    pragma_interfaces::{DataType, PragmaPricesResponse},
    mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait}
};
use strategies::tests::snforge::replicating::helpers::{
    deploy_replicating_strategy, deploy_mock_pragma_oracle
};

// External imports.
use snforge_std::{start_prank, stop_prank, PrintTrait};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

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
    liquidity: u256,
    base_fee_factor: u256,
    quote_fee_factor: u256,
    base_fee_factor_last: u256,
    quote_fee_factor_last: u256,
    lower_limit: LimitState,
    upper_limit: LimitState,
}

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (
    IMarketManagerDispatcher,
    felt252,
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    IMockPragmaOracleDispatcher,
    IReplicatingStrategyDispatcher,
) {
    // Deploy market manager.
    let market_manager = deploy_market_manager(owner());

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let erc20_class = declare_token();
    let base_token = deploy_token(erc20_class, base_token_params);
    let quote_token = deploy_token(erc20_class, quote_token_params);

    // Deploy mock oracle.
    let oracle = deploy_mock_pragma_oracle(owner());

    // Deploy replicating strategy.
    let strategy = deploy_replicating_strategy(owner());

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = OFFSET;
    params.width = 1;
    params.strategy = strategy.contract_address;
    let market_id = create_market(market_manager, params);

    // Fund LP with initial token balances and approve market manager as spender.
    let base_amount = to_e28(5000000000000000000000000000);
    let quote_amount = to_e28(10000000000000000000000000000);
    fund(base_token, alice(), base_amount);
    fund(quote_token, alice(), quote_amount);
    approve(base_token, alice(), market_manager.contract_address, base_amount);
    approve(quote_token, alice(), market_manager.contract_address, quote_amount);
    approve(base_token, alice(), strategy.contract_address, base_amount);
    approve(quote_token, alice(), strategy.contract_address, quote_amount);

    // Fund owner with initial token balances and approve strategy and market manager as spenders.
    fund(base_token, owner(), base_amount);
    fund(quote_token, owner(), quote_amount);
    approve(base_token, owner(), market_manager.contract_address, base_amount);
    approve(quote_token, owner(), market_manager.contract_address, quote_amount);
    approve(base_token, owner(), strategy.contract_address, base_amount);
    approve(quote_token, owner(), strategy.contract_address, quote_amount);

    // Initialise strategy.
    start_prank(strategy.contract_address, owner());
    strategy
        .initialise(
            'ETH-USDC Replicating 1 0.3%',
            'ETH-USDC REPL-1-0.3%',
            market_manager.contract_address,
            market_id,
            oracle.contract_address,
            'ETH/USD',
            'USDC/USD',
            100000000000000000000, // 10^20 = 10^28 / 10^8
            10, // ~0.01% min spread
            20000, // ~20% slippage
            200, // ~0.2% delta
        );

    // Set initial oracle price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 100000000); // 1

    // Deposit initial to strategy.
    strategy.deposit_initial(to_e18(10000000), to_e18(11125200));
    stop_prank(strategy.contract_address);

    (market_manager, market_id, base_token, quote_token, oracle, strategy)
}

////////////////////////////////
// TESTS
////////////////////////////////

// Caution: make sure to comment out `update_positions` in `replicating_strategy` 
// before running this test.
#[test]
fn test_fee_factor_invariants_replicating(
    pos1_limit1: u16,
    pos1_limit2: u16,
    pos1_liquidity: u32,
    pos1_rem_pct: u8,
    pos2_limit1: u16,
    pos2_limit2: u16,
    pos2_liquidity: u32,
    pos2_rem_pct: u8,
    pos3_limit1: u16,
    pos3_limit2: u16,
    pos3_liquidity: u32,
    pos3_rem_pct: u8,
    pos4_limit1: u16,
    pos4_limit2: u16,
    pos4_liquidity: u32,
    pos4_rem_pct: u8,
    pos5_limit1: u16,
    pos5_limit2: u16,
    pos5_liquidity: u32,
    pos5_rem_pct: u8,
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
    price_chg1: u16,
    price_chg2: u16,
    price_chg3: u16,
    price_chg4: u16,
    price_chg5: u16,
    price_chg6: u16,
    price_chg7: u16,
    price_chg8: u16,
    price_chg9: u16,
    price_chg10: u16,
) {
    let (market_manager, market_id, base_token, quote_token, oracle, strategy) = before();

    // Initialise swap params.
    let swap_params = array![
        (swap1_amount, price_chg1),
        (swap2_amount, price_chg2),
        (swap3_amount, price_chg3),
        (swap4_amount, price_chg4),
        (swap5_amount, price_chg5),
        (swap6_amount, price_chg6),
        (swap7_amount, price_chg7),
        (swap8_amount, price_chg8),
        (swap9_amount, price_chg9),
        (swap10_amount, price_chg10),
    ]
        .span();

    // Initialise position params.
    let pos1_lower_limit = OFFSET - 32768 + min(pos1_limit1, pos1_limit2).into();
    let pos1_upper_limit = OFFSET - 32768 + max(pos1_limit1, pos1_limit2).into();
    let pos1_liquidity: u256 = pos1_liquidity.into() * 1000000;
    let pos1_rem_liq = pos1_liquidity * pos1_rem_pct.into() / 256;
    let pos2_lower_limit = OFFSET - 32768 + min(pos2_limit1, pos2_limit2).into();
    let pos2_upper_limit = OFFSET - 32768 + max(pos2_limit1, pos2_limit2).into();
    let pos2_liquidity: u256 = pos2_liquidity.into() * 1000000;
    let pos2_rem_liq = pos2_liquidity * pos2_rem_pct.into() / 256;
    let pos3_lower_limit = OFFSET - 32768 + min(pos3_limit1, pos3_limit2).into();
    let pos3_upper_limit = OFFSET - 32768 + max(pos3_limit1, pos3_limit2).into();
    let pos3_liquidity: u256 = pos3_liquidity.into() * 1000000;
    let pos3_rem_liq = pos3_liquidity * pos3_rem_pct.into() / 256;
    let pos4_lower_limit = OFFSET - 32768 + min(pos4_limit1, pos4_limit2).into();
    let pos4_upper_limit = OFFSET - 32768 + max(pos4_limit1, pos4_limit2).into();
    let pos4_liquidity: u256 = pos4_liquidity.into() * 1000000;
    let pos4_rem_liq = pos4_liquidity * pos4_rem_pct.into() / 256;
    let pos5_lower_limit = OFFSET - 32768 + min(pos5_limit1, pos5_limit2).into();
    let pos5_upper_limit = OFFSET - 32768 + max(pos5_limit1, pos5_limit2).into();
    let pos5_liquidity: u256 = pos5_liquidity.into() * 1000000;
    let pos5_rem_liq = pos5_liquidity * pos5_rem_pct.into() / 256;
    let mut position_params = array![
        (pos1_lower_limit, pos1_upper_limit, pos1_liquidity, pos1_rem_liq),
        (pos2_lower_limit, pos2_upper_limit, pos2_liquidity, pos2_rem_liq),
        (pos3_lower_limit, pos3_upper_limit, pos3_liquidity, pos3_rem_liq),
        (pos4_lower_limit, pos4_upper_limit, pos4_liquidity, pos4_rem_liq),
        (pos5_lower_limit, pos5_upper_limit, pos5_liquidity, pos5_rem_liq),
    ]
        .span();

    // Initialise oracle price.
    let mut oracle_price: u128 = 100000000;

    // Loop through iterations and: 
    // 1. Update oracle price
    // 2. Execute swaps
    // 3. Add liquidity (if even) or remove liquidity (if odd)
    // 4. Check fee factor invariants
    let mut i = 0;
    loop {
        if i >= 10 {
            break;
        }
        // Fetch swap and position params.
        let (swap_amount, price_chg) = *swap_params.at(i);
        let (lower_limit, upper_limit, liquidity, liq_rem) = *position_params.at(i / 2);
        let is_remove = i % 2 != 0;

        // Update oracle price.
        if price_chg % 2 == 0 {
            oracle_price += price_chg.into() * 100;
        } else {
            oracle_price -= price_chg.into() * 100;
        }
        oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', oracle_price);

        // Fetch queued positions.
        let strategy_addr = strategy.contract_address;
        let queued_positions = IStrategyDispatcher { contract_address: strategy_addr }
            .queued_positions();

        // Snapshot state before.
        let (market_state_bef, strategy_pos_bef) = snapshot_all(
            market_manager, market_id, queued_positions
        );

        // Execute swap, skipping fail cases.
        if swap_amount != 0 {
            // Setup params.
            let is_buy = swap_amount % 2 == 0;
            let mut params = swap_params(
                alice(),
                market_id,
                is_buy,
                true,
                swap_amount.into(),
                Option::None(()),
                Option::None(())
            );

            start_prank(market_manager.contract_address, strategy.contract_address);
            start_prank(strategy.contract_address, market_manager.contract_address);
            // Manually call update positions.
            IStrategyDispatcher { contract_address: strategy.contract_address }
                .update_positions(
                    SwapParams {
                        is_buy,
                        amount: swap_amount.into(),
                        exact_input: true,
                        threshold_sqrt_price: Option::None(()),
                        deadline: Option::None(())
                    }
                );
            stop_prank(market_manager.contract_address);

            // Execute swap with strategy update disabled.
            // Caution: make sure to comment out `update_positions` in `replicating_strategy`
            // before running this test.
            start_prank(market_manager.contract_address, alice());
            swap(market_manager, params);
            stop_prank(market_manager.contract_address);

            stop_prank(strategy.contract_address);
        }

        // Modify position, skipping fail cases.
        if lower_limit != upper_limit && liquidity != 0 {
            let amount = if is_remove {
                liq_rem
            } else {
                liquidity
            };
            let mut params = modify_position_params(
                alice(), market_id, lower_limit, upper_limit, I256Trait::new(amount, is_remove)
            );
            modify_position(market_manager, params);
        }

        // Snapshot state after.
        let (market_state_aft, strategy_pos_aft) = snapshot_all(
            market_manager, market_id, queued_positions
        );

        // Check fee factor invariants.
        // Loop through positions.
        let mut j = 0;
        loop {
            if j >= strategy_pos_aft.len() {
                break;
            }

            // Invariant 1: fee factor inside position is never negative.
            // No actual checks need to be performed here as it would have failed on snapshot.

            // Invariant 2: fee factor inside position always increases after swap.
            let before = *strategy_pos_aft.at(j);
            let after = *strategy_pos_aft.at(j);
            assert(after.base_fee_factor >= before.base_fee_factor, 'Invariant 2: base');
            assert(after.quote_fee_factor >= before.quote_fee_factor, 'Invariant 2: quote');

            // Invariant 3: position fee factor should never exceed global fee factor.
            assert(after.base_fee_factor <= market_state_aft.base_fee_factor, 'Invariant 3: base');
            assert(
                after.quote_fee_factor <= market_state_aft.quote_fee_factor, 'Invariant 3: quote'
            );

            // Invariant 4: fee factor inside position should always be gte fee factor last.
            assert(after.base_fee_factor >= before.base_fee_factor_last, 'Invariant 4: base');
            assert(after.quote_fee_factor >= before.quote_fee_factor_last, 'Invariant 4: quote');

            j += 1;
        };

        // Move to next position.
        i += 1;
    };
}

////////////////////////////////
// INTERNAL HELPERS
////////////////////////////////

// Returns global state of market and all positions.
fn snapshot_all(
    market_manager: IMarketManagerDispatcher,
    market_id: felt252,
    position_params: Span<PositionInfo>
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
        let PositionInfo{lower_limit, upper_limit, liquidity } = *position_params.at(i);

        // Fetch position.
        let position = market_manager.position(market_id, alice().into(), lower_limit, upper_limit);

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
        position_states
            .append(
                PositionState {
                    liquidity: position.liquidity,
                    base_fee_factor,
                    quote_fee_factor,
                    base_fee_factor_last: position.base_fee_factor_last,
                    quote_fee_factor_last: position.quote_fee_factor_last,
                    lower_limit: LimitState {
                        base_fee_factor: lower_limit_info.base_fee_factor,
                        quote_fee_factor: lower_limit_info.quote_fee_factor,
                    },
                    upper_limit: LimitState {
                        base_fee_factor: upper_limit_info.base_fee_factor,
                        quote_fee_factor: upper_limit_info.quote_fee_factor,
                    },
                }
            );

        i += 1;
    };

    // Return global state and position states.
    (market_state, position_states.span())
}
