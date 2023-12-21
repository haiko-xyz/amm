// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address_const;
use integer::{BoundedU32, BoundedU128, BoundedU256};

// Local imports.
use amm::libraries::constants::{OFFSET, MAX_LIMIT, MAX_SCALED};
use amm::libraries::math::{fee_math, price_math, liquidity_math};
use amm::libraries::id;
use amm::interfaces::{
    IMarketManager::{IMarketManager, IMarketManagerDispatcher, IMarketManagerDispatcherTrait},
    IStrategy::{IStrategyDispatcher, IStrategyDispatcherTrait},
};
use amm::types::core::{MarketState, SwapParams};
use amm::types::i128::{i128, I128Trait};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap},
    token::{deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, bob, treasury, default_token_params, default_market_params,
    modify_position_params, swap_params
};
use amm::tests::common::utils::{to_e18, to_e18_u128, to_e28, approx_eq, approx_eq_pct};
use strategies::strategies::replicating::{
    replicating_strategy::ReplicatingStrategy,
    interface::{IReplicatingStrategyDispatcher, IReplicatingStrategyDispatcherTrait},
    pragma::{DataType, PragmaPricesResponse}, types::{StrategyParams, StrategyState},
    test::mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
};
use strategies::tests::replicating::helpers::{
    deploy_replicating_strategy, deploy_mock_pragma_oracle
};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    declare, start_warp, start_prank, stop_prank, CheatTarget, PrintTrait, spy_events, SpyOn,
    EventSpy, EventAssertions, EventFetcher
};

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
struct SwapCase {
    is_buy: bool,
    exact_input: bool,
    amount: u256,
    threshold_sqrt_price: Option<u256>,
}

////////////////////////////////
// SETUP
////////////////////////////////

fn before(
    initialise_market: bool
) -> (
    IMarketManagerDispatcher,
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    felt252,
    IMockPragmaOracleDispatcher,
    IReplicatingStrategyDispatcher,
) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let manager_class = declare('MarketManager');
    let market_manager = deploy_market_manager(manager_class, owner);

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let erc20_class = declare('ERC20');
    let base_token = deploy_token(erc20_class, base_token_params);
    let quote_token = deploy_token(erc20_class, quote_token_params);

    // Deploy oracle contract.
    let oracle = deploy_mock_pragma_oracle(owner);

    // Deploy replicating strategy.
    let strategy = deploy_replicating_strategy(
        owner, market_manager.contract_address, oracle.contract_address, oracle.contract_address
    );

    // Create market.
    let mut params = default_market_params();
    params.width = 10;
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = 7906620 + 741930; // initial limit
    params.strategy = strategy.contract_address;
    let market_id = create_market(market_manager, params);

    // Add market to strategy.
    if initialise_market {
        start_prank(CheatTarget::One(strategy.contract_address), owner());
        strategy
            .add_market(
                market_id,
                owner,
                'ETH',
                'USDC',
                3, // minimum sources
                600, // 10 minutes max age 
                10, // ~0.01% min spread
                20000, // ~20% range
                200, // ~0.2% delta
                true,
                false,
            );
    }

    // Fund owner with initial token balances and approve strategy and market manager as spenders.
    let base_amount = to_e18(5000000);
    let quote_amount = to_e18(1000000000000);
    fund(base_token, owner(), base_amount);
    fund(quote_token, owner(), quote_amount);
    approve(base_token, owner(), market_manager.contract_address, base_amount);
    approve(quote_token, owner(), market_manager.contract_address, quote_amount);
    approve(base_token, owner(), strategy.contract_address, base_amount);
    approve(quote_token, owner(), strategy.contract_address, quote_amount);

    // Fund LP with initial token balances and approve strategy and market manager as spenders.
    fund(base_token, alice(), base_amount);
    fund(quote_token, alice(), quote_amount);
    approve(base_token, alice(), market_manager.contract_address, base_amount);
    approve(quote_token, alice(), market_manager.contract_address, quote_amount);
    approve(base_token, alice(), strategy.contract_address, base_amount);
    approve(quote_token, alice(), strategy.contract_address, quote_amount);

    // Fund strategy with initial token balances and approve market manager as spender.
    // This is due to a limitation with `snforge` pranks that requires the strategy to be the 
    // address executing swaps for checks to pass.
    fund(base_token, strategy.contract_address, base_amount);
    fund(quote_token, strategy.contract_address, quote_amount);
    approve(base_token, strategy.contract_address, market_manager.contract_address, base_amount);
    approve(quote_token, strategy.contract_address, market_manager.contract_address, quote_amount);

    (market_manager, base_token, quote_token, market_id, oracle, strategy)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_get_bid_ask() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 150000000000, 8, 999, 5); // 1500

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = to_e18(1);
    let initial_quote_amount = to_e18(2000);
    strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Get bid and ask.
    // Expect inventory delta of 1/7 * 200 = 30 (rounded up).
    // Expect bid to be placed at 7906620 + 731320 (oracle) - 10 (min spread) - 30 (inv delta).
    // Expect ask to be placed at 7906620 + 741930 (curr price) + 10 (min spread).
    let (bid_lower, bid_upper, ask_lower, ask_upper) = strategy.get_bid_ask(market_id);
    assert(bid_upper == 7906620 + 731320 - 10 - 30, 'Bid upper');
    assert(bid_lower == bid_upper - 20000, 'Bid lower');
    assert(ask_lower == 7906620 + 741930 + 10, 'Ask lower');
    assert(ask_upper == ask_lower + 20000, 'Ask upper');
}

#[test]
fn test_queued_and_placed_positions() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = to_e18(1);
    let initial_quote_amount = to_e18(2000);
    strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 180000000000, 8, 999, 5);

    // Get queued position.
    let strategy_alt = IStrategyDispatcher { contract_address: strategy.contract_address };
    let queued_positions = strategy_alt.queued_positions(market_id);
    let next_bid = *queued_positions.at(0);
    let next_ask = *queued_positions.at(1);

    // Swap to update positions.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    market_manager
        .swap(
            market_id,
            true,
            to_e18(1000),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

    // Get placed positions.
    let placed_positions = strategy_alt.placed_positions(market_id);
    let bid = *placed_positions.at(0);
    let ask = *placed_positions.at(1);

    // Run checks.
    assert(next_bid == bid, 'Queued positions: bid');
    assert(next_ask == ask, 'Queued positions: ask');
}

#[test]
fn test_queued_positions_uninitialised_market() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Fetch queued positions for uninitialised market.
    let strategy_alt = IStrategyDispatcher { contract_address: strategy.contract_address };
    let queued_positions = strategy_alt.queued_positions(1);
    let next_bid = *queued_positions.at(0);
    let next_ask = *queued_positions.at(1);

    // Run checks.
    assert(next_bid.lower_limit == 0, 'Queued pos: bid lower limit');
    assert(next_bid.upper_limit == 0, 'Queued pos: bid upper limit');
    assert(next_bid.liquidity == 0, 'Queued pos: bid liquidity');
    assert(next_ask.lower_limit == 0, 'Queued pos: ask lower limit');
    assert(next_ask.upper_limit == 0, 'Queued pos: ask upper limit');
    assert(next_ask.liquidity == 0, 'Queued pos: ask liquidity');
}

#[test]
fn test_add_market_initialises_state() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(false);

    // Record events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Add market.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.add_market(market_id, owner(), 'ETH', 'USDC', 3, 600, 10, 20000, 200, true, false);

    // Check strategy params correctly updated.
    let params = strategy.strategy_params(market_id);
    assert(params.min_spread == 10, 'Min spread');
    assert(params.range == 20000, 'Range');
    assert(params.max_delta == 200, 'Delta');
    assert(params.allow_deposits, 'Allow deposits');

    // Check oracle params correctly updated.
    let oracle_params = strategy.oracle_params(market_id);
    assert(oracle_params.base_currency_id == 'ETH', 'Base curr id');
    assert(oracle_params.quote_currency_id == 'USDC', 'Quote curr id');
    assert(oracle_params.min_sources == 3, 'Min sources');
    assert(oracle_params.max_age == 600, 'Max age');

    // Check market state correctly updated.
    let state = strategy.strategy_state(market_id);
    assert(state.is_initialised, 'Initialised');
    assert(!state.is_paused, 'Paused');
    assert(state.base_reserves == 0, 'Base reserves');
    assert(state.quote_reserves == 0, 'Quote reserves');
    assert(state.bid.lower_limit == 0, 'Bid: lower limit');
    assert(state.bid.upper_limit == 0, 'Bid: upper limit');
    assert(state.bid.liquidity == 0, 'Bid: liquidity');
    assert(state.ask.lower_limit == 0, 'Ask: lower limit');
    assert(state.ask.upper_limit == 0, 'Ask: upper limit');
    assert(state.ask.liquidity == 0, 'Ask: liquidity');

    // Check owner correctly updated.
    assert(strategy.strategy_owner(market_id) == owner(), 'Owner');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::AddMarket(
                        ReplicatingStrategy::AddMarket { market_id }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: ('MarketNull',))]
fn test_add_market_market_null() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Register null market.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.add_market(1, owner(), 'ETH', 'USDC', 3, 600, 10, 20000, 200, true, false);
}

#[test]
#[should_panic(expected: ('Initialised',))]
fn test_add_market_already_initialised() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Register null market.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.add_market(market_id, owner(), 'ETH', 'USDC', 3, 600, 10, 20000, 200, true, false);
}

#[test]
#[should_panic(expected: ('RangeZero',))]
fn test_add_market_range_zero() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Technically the market id does not exist but because this check is run before the
    // market null check, it catches the error correctly.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.add_market(1, owner(), 'ETH', 'USDC', 3, 600, 10, 0, 200, true, false);
}

#[test]
#[should_panic(expected: ('MinSourcesZero',))]
fn test_add_market_min_sources_zero() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Technically the market id does not exist but because this check is run before the
    // market null check, it catches the error correctly.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.add_market(1, owner(), 'ETH', 'USDC', 0, 600, 10, 20000, 200, true, false);
}

#[test]
#[should_panic(expected: ('MaxAgeZero',))]
fn test_add_market_max_age_zero() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Technically the market id does not exist but because this check is run before the
    // market null check, it catches the error correctly.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.add_market(1, owner(), 'ETH', 'USDC', 3, 0, 10, 20000, 200, true, false);
}

#[test]
#[should_panic(expected: ('BaseIdNull',))]
fn test_add_market_base_id_null() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Technically the market id does not exist but because this check is run before the
    // market null check, it catches the error correctly.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.add_market(1, owner(), 0, 'USDC', 3, 600, 10, 20000, 200, true, false);
}

#[test]
#[should_panic(expected: ('QuoteIdNull',))]
fn test_add_market_quote_id_null() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Technically the market id does not exist but because this check is run before the
    // market null check, it catches the error correctly.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.add_market(1, owner(), 'ETH', 0, 3, 600, 10, 20000, 200, true, false);
}

#[test]
fn test_deposit_initial_success() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5); // 1668.78

    // Snapshot before.
    let bef = _snapshot_state(
        market_manager, strategy, market_id, base_token, quote_token, owner()
    );

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let shares = strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);
    let base_liquidity_exp = 429406775392817428992841450;
    let quote_liquidity_exp = 286266946460287812818573174;
    let shares_exp = quote_liquidity_exp + base_liquidity_exp;

    // Snapshot after.
    let aft = _snapshot_state(
        market_manager, strategy, market_id, base_token, quote_token, owner()
    );

    // Run checks.
    assert(aft.lp_base_bal == bef.lp_base_bal - initial_base_amount, 'Owner base balance');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - initial_quote_amount, 'Owner quote balance');
    assert(aft.strategy_base_bal == bef.strategy_base_bal, 'Strategy base balance');
    assert(aft.strategy_quote_bal == bef.strategy_quote_bal, 'Strategy quote balance');
    assert(aft.market_base_bal == bef.market_base_bal + initial_base_amount, 'Market base balance');
    assert(
        aft.market_quote_bal == bef.market_quote_bal + initial_quote_amount, 'Market quote balance'
    );
    assert(aft.market_base_res == initial_base_amount, 'Market base reserves');
    assert(aft.market_quote_res == initial_quote_amount, 'Market quote reserves');
    assert(aft.strategy_state.base_reserves == bef.strategy_state.base_reserves, 'Base reserves');
    assert(
        aft.strategy_state.quote_reserves == bef.strategy_state.quote_reserves, 'Quote reserves'
    );
    assert(aft.strategy_state.bid.lower_limit == 7906620 + 721930, 'Bid: lower limit');
    assert(aft.strategy_state.bid.upper_limit == 7906620 + 741930, 'Bid: upper limit');
    assert(aft.strategy_state.ask.lower_limit == 7906620 + 742050, 'Ask: lower limit');
    assert(aft.strategy_state.ask.upper_limit == 7906620 + 762050, 'Ask: upper limit');
    assert(approx_eq_pct(shares, shares_exp, 20), 'Shares');
    assert(
        approx_eq_pct(strategy.user_deposits(market_id, owner()), shares_exp, 20), 'User deposits'
    );
    assert(approx_eq_pct(strategy.total_deposits(market_id), shares_exp, 20), 'Total deposits');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Deposit(
                        ReplicatingStrategy::Deposit {
                            market_id,
                            caller: owner(),
                            base_amount: initial_base_amount,
                            quote_amount: initial_quote_amount,
                        }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: ('DepositInitialZero',))]
fn test_deposit_initial_single_sided_bid_liquidity_correctly_reverts() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // If the position range would case the lower bid limit to overflow, only single sided (ask)
    // liquidity is placed. This should be correctly handled when depositing initial liquidity.

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 1, 28, 999, 5); // Limit = -6447270

    // Set range to overflow upper bounds so only bid liquidity is placed.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.range = 2000000;
    strategy.set_params(market_id, params);

    // Deposit initial.
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = 1000;
    strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);
}

#[test]
#[should_panic(expected: ('DepositInitialZero',))]
fn test_deposit_initial_single_sided_ask_liquidity_correctly_reverts() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // If the position range would case the upper ask limit to overflow, only single sided (bid)
    // liquidity is placed. This should be correctly handled when depositing initial liquidity.

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle
        .set_data_with_USD_hop(
            'ETH', 'USDC', 21764856978905781477192766323629261, 0, 999, 5
        ); // Limit = 7906600

    // Set range to overflow upper bounds so only ask liquidity is placed.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.range = 1000;
    strategy.set_params(market_id, params);

    // Deposit initial.
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);
}

#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_deposit_initial_base_zero() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit_initial(market_id, 0, to_e18(12500));
}

#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_deposit_initial_quote_zero() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit_initial(market_id, to_e18(10), 0);
}

#[test]
#[should_panic(expected: ('NotInitialised',))]
fn test_deposit_initial_market_null() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit_initial(1, to_e18(10), to_e18(12500));
}

#[test]
#[should_panic(expected: ('UseDeposit',))]
fn test_deposit_initial_existing_deposits() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit_initial(market_id, to_e18(100), to_e18(1125200));

    // Deposit.
    strategy.deposit(market_id, to_e18(500), to_e18(700000));

    // Deposit initial again.
    strategy.deposit_initial(market_id, to_e18(100), to_e18(1125200));
}

#[test]
#[should_panic(expected: ('NotWhitelisted',))]
fn test_deposit_initial_user_not_whitelisted() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Enable whitelist.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.use_whitelist = true;
    strategy.set_params(market_id, params);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit_initial(market_id, to_e18(100), to_e18(1125200));
}

#[test]
#[should_panic(expected: ('DepositInitialZero',))]
fn test_deposit_initial_invalid_oracle_price() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 2);

    // Deposit initial should revert if oracle price is invalid.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit_initial(market_id, to_e18(1000000), to_e18(1112520000));
}

#[test]
#[should_panic(expected: ('Paused',))]
fn test_deposit_initial_paused() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Pause strategy.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.pause(market_id);

    // Deposit initial should revert if paused.
    strategy.deposit_initial(market_id, to_e18(1000000), to_e18(1112520000));
}

#[test]
#[should_panic(expected: ('NotInitialised',))]
fn test_deposit_initial_market_not_initialised() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(false);

    // Deposit initial should revert if market not initialised.
    strategy.deposit_initial(market_id, to_e18(1000000), to_e18(1112520000));
}

#[test]
#[should_panic(expected: ('DepositDisabled',))]
fn test_deposit_initial_deposit_disabled() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Disable deposits.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.allow_deposits = false;
    strategy.set_params(market_id, params);

    // Deposit initial should revert if deposits disabled.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit_initial(market_id, to_e18(1000000), to_e18(1112520000));
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_deposit_initial_not_approved() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Set allowance to 0.
    start_prank(CheatTarget::One(base_token.contract_address), owner());
    base_token.approve(strategy.contract_address, 0);
    start_prank(CheatTarget::One(quote_token.contract_address), owner());
    quote_token.approve(strategy.contract_address, 0);

    // Deposit initial should revert.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit_initial(market_id, to_e18(1000000), to_e18(1112520000));
}

#[test]
fn test_update_positions_rebalances() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5); // 1668.78

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let shares = strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price.
    start_warp(CheatTarget::One(oracle.contract_address), 1010);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 168000000000, 8, 1005, 5); // 1680

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Execute swap as strategy and check positions updated.
    // This must be done to overcome a limitation with `prank` that causes tx to revert for a 
    // non-strategy caller.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    let amount = to_e18(500000);
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()), Option::None(()));
    let state = strategy.strategy_state(market_id);
    let market_state = market_manager.market_state(market_id);

    // Run checks.
    assert(state.bid.lower_limit == 7906620 + 721930, 'Bid: lower limit');
    assert(state.bid.upper_limit == 7906620 + 741930, 'Bid: upper limit');
    assert(state.ask.lower_limit == 7906620 + 742720, 'Ask: lower limit');
    assert(state.ask.upper_limit == 7906620 + 762720, 'Ask: upper limit');
    assert(
        approx_eq_pct(state.bid.liquidity.into(), 286266946460287812818573174, 20), 'Bid: liquidity'
    );
    assert(
        approx_eq_pct(state.ask.liquidity.into(), 430847693075374009874980115, 20), 'Ask: liquidity'
    );
    assert(
        approx_eq(market_state.curr_sqrt_price, 410015410053942901623567337309, 100),
        'Market: curr sqrt price'
    );
    assert(market_state.curr_limit == 7906620 + 742725, 'Market: curr sqrt price');
    assert(approx_eq(state.base_reserves, 0, 10), 'Base reserves');
    assert(approx_eq(state.quote_reserves, 0, 10), 'Quote reserves');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::UpdatePositions(
                        ReplicatingStrategy::UpdatePositions {
                            market_id,
                            bid_lower_limit: state.bid.lower_limit,
                            bid_upper_limit: state.bid.upper_limit,
                            bid_liquidity: state.bid.liquidity,
                            ask_lower_limit: state.ask.lower_limit,
                            ask_upper_limit: state.ask.upper_limit,
                            ask_liquidity: state.ask.liquidity,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_update_positions_multiple_swaps() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166700000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(oracle.contract_address), owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let shares = strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price.
    start_warp(CheatTarget::One(oracle.contract_address), 1010);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 163277500000, 8, 1005, 5);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Execute swap 1 as strategy. 
    // This must be done to overcome a limitation with `prank` that causes tx to revert for a 
    // non-strategy caller.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    let amount = to_e18(100);
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()), Option::None(()));

    // Run checks. Expect position not updated as LVR condition not met.
    let state = strategy.strategy_state(market_id);
    let mut market_state = market_manager.market_state(market_id);
    assert(state.bid.lower_limit == 7906620 + 721870, 'Bid 1: lower limit');
    assert(state.bid.upper_limit == 7906620 + 741870, 'Bid 1: upper limit');
    assert(state.ask.lower_limit == 7906620 + 741940, 'Ask 1: lower limit');
    assert(state.ask.upper_limit == 7906620 + 761940, 'Ask 1: upper limit');
    assert(
        approx_eq_pct(state.bid.liquidity.into(), 286352838998000392443103695, 20),
        'Bid 1: liquidity'
    );
    assert(
        approx_eq_pct(state.ask.liquidity.into(), 429170667782432169281955462, 20),
        'Ask 1: liquidity'
    );
    assert(
        approx_eq_pct(market_state.curr_sqrt_price, 408407949181225947147258078960, 20),
        'Swap 1: end sqrt price'
    );
    assert(market_state.curr_limit == 7906620 + 741940, 'Swap 1: end limit');
    assert(approx_eq(state.base_reserves, 0, 10), 'Swap 1: Base reserves');
    assert(approx_eq(state.quote_reserves, 0, 10), 'Swap 1: Quote reserves');

    // Execute swap 2 as strategy and check positions updated. 
    // This must be done to overcome a limitation with `prank` that causes tx to revert for a 
    // non-strategy caller.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    let (amount_in_2, amount_out_2, fees_2) = market_manager
        .swap(market_id, false, amount, true, Option::None(()), Option::None(()), Option::None(()));

    // Run checks.
    let state_2 = strategy.strategy_state(market_id);
    market_state = market_manager.market_state(market_id);
    assert(state_2.bid.lower_limit == 7906620 + 719790, 'Bid 2: lower limit');
    assert(state_2.bid.upper_limit == 7906620 + 739790, 'Bid 2: upper limit');
    assert(state_2.ask.lower_limit == 7906620 + 741950, 'Ask 2: lower limit');
    assert(state_2.ask.upper_limit == 7906620 + 761950, 'Ask 2: upper limit');
    assert(
        approx_eq_pct(state_2.bid.liquidity.into(), 289346459271780151386678214, 20),
        'Bid 2: liquidity'
    );
    assert(
        approx_eq_pct(state_2.ask.liquidity.into(), 429192101090792820578334882, 20),
        'Ask 2: liquidity'
    );
    assert(
        approx_eq_pct(market_state.curr_sqrt_price, 404035472140796796041975907438, 20),
        'Swap 2: end sqrt price'
    );
    assert(market_state.curr_limit == 7906620 + 739787, 'Swap 2: end limit');
    assert(approx_eq(state_2.base_reserves, 0, 10), 'Swap 2: Base reserves');
    assert(approx_eq(state_2.quote_reserves, 0, 10), 'Swap 2: Quote reserves');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::UpdatePositions(
                        ReplicatingStrategy::UpdatePositions {
                            market_id,
                            bid_lower_limit: state_2.bid.lower_limit,
                            bid_upper_limit: state_2.bid.upper_limit,
                            bid_liquidity: state_2.bid.liquidity,
                            ask_lower_limit: state_2.ask.lower_limit,
                            ask_upper_limit: state_2.ask.upper_limit,
                            ask_liquidity: state_2.ask.liquidity,
                        }
                    )
                ),
            ]
        );
}

#[test]
fn test_update_positions_lvr_condition_not_met() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Update price.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166780000000, 8, 999, 5);

    // Deposit initial.
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let shares = strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price to within LVR rebalance threshold.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    start_warp(CheatTarget::One(oracle.contract_address), 1010);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 167300000000, 8, 1005, 5);

    let bid_before = strategy.bid(market_id);
    let ask_before = strategy.ask(market_id);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Swap buy and check positions not updated.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    let amount = to_e18(500000);
    market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()), Option::None(()));
    let mut bid_after = strategy.bid(market_id);
    let mut ask_after = strategy.ask(market_id);
    assert(bid_before == bid_after, 'LVR rebalance: bid 1');
    assert(ask_before == ask_after, 'LVR rebalance: ask 1');

    // Update price, swap sell and check positions unchanged.
    start_warp(CheatTarget::One(oracle.contract_address), 1020);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166400000000, 8, 1015, 5);
    market_manager
        .swap(market_id, false, amount, true, Option::None(()), Option::None(()), Option::None(()));
    bid_after = strategy.bid(market_id);
    ask_after = strategy.ask(market_id);
    assert(bid_before == bid_after, 'LVR rebalance: bid 2');
    assert(ask_before == ask_after, 'LVR rebalance: ask 2');

    // Check no events emitted.
    spy.fetch_events();
    assert(spy.events.len() == 0, 'Events');
}

#[test]
fn test_update_positions_zero_fee_crossing_spread_always_rebalances() {
    let (market_manager, base_token, quote_token, _, oracle, strategy) = before(true);

    // Create zero fee market.
    let mut params = default_market_params();
    params.width = 10;
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.swap_fee_rate = 0;
    params.start_limit = 7906620 + 741930; // initial limit
    params.strategy = strategy.contract_address;
    let market_id = create_market(market_manager, params);

    // Add market to strategy.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.add_market(market_id, owner(), 'ETH', 'USDC', 3, 600, 10, 20000, 200, true, false);

    // Update price.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166780000000, 8, 999, 5);

    // Deposit initial.
    let initial_base_amount = to_e18(1000);
    let initial_quote_amount = to_e18(1112520);
    let shares = strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    start_warp(CheatTarget::One(oracle.contract_address), 1010);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 165000000000, 8, 1005, 5);

    let bid_before = strategy.bid(market_id);
    let ask_before = strategy.ask(market_id);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Swap sell and check positions updated.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    market_manager
        .swap(
            market_id, false, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );

    // Run checks.
    let mut bid_after = strategy.bid(market_id);
    let mut ask_after = strategy.ask(market_id);
    assert(bid_before != bid_after, 'Rebalance: bid');
    assert(ask_before != ask_after, 'Rebalance: ask');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::UpdatePositions(
                        ReplicatingStrategy::UpdatePositions {
                            market_id,
                            bid_lower_limit: bid_after.lower_limit,
                            bid_upper_limit: bid_after.upper_limit,
                            bid_liquidity: bid_after.liquidity,
                            ask_lower_limit: ask_after.lower_limit,
                            ask_upper_limit: ask_after.upper_limit,
                            ask_liquidity: ask_after.liquidity,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_update_positions_not_crossing_spread_does_not_rebalance() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166780000000, 8, 999, 5);

    // Deposit initial.
    let initial_base_amount = to_e18(1000);
    let initial_quote_amount = to_e18(1112520);
    let shares = strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    start_warp(CheatTarget::One(oracle.contract_address), 1010);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 115000000000, 8, 1005, 5);

    let bid_before = strategy.bid(market_id);
    let ask_before = strategy.ask(market_id);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Swap buy and check positions not updated.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );
    let mut bid_after = strategy.bid(market_id);
    let mut ask_after = strategy.ask(market_id);
    assert(bid_before == bid_after, 'Rebalance: bid');
    assert(ask_before == ask_after, 'Rebalance: ask');

    // Check event not emitted.
    spy.fetch_events();
    assert(spy.events.len() == 0, 'Events');
}

#[test]
fn test_update_positions_oracle_price_unchanged() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166780000000, 8, 999, 5);

    // Deposit initial.
    let initial_base_amount = to_e18(1000);
    let initial_quote_amount = to_e18(1112520);
    let shares = strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    let bid_before = strategy.bid(market_id);
    let ask_before = strategy.ask(market_id);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Swap and check positions not updated.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );
    let mut bid_after = strategy.bid(market_id);
    let mut ask_after = strategy.ask(market_id);
    assert(bid_before == bid_after, 'Rebalance: bid');
    assert(ask_before == ask_after, 'Rebalance: ask');

    // Check event not emitted.
    spy.fetch_events();
    assert(spy.events.len() == 0, 'Events');
}

#[test]
#[should_panic(expected: ('OnlyMarketManager',))]
fn test_update_positions_not_market_manager() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let strategy_alt = IStrategyDispatcher { contract_address: strategy.contract_address };
    strategy_alt
        .update_positions(
            market_id,
            SwapParams {
                is_buy: true,
                amount: to_e18(1000),
                exact_input: true,
                threshold_sqrt_price: Option::None(()),
                deadline: Option::None(()),
            }
        );
}

#[test]
fn test_update_positions_market_not_initialised() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(false);

    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    let strategy_alt = IStrategyDispatcher { contract_address: strategy.contract_address };

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    strategy_alt
        .update_positions(
            market_id,
            SwapParams {
                is_buy: true,
                amount: to_e18(1000),
                exact_input: true,
                threshold_sqrt_price: Option::None(()),
                deadline: Option::None(()),
            }
        );

    // Check event not emitted.
    spy.fetch_events();
    assert(spy.events.len() == 0, 'Events');
}

#[test]
fn test_update_positions_market_paused() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Pause market.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.pause(market_id);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Update positions.
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    let strategy_alt = IStrategyDispatcher { contract_address: strategy.contract_address };
    strategy_alt
        .update_positions(
            market_id,
            SwapParams {
                is_buy: true,
                amount: to_e18(1000),
                exact_input: true,
                threshold_sqrt_price: Option::None(()),
                deadline: Option::None(()),
            }
        );

    // Check event not emitted.
    spy.fetch_events();
    assert(spy.events.len() == 0, 'Events');
}

#[test]
fn test_update_positions_num_sources_too_low() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Update price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166800000000, 8, 999, 5);

    // Deposit initial.
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let shares = strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price with sources below threshold.
    start_warp(CheatTarget::One(oracle.contract_address), 1010);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 70000000000, 8, 1005, 2);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Execute swap as strategy. 
    // This must be done to overcome a limitation with `prank` that causes tx to revert for a 
    // non-strategy caller.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    market_manager
        .swap(market_id, true, 1000, true, Option::None(()), Option::None(()), Option::None(()));

    // Check strategy paused and positions withdrawn.
    let state = strategy.strategy_state(market_id);
    assert(state.is_paused, 'Paused');
    assert(state.bid.liquidity == 0, 'Bid liquidity');
    assert(state.ask.liquidity == 0, 'Ask liquidity');

    // Check pause event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Pause(ReplicatingStrategy::Pause { market_id })
                )
            ]
        );
}

#[test]
fn test_update_positions_price_stale() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Update price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166800000000, 8, 999, 5);

    // Deposit initial.
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    start_prank(CheatTarget::One(oracle.contract_address), owner());
    let shares = strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price with price age above threshold.
    start_warp(CheatTarget::One(oracle.contract_address), 1600);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 70000000000, 8, 999, 2);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Execute swap as strategy. 
    // This must be done to overcome a limitation with `prank` that causes tx to revert for a 
    // non-strategy caller.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    market_manager
        .swap(market_id, true, 1000, true, Option::None(()), Option::None(()), Option::None(()));

    // Check strategy paused and positions withdrawn.
    let state = strategy.strategy_state(market_id);
    assert(state.is_paused, 'Paused');
    assert(state.bid.liquidity == 0, 'Bid liquidity');
    assert(state.ask.liquidity == 0, 'Ask liquidity');

    // Check pause event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Pause(ReplicatingStrategy::Pause { market_id })
                )
            ]
        );
}

#[test]
fn test_deposit_success() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Snapshot before.
    let bef = _snapshot_state(
        market_manager, strategy, market_id, base_token, quote_token, alice()
    );

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Deposit.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    let base_amount_req = to_e18(500);
    let quote_amount_req = to_e18(700000); // Contains extra, should be partially refunded
    let (base_amount, quote_amount, new_shares) = strategy
        .deposit(market_id, base_amount_req, quote_amount_req);

    // Snapshot after.
    let aft = _snapshot_state(
        market_manager, strategy, market_id, base_token, quote_token, alice()
    );
    let user_deposits = strategy.user_deposits(market_id, alice());
    let total_deposits = strategy.total_deposits(market_id);

    // Run checks.
    let base_exp = to_e18(500);
    let quote_exp = to_e18(556260);
    let bid_init_shares_exp = 286266946460287812818573174;
    let ask_init_shares_exp = 429406775392817428992841450;
    let bid_new_shares_exp = 143133473230143906409286;
    let ask_new_shares_exp = 214703387696408714496420;
    let total_shares_exp = bid_init_shares_exp
        + ask_init_shares_exp
        + bid_new_shares_exp
        + ask_new_shares_exp;
    assert(base_amount == base_exp, 'Base amount');
    assert(quote_amount == quote_exp, 'Quote amount');
    assert(
        approx_eq_pct(aft.strategy_state.bid.liquidity.into(), bid_init_shares_exp, 10),
        'Bid: liquidity'
    );
    assert(
        approx_eq_pct(aft.strategy_state.ask.liquidity.into(), ask_init_shares_exp, 10),
        'Ask: liquidity'
    );
    assert(approx_eq_pct(new_shares, bid_new_shares_exp + ask_new_shares_exp, 20), 'Shares');
    assert(
        approx_eq_pct(user_deposits, bid_new_shares_exp + ask_new_shares_exp, 20), 'User deposits'
    );
    assert(approx_eq_pct(total_deposits, total_shares_exp, 20), 'Total deposits');
    assert(aft.lp_base_bal == bef.lp_base_bal - base_exp, 'Alice base');
    assert(aft.lp_quote_bal == bef.lp_quote_bal - quote_exp, 'Alice quote');
    assert(aft.strategy_base_bal == bef.strategy_base_bal + base_exp, 'Strategy base');
    assert(aft.strategy_quote_bal == bef.strategy_quote_bal + quote_exp, 'Strategy quote');
    assert(bef.strategy_state.bid == aft.strategy_state.bid, 'Bid');
    assert(bef.strategy_state.ask == aft.strategy_state.ask, 'Ask');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Deposit(
                        ReplicatingStrategy::Deposit {
                            market_id, caller: alice(), base_amount, quote_amount,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_deposit_multiple() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Deposit once.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    let base_amount_req = to_e18(500);
    let quote_amount_req = to_e18(700000); // Contains extra, should be partially refunded
    strategy.deposit(market_id, base_amount_req, quote_amount_req);

    // Deposit again.
    strategy.deposit(market_id, base_amount_req, quote_amount_req);

    // Run checks.
    let market_state = market_manager.market_state(market_id);
    let state = strategy.strategy_state(market_id);

    let base_exp = to_e18(500);
    let quote_exp = to_e18(556260);
    let bid_init_shares_exp = 286266946460287812818573174;
    let ask_init_shares_exp = 429406775392817428992841450;
    let bid_new_shares_exp = 286266946460287812818572;
    let ask_new_shares_exp = 429406775392817428992840;
    let total_shares_exp = bid_init_shares_exp
        + ask_init_shares_exp
        + bid_new_shares_exp
        + ask_new_shares_exp;

    let user_shares = strategy.user_deposits(market_id, alice());
    let total_shares = strategy.total_deposits(market_id);
    assert(
        approx_eq_pct(user_shares, bid_new_shares_exp + ask_new_shares_exp, 20), 'Deposit: shares'
    );
    assert(approx_eq_pct(total_shares, total_shares_exp, 20), 'Deposit: total shares');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Deposit(
                        ReplicatingStrategy::Deposit {
                            market_id,
                            caller: alice(),
                            base_amount: base_exp,
                            quote_amount: quote_exp,
                        }
                    )
                ),
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Deposit(
                        ReplicatingStrategy::Deposit {
                            market_id,
                            caller: alice(),
                            base_amount: base_exp,
                            quote_amount: quote_exp,
                        }
                    )
                ),
            ]
        );
}

#[test]
fn test_deposit_single_sided_bid_liquidity() {
    // The portfolio could become entirely skewed in one asset due to price movements. In this case,
    // single-sided liquidity deposits should be handled gracefully.
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit_initial(market_id, 1000, to_e18(1000));

    // Place position above current one.
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, 7906620 + 765000, 7906620 + 766000, I128Trait::new(to_e18_u128(1000), false)
        );

    // Execute buy as strategy. Update positions to concentrate liquidity entirely in bid.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    market_manager
        .swap(
            market_id,
            true,
            to_e18(1000),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

    // Update oracle price and swap to trigger position update, setting ask liquidity to 0.
    start_warp(CheatTarget::One(oracle.contract_address), 1010);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 220000000000, 8, 1005, 5);
    market_manager
        .swap(
            market_id,
            true,
            to_e18(1000),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );
    let state = strategy.strategy_state(market_id);
    assert(state.ask.liquidity == 0, 'Ask: liquidity');

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Deposit single-sided bid liquidity.
    let position_id = id::position_id(
        market_id, strategy.contract_address.into(), state.bid.lower_limit, state.bid.upper_limit
    );
    let (_, quote_amount) = market_manager.amounts_inside_position(position_id);
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit(market_id, 0, quote_amount);

    // Run checks.
    let alice_shares = strategy.user_deposits(market_id, alice());
    let total_shares = strategy.total_deposits(market_id);
    assert(alice_shares == total_shares / 2, 'Deposit: shares');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Deposit(
                        ReplicatingStrategy::Deposit {
                            market_id, caller: alice(), base_amount: 0, quote_amount,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_deposit_single_sided_ask_liquidity() {
    // The portfolio could become entirely skewed in one asset due to price movements. In this case,
    // single-sided liquidity deposits should be handled gracefully.
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit_initial(market_id, to_e18(1), 10);

    // Place poosition below current one.
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, 7906620 + 725000, 7906620 + 735000, I128Trait::new(to_e18_u128(1000), false)
        );

    // Buy and update positions to concentrate liquidity entirely in bid.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    market_manager
        .swap(
            market_id,
            false,
            to_e18(100),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

    // Update oracle price and swap to trigger position update, setting ask liquidity to 0.
    start_warp(CheatTarget::One(oracle.contract_address), 1010);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 100000000000, 8, 1005, 5);
    market_manager
        .swap(
            market_id,
            false,
            to_e18(100),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );
    let state = strategy.strategy_state(market_id);
    assert(state.bid.liquidity == 0, 'Bid: liquidity');

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Deposit single-sided bid liquidity.
    let position_id = id::position_id(
        market_id, strategy.contract_address.into(), state.ask.lower_limit, state.ask.upper_limit
    );
    let (base_amount, quote_amount) = market_manager.amounts_inside_position(position_id);
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit(market_id, base_amount, 0);

    // Run checks.
    let alice_shares = strategy.user_deposits(market_id, alice());
    let total_shares = strategy.total_deposits(market_id);
    assert(alice_shares == total_shares / 2, 'Deposit: shares');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Deposit(
                        ReplicatingStrategy::Deposit {
                            market_id, caller: alice(), base_amount, quote_amount: 0,
                        }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: ('AmountZero',))]
fn test_deposit_base_and_quote_zero() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit_initial(market_id, 1000, 1000);

    // Deposit should revert.
    strategy.deposit(market_id, 0, 0);
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_deposit_not_approved() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial should revert if deposits disabled.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit_initial(market_id, to_e18(1000000), to_e18(1112520000));

    // Set allowance to 0.
    start_prank(CheatTarget::One(base_token.contract_address), owner());
    base_token.approve(strategy.contract_address, 0);
    start_prank(CheatTarget::One(quote_token.contract_address), owner());
    quote_token.approve(strategy.contract_address, 0);

    strategy.deposit(market_id, to_e18(1000000), to_e18(1112520000));
}

#[test]
#[should_panic(expected: ('UseDepositInitial',))]
fn test_deposit_market_null() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit(1, to_e18(10), to_e18(12500));
}

#[test]
#[should_panic(expected: ('UseDepositInitial',))]
fn test_deposit_no_deposits() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit(market_id, to_e18(500), to_e18(700000));
}

#[test]
#[should_panic(expected: ('UseDepositInitial',))]
fn test_deposit_user_not_whitelisted() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Enable whitelist.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.use_whitelist = true;
    strategy.set_params(market_id, params);

    // Deposit.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit(market_id, to_e18(500), to_e18(700000));
}

#[test]
#[should_panic(expected: ('Paused',))]
fn test_deposit_paused() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit_initial(market_id, to_e18(1000000), to_e18(1112520000));

    // Pause strategy.
    strategy.pause(market_id);

    // Deposit.
    strategy.deposit(market_id, to_e18(1000000), to_e18(1112520000));
}

#[test]
#[should_panic(expected: ('UseDepositInitial',))]
fn test_deposit_market_not_initialised() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(false);

    // Deposit should revert if market not initialised.
    strategy.deposit(market_id, to_e18(1000000), to_e18(1112520000));
}

#[test]
#[should_panic(expected: ('DepositDisabled',))]
fn test_deposit_deposit_disabled() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit_initial(market_id, to_e18(1000000), to_e18(1112520000));

    // Disable deposits.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.allow_deposits = false;
    strategy.set_params(market_id, params);

    // Deposit should revert if deposits disabled.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit(market_id, to_e18(1000000), to_e18(1112520000));
}

#[test]
fn test_deposit_deposit_disabled_strategy_owner() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit_initial(market_id, to_e18(1000), to_e18(1250000));

    // Disable deposits.
    let mut params = strategy.strategy_params(market_id);
    params.allow_deposits = false;
    strategy.set_params(market_id, params);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Deposit should work if owner is depositing.
    let (base_amount, quote_amount, _) = strategy.deposit(market_id, to_e18(1), to_e18(1250));

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Deposit(
                        ReplicatingStrategy::Deposit {
                            market_id, caller: owner(), base_amount, quote_amount,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_get_balances() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Remove protocol fee for easier accounting.
    start_prank(CheatTarget::One(market_manager.contract_address), owner());
    market_manager.set_protocol_share(market_id, 0);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5); // 1668.78

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    let base_deposit = to_e18(1000);
    let quote_deposit = to_e18(1668780);
    strategy.deposit_initial(market_id, base_deposit, quote_deposit);

    // Swap buy to accrue fees. 
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    let buy_amount = to_e18(2000);
    let (amount_in_1, amount_out_1, _) = market_manager
        .swap(
            market_id,
            true,
            to_e18(2000),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

    // Swap sell to accrue fees in ask position.
    let sell_amount = to_e18(1);
    let (amount_in_2, amount_out_2, _) = market_manager
        .swap(
            market_id, false, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );

    // Run checks.
    let base_amount_exp = base_deposit + amount_in_2 - amount_out_1;
    let quote_amount_exp = quote_deposit + amount_in_1 - amount_out_2;

    // Deposit more tokens.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.deposit(market_id, base_amount_exp, quote_amount_exp);

    // Get balances.
    let (base_amount, quote_amount) = strategy.get_balances(market_id);
    assert(approx_eq(base_amount, base_amount_exp * 2, 10), 'Base amount');
    assert(approx_eq(quote_amount, quote_amount_exp * 2, 10), 'Quote amount');
}

#[test]
fn test_withdraw_all() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let shares_init = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Execute swap sell.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    let amount = to_e18(5000);
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, false, amount, true, Option::None(()), Option::None(()), Option::None(()));

    // Snapshot before.
    let bef = _snapshot_state(
        market_manager, strategy, market_id, base_token, quote_token, owner()
    );

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Withdraw from strategy.
    let mut user_deposits = strategy.user_deposits(market_id, owner());
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let (base_amount, quote_amount) = strategy.withdraw(market_id, user_deposits);

    // Snapshot after.
    let aft = _snapshot_state(
        market_manager, strategy, market_id, base_token, quote_token, owner()
    );
    user_deposits = strategy.user_deposits(market_id, owner());
    let total_deposits = strategy.total_deposits(market_id);

    // Run checks.
    assert(amount_in == amount, 'Amount in');
    assert(approx_eq_pct(amount_out, 8308093186237340625293077, 20), 'Amount out');
    assert(fees == to_e18(15), 'Fees');
    let protocol_fee = fee_math::calc_fee(fees, aft.market_state.protocol_share);
    assert(
        approx_eq_pct(aft.lp_base_bal, bef.lp_base_bal + bef.market_base_bal - protocol_fee, 20),
        'LP base'
    );
    assert(
        approx_eq_pct(aft.lp_quote_bal, bef.lp_quote_bal + bef.market_quote_bal, 20), 'LP quote'
    );
    assert(approx_eq_pct(aft.strategy_base_bal, bef.strategy_base_bal, 20), 'Strategy base');
    assert(approx_eq_pct(aft.strategy_quote_bal, bef.strategy_quote_bal, 20), 'Strategy quote');
    assert(approx_eq_pct(aft.market_base_bal, protocol_fee, 10), 'Market base');
    assert(approx_eq(aft.market_quote_bal, 0, 10), 'Market quote');
    assert(
        approx_eq_pct(
            (aft.strategy_state.bid.liquidity + aft.strategy_state.ask.liquidity).into(), 0, 20
        ),
        'Liquidity'
    );
    assert(approx_eq_pct(base_amount, 1004999970000000000000000, 20), 'Base amount');
    assert(approx_eq_pct(quote_amount, 1104211906813762659374706922, 20), 'Quote amount');
    assert(approx_eq(aft.strategy_state.base_reserves, 0, 10), 'Base reserves');
    assert(approx_eq(aft.strategy_state.quote_reserves, 0, 10), 'Quote reserves');
    assert(approx_eq(user_deposits, 0, 10), 'User shares');
    assert(approx_eq(total_deposits, 0, 10), 'Total shares');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Withdraw(
                        ReplicatingStrategy::Withdraw {
                            market_id, caller: owner(), base_amount, quote_amount,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_withdraw_partial() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let shares_init = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Execute swap sell as strategy. 
    // This must be done to overcome a limitation with `prank` that causes tx to revert for a 
    // non-strategy caller.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    let amount = to_e18(5000);
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, false, amount, true, Option::None(()), Option::None(()), Option::None(()));

    // Snapshot before.
    let bef = _snapshot_state(
        market_manager, strategy, market_id, base_token, quote_token, owner()
    );

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Withdraw partial from strategy.
    let shares_init = 286266946460287812818573174 + 429406775392817428992841450;
    let shares_req = shares_init / 2;
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let (base_amount, quote_amount) = strategy.withdraw(market_id, shares_req);

    // Snapshot after.
    let aft = _snapshot_state(
        market_manager, strategy, market_id, base_token, quote_token, owner()
    );
    let user_deposits = strategy.user_deposits(market_id, owner());
    let total_deposits = strategy.total_deposits(market_id);

    // Run checks.
    assert(amount_in == amount, 'Amount in');
    assert(approx_eq_pct(amount_out, 8308093186237340625293077, 20), 'Amount out');
    assert(fees == to_e18(15), 'Fees');
    let protocol_fee = fee_math::calc_fee(fees, aft.market_state.protocol_share);
    // Removed liquidity includes entire fee balance. Withdrawn balance should allocate fees pro-rata.
    let base_remove = (bef.market_base_bal - protocol_fee) / 2;
    let quote_remove = bef.market_quote_bal / 2;
    let base_withdraw = base_remove + (fees - protocol_fee) / 2;
    let quote_withdraw = quote_remove;
    assert(approx_eq_pct(aft.lp_base_bal, bef.lp_base_bal + base_remove, 20), 'LP base');
    assert(approx_eq_pct(aft.lp_quote_bal, bef.lp_quote_bal + quote_remove, 20), 'LP quote');
    assert(
        approx_eq_pct(
            aft.strategy_base_bal, bef.strategy_base_bal + base_withdraw - base_remove, 20
        ),
        'Strategy base'
    );
    assert(
        approx_eq_pct(
            aft.strategy_quote_bal, bef.strategy_quote_bal + quote_withdraw - quote_remove, 20
        ),
        'Strategy quote'
    );
    assert(
        approx_eq_pct(aft.market_base_bal, bef.market_base_bal - base_withdraw, 10), 'Market base'
    );
    assert(
        approx_eq(aft.market_quote_bal, bef.market_quote_bal - quote_withdraw, 10), 'Market quote'
    );
    assert(
        approx_eq_pct(
            (aft.strategy_state.bid.liquidity + aft.strategy_state.ask.liquidity).into(),
            shares_req,
            20
        ),
        'Liquidity'
    );
    assert(approx_eq_pct(base_amount, 502499985000000000000000, 20), 'Withdraw: base amount');
    assert(approx_eq_pct(quote_amount, 552105953406881329687353461, 20), 'Withdraw: quote amount');
    assert(
        approx_eq_pct(aft.strategy_state.bid.liquidity.into(), 143133473230143906409286587, 20),
        'Bid liquidity'
    );
    assert(
        approx_eq_pct(aft.strategy_state.ask.liquidity.into(), 214703387696408714496420725, 20),
        'Ask liquidity'
    );
    assert(
        approx_eq(aft.strategy_state.base_reserves, 7485000000000000000, 10),
        'Withdraw: base reserves'
    );
    assert(approx_eq(aft.strategy_state.quote_reserves, 0, 10), 'Withdraw: quote reserves');
    assert(approx_eq_pct(user_deposits, shares_init - shares_req, 20), 'Withdraw: user shares');
    assert(approx_eq_pct(total_deposits, shares_init - shares_req, 20), 'Withdraw: total shares');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Withdraw(
                        ReplicatingStrategy::Withdraw {
                            market_id, caller: owner(), base_amount, quote_amount,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_withdraw_single_sided_liquidity() {
    // The portfolio could become entirely skewed in one asset due to price movements. In this case,
    // single-sided liquidity deposits should be handled gracefully.
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let base_initial = 1000;
    let quote_initial = to_e18(1000);
    let shares = strategy.deposit_initial(market_id, base_initial, quote_initial);

    // Place position above current one.
    start_prank(CheatTarget::One(market_manager.contract_address), alice());
    market_manager
        .modify_position(
            market_id, 7906620 + 765000, 7906620 + 766000, I128Trait::new(to_e18_u128(1000), false)
        );

    // Execute buy as strategy. Update positions to concentrate liquidity entirely in bid.
    start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
    start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
    let (amount_in, amount_out, fees) = market_manager
        .swap(
            market_id,
            true,
            to_e18(1000),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );

    // Update oracle price and swap to trigger position update, setting ask liquidity to 0.
    start_warp(CheatTarget::One(oracle.contract_address), 1010);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 220000000000, 8, 1005, 5);
    market_manager
        .swap(
            market_id,
            true,
            to_e18(1000),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );
    let state = strategy.strategy_state(market_id);
    assert(state.ask.liquidity == 0, 'Ask: liquidity');

    // Snapshot before.
    let bef = _snapshot_state(
        market_manager, strategy, market_id, base_token, quote_token, owner()
    );

    // Withdraw single-sided bid liquidity.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let (base_amount, quote_amount) = strategy.withdraw(market_id, shares);

    // Snapshot after.
    let aft = _snapshot_state(
        market_manager, strategy, market_id, base_token, quote_token, owner()
    );
    let owner_shares = strategy.user_deposits(market_id, owner());
    let total_shares = strategy.total_deposits(market_id);

    // Run checks.
    assert(owner_shares == 0, 'Owner shares');
    assert(total_shares == 0, 'Total shares');
    assert(base_amount == 0, 'Base amount');
    assert(quote_amount != 0, 'Quote amount');
    assert(approx_eq(aft.lp_base_bal, bef.lp_base_bal + base_amount, 10), 'LP base');
    assert(approx_eq(aft.lp_quote_bal, bef.lp_quote_bal + quote_amount, 10), 'LP quote');
    assert(approx_eq(aft.strategy_base_bal, bef.strategy_base_bal, 10), 'Strategy base');
    assert(approx_eq(aft.strategy_quote_bal, bef.strategy_quote_bal, 10), 'Strategy quote');
    assert(approx_eq(aft.market_base_bal, bef.market_base_bal - base_amount, 10), 'Market base');
    assert(
        approx_eq_pct(aft.market_quote_bal, bef.market_quote_bal - quote_amount, 20), 'Market quote'
    );
    assert(approx_eq(aft.strategy_state.base_reserves, 0, 10), 'Base reserves');
    assert(approx_eq(aft.strategy_state.quote_reserves, 0, 10), 'Quote reserves');
    assert(approx_eq(aft.strategy_state.bid.liquidity.into(), 0, 10), 'Bid liquidity');
    assert(approx_eq(aft.strategy_state.ask.liquidity.into(), 0, 10), 'Ask liquidity');
}

#[test]
fn test_withdraw_user_removed_from_whitelist() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Enable whitelist.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.use_whitelist = true;
    strategy.set_params(market_id, params);

    // Whitelist user.
    strategy.set_whitelist(owner(), true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let shares = strategy.deposit_initial(market_id, to_e18(1000), to_e18(1125000));

    // Remove user from whitelist.
    strategy.set_whitelist(owner(), false);

    // Should be able to withdraw.
    strategy.withdraw(market_id, shares);
}

#[test]
#[should_panic(expected: ('InsuffShares',))]
fn test_withdraw_market_null() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.withdraw(1, 1000);
}

#[test]
#[should_panic(expected: ('InsuffShares',))]
fn test_withdraw_strategy_not_initialised() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(false);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.withdraw(1, 1000);
}

#[test]
#[should_panic(expected: ('SharesZero',))]
fn test_withdraw_shares_zero() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit_initial(market_id, 1000, 1000);

    // Withdraw.
    strategy.withdraw(market_id, 0);
}

#[test]
#[should_panic(expected: ('InsuffShares',))]
fn test_withdraw_more_than_available() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    let shares = strategy.deposit_initial(market_id, 1000, 1000);

    // Withdraw.
    strategy.withdraw(market_id, shares + 1);
}

#[test]
#[should_panic(expected: ('InsuffShares',))]
fn test_withdraw_more_than_owned() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let shares = strategy.deposit_initial(market_id, 1000, 1000);

    // Other LP deposits.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit(market_id, 1000, 1000);

    // Withdraw.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.withdraw(market_id, shares + 1);
}

#[test]
fn test_withdraw_allowed_if_paused() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let shares = strategy.deposit_initial(market_id, to_e18(1000000), to_e18(1112520000));

    // Pause strategy.
    strategy.pause(market_id);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Withdraw.
    let (base_amount, quote_amount) = strategy.withdraw(market_id, shares);

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Withdraw(
                        ReplicatingStrategy::Withdraw {
                            market_id, caller: owner(), base_amount, quote_amount,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_withdraw_fees() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Enable withdraw fee.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let withdraw_fee_rate = 30;
    strategy.set_withdraw_fee(market_id, withdraw_fee_rate);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let base_deposit = to_e18(1000000);
    let quote_deposit = to_e18(1112520000);
    let shares = strategy.deposit_initial(market_id, base_deposit, quote_deposit);

    // Withdraw.
    let (base_amount, quote_amount) = strategy.withdraw(market_id, shares);
    let base_fees_exp = fee_math::calc_fee(base_deposit, withdraw_fee_rate);
    let quote_fees_exp = fee_math::calc_fee(quote_deposit, withdraw_fee_rate);
    let base_amount_exp = base_deposit - base_fees_exp;
    let quote_amount_exp = quote_deposit - quote_fees_exp;

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Collect fees.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let base_fees = strategy
        .collect_withdraw_fees(owner(), base_token.contract_address, base_fees_exp);
    let quote_fees = strategy
        .collect_withdraw_fees(owner(), quote_token.contract_address, quote_fees_exp);

    // Run checks.
    assert(approx_eq_pct(base_amount, base_amount_exp, 20), 'Base amount');
    assert(approx_eq_pct(quote_amount, quote_amount_exp, 20), 'Quote amount');
    assert(approx_eq_pct(base_fees, base_fees_exp, 20), 'Base fees');
    assert(approx_eq_pct(quote_fees, quote_fees_exp, 20), 'Quote fees');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::CollectWithdrawFee(
                        ReplicatingStrategy::CollectWithdrawFee {
                            receiver: owner(),
                            token: base_token.contract_address,
                            amount: base_fees,
                        }
                    )
                ),
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::CollectWithdrawFee(
                        ReplicatingStrategy::CollectWithdrawFee {
                            receiver: owner(),
                            token: quote_token.contract_address,
                            amount: quote_fees,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_set_withdraw_fee() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Set withdraw fee.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let withdraw_fee_rate = 30;
    strategy.set_withdraw_fee(market_id, withdraw_fee_rate);

    // Run checks.
    let fee_rate = strategy.withdraw_fee_rate(market_id);
    assert(fee_rate == withdraw_fee_rate, 'Withdraw fee rate');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::SetWithdrawFee(
                        ReplicatingStrategy::SetWithdrawFee { market_id, fee_rate, }
                    )
                )
            ]
        );
}


#[test]
#[should_panic(expected: ('FeeOF',))]
fn test_set_withdraw_fee_overflow() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set withdraw fee.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let withdraw_fee_rate = 10001;
    strategy.set_withdraw_fee(market_id, withdraw_fee_rate);
}

#[test]
#[should_panic(expected: ('FeeUnchanged',))]
fn test_set_withdraw_fee_unchanged() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set withdraw fee.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let withdraw_fee_rate = strategy.withdraw_fee_rate(market_id);
    strategy.set_withdraw_fee(market_id, withdraw_fee_rate);
}

#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_set_withdraw_fee_not_owner() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set withdraw fee.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.set_withdraw_fee(market_id, 50);
}


#[test]
fn test_collect_and_pause() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 100100000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = 1000000;
    let initial_quote_amount = 1000000;
    let shares_init = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Collect and pause.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.collect_and_pause(market_id);
    let market_state = market_manager.market_state(market_id);
    let state = strategy.strategy_state(market_id);

    // Run checks.
    assert(market_state.liquidity == 0, 'Collect pause: mkt liquidity');
    assert(state.bid.liquidity == 0, 'Collect pause: bid liquidity');
    assert(state.ask.liquidity == 0, 'Collect pause: ask liquidity');
    assert(approx_eq(state.base_reserves, initial_base_amount, 10), 'Collect pause: base reserves');
    assert(
        approx_eq(state.quote_reserves, initial_quote_amount, 10), 'Collect pause: quote reserves'
    );

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Pause(ReplicatingStrategy::Pause { market_id })
                )
            ]
        );
}

#[test]
fn test_disable_deposits() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = 1000000;
    let initial_quote_amount = 1000000;
    let shares_init = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Disable deposits.
    let mut params = strategy.strategy_params(market_id);
    params.allow_deposits = false;
    strategy.set_params(market_id, params);

    // Run checks.
    params = strategy.strategy_params(market_id);
    assert(!params.allow_deposits, 'Disable deposits');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::SetStrategyParams(
                        ReplicatingStrategy::SetStrategyParams {
                            market_id,
                            min_spread: params.min_spread,
                            range: params.range,
                            max_delta: params.max_delta,
                            allow_deposits: false,
                            use_whitelist: false,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_reenable_deposits() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = 1000000;
    let initial_quote_amount = 1000000;
    let shares_init = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Disable deposits.
    let mut params = strategy.strategy_params(market_id);
    params.allow_deposits = false;
    strategy.set_params(market_id, params);

    // Reenable deposits.
    params.allow_deposits = true;
    strategy.set_params(market_id, params);

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::SetStrategyParams(
                        ReplicatingStrategy::SetStrategyParams {
                            market_id,
                            min_spread: params.min_spread,
                            range: params.range,
                            max_delta: params.max_delta,
                            allow_deposits: false,
                            use_whitelist: params.use_whitelist,
                        }
                    )
                ),
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::SetStrategyParams(
                        ReplicatingStrategy::SetStrategyParams {
                            market_id,
                            min_spread: params.min_spread,
                            range: params.range,
                            max_delta: params.max_delta,
                            allow_deposits: true,
                            use_whitelist: params.use_whitelist,
                        }
                    )
                ),
            ]
        );

    // Deposit.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit(market_id, to_e18(500), to_e18(700000));
}

#[test]
fn test_disable_deposit_strategy_owner_deposit() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = 1000000;
    let initial_quote_amount = 1000000;
    let shares_init = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Disable deposits.
    let mut params = strategy.strategy_params(market_id);
    params.allow_deposits = false;
    strategy.set_params(market_id, params);

    // Deposit should be allowed.
    let (base_amount, quote_amount, _) = strategy.deposit(market_id, to_e18(500), to_e18(700000));

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Deposit(
                        ReplicatingStrategy::Deposit {
                            market_id, caller: owner(), base_amount, quote_amount,
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_set_strategy_params() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Update params.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let params = StrategyParams {
        min_spread: 0, range: 3000, max_delta: 0, allow_deposits: false, use_whitelist: true,
    };
    strategy.set_params(market_id, params);

    // Run checks.
    let params = strategy.strategy_params(market_id);
    assert(params.min_spread == 0, 'Set params: min spread');
    assert(params.range == 3000, 'Set params: range');
    assert(params.max_delta == 0, 'Set params: max delta');
    assert(!params.allow_deposits, 'Set params: allow deposits');
    assert(params.use_whitelist, 'Set params: use whitelist');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::SetStrategyParams(
                        ReplicatingStrategy::SetStrategyParams {
                            market_id,
                            min_spread: 0,
                            range: 3000,
                            max_delta: 0,
                            allow_deposits: false,
                            use_whitelist: true,
                        }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: ('OnlyStrategyOwner',))]
fn test_set_strategy_params_not_strategy_owner() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), alice());
    let mut params = strategy.strategy_params(market_id);
    params.range = 3000;
    strategy.set_params(market_id, params);
}

#[test]
#[should_panic(expected: ('ParamsUnchanged',))]
fn test_set_strategy_params_unchanged() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let params = strategy.strategy_params(market_id);
    strategy.set_params(market_id, params);
}

#[test]
#[should_panic(expected: ('RangeZero',))]
fn test_set_strategy_params_zero_range() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.range = 0;
    strategy.set_params(market_id, params);
}

#[test]
fn test_whitelist_user() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Enable whitelist.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.use_whitelist = true;
    strategy.set_params(market_id, params);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Whitelist user.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.set_whitelist(alice(), true);

    // Deposit initial should be allowed.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.deposit_initial(market_id, 1000, 1000);

    // Run checks.
    let is_whitelisted = strategy.is_whitelisted(alice());
    assert(is_whitelisted, 'Whitelist user');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::SetWhitelist(
                        ReplicatingStrategy::SetWhitelist { user: alice(), enable: true }
                    )
                )
            ]
        );
}

#[test]
fn test_remove_user_from_whitelist() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Enable whitelist.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.use_whitelist = true;
    strategy.set_params(market_id, params);

    // Whitelist user.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.set_whitelist(alice(), true);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Remove user from whitelist.
    strategy.set_whitelist(alice(), false);

    // Run checks.
    let is_whitelisted = strategy.is_whitelisted(alice());
    assert(!is_whitelisted, 'Remove Whitelist');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::SetWhitelist(
                        ReplicatingStrategy::SetWhitelist { user: alice(), enable: false }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: ('AlreadyWhitelisted',))]
fn test_whitelist_already_whitelisted_user() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Enable whitelist.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.use_whitelist = true;
    strategy.set_params(market_id, params);

    // Whitelist user.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.set_whitelist(alice(), true);
    strategy.set_whitelist(alice(), true);
}

#[test]
#[should_panic(expected: ('NotWhitelisted',))]
fn test_remove_non_whitelisted_user() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Enable whitelist.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let mut params = strategy.strategy_params(market_id);
    params.use_whitelist = true;
    strategy.set_params(market_id, params);

    strategy.set_whitelist(alice(), false);
}

#[test]
fn test_change_oracle() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Update oracle and oracle summary.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let new_oracle = contract_address_const::<0x123>();
    let new_oracle_summary = contract_address_const::<0x456>();
    strategy.change_oracle(new_oracle, new_oracle_summary);

    // Run checks.
    let oracle = strategy.oracle();
    let oracle_summary = strategy.oracle_summary();
    assert(oracle == new_oracle, 'Change oracle: oracle');
    assert(oracle_summary == new_oracle_summary, 'Change oracle: oracle summary');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::ChangeOracle(
                        ReplicatingStrategy::ChangeOracle {
                            oracle: new_oracle, oracle_summary: new_oracle_summary,
                        }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_change_oracle_not_owner() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), alice());
    let oracle = contract_address_const::<0x123>();
    let oracle_summary = contract_address_const::<0x456>();
    strategy.change_oracle(oracle, oracle_summary);
}

#[test]
#[should_panic(expected: ('OracleUnchanged',))]
fn test_change_oracle_unchanged() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let oracle = strategy.oracle();
    let oracle_summary = strategy.oracle_summary();
    strategy.change_oracle(oracle, oracle_summary);
}

#[test]
fn test_transfer_and_accept_owner() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.transfer_owner(alice());
    assert(strategy.owner() == owner(), 'Transfer owner: owner');

    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.accept_owner();
    assert(strategy.owner() == alice(), 'Accept owner: owner');
    assert(
        strategy.queued_owner() == contract_address_const::<0x0>(), 'Accept owner: queued owner'
    );

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::ChangeOwner(
                        ReplicatingStrategy::ChangeOwner { old: owner(), new: alice(), }
                    )
                )
            ]
        );
}

#[test]
fn test_transfer_then_update_owner_before_accepting() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Transfer owner.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.transfer_owner(alice());

    // Transfer again.
    strategy.transfer_owner(bob());
    assert(strategy.owner() == owner(), 'Transfer owner: owner');
    assert(strategy.queued_owner() == bob(), 'Transfer owner: queued owner');

    // Accept owner.
    start_prank(CheatTarget::One(strategy.contract_address), bob());
    strategy.accept_owner();
    assert(strategy.owner() == bob(), 'Accept owner: owner');
    assert(
        strategy.queued_owner() == contract_address_const::<0x0>(), 'Accept owner: queued owner'
    );

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::ChangeOwner(
                        ReplicatingStrategy::ChangeOwner { old: owner(), new: bob(), }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: ('OnlyOwner',))]
fn test_transfer_owner_not_owner() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.transfer_owner(alice());
}

#[test]
#[should_panic(expected: ('OnlyNewOwner',))]
fn test_accept_owner_not_transferred() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.accept_owner();
}

#[test]
fn test_transfer_and_accept_strategy_owner() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Transfer owner.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.transfer_strategy_owner(market_id, alice());
    assert(strategy.strategy_owner(market_id) == owner(), 'Transfer owner: owner');

    // Accept owner.
    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.accept_strategy_owner(market_id);
    assert(strategy.strategy_owner(market_id) == alice(), 'Accept owner: owner');
    assert(
        strategy.queued_strategy_owner(market_id) == contract_address_const::<0x0>(),
        'Accept owner: queued owner'
    );

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::ChangeStrategyOwner(
                        ReplicatingStrategy::ChangeStrategyOwner {
                            market_id, old: owner(), new: alice(),
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_transfer_then_update_strategy_owner_before_accepting() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Transfer owner.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.transfer_strategy_owner(market_id, alice());

    // Transfer again.
    strategy.transfer_strategy_owner(market_id, bob());
    assert(strategy.strategy_owner(market_id) == owner(), 'Transfer owner: owner');
    assert(strategy.queued_strategy_owner(market_id) == bob(), 'Transfer owner: queued owner');

    // Accept owner.
    start_prank(CheatTarget::One(strategy.contract_address), bob());
    strategy.accept_strategy_owner(market_id);

    // Run checks.
    assert(strategy.strategy_owner(market_id) == bob(), 'Accept owner: owner');
    assert(
        strategy.queued_strategy_owner(market_id) == contract_address_const::<0x0>(),
        'Accept owner: queued owner'
    );

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::ChangeStrategyOwner(
                        ReplicatingStrategy::ChangeStrategyOwner {
                            market_id, old: owner(), new: bob(),
                        }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: ('OnlyStrategyOwner',))]
fn test_transfer_strategy_owner_not_owner() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.transfer_strategy_owner(market_id, alice());
}

#[test]
#[should_panic(expected: ('OnlyNewOwner',))]
fn test_accept_strategy_owner_not_transferred() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), alice());
    strategy.accept_strategy_owner(market_id);
}

#[test]
fn test_pause() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Pause strategy.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.pause(market_id);

    // Run checks.
    assert(strategy.is_paused(market_id), 'Paused');
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Pause(ReplicatingStrategy::Pause { market_id })
                )
            ]
        );
}

#[test]
#[should_panic(expected: ('AlreadyPaused',))]
fn test_pause_already_paused() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.pause(market_id);
    strategy.pause(market_id);
}

#[test]
fn test_unpause() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Pause strategy.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.pause(market_id);

    // Log events.
    let mut spy = spy_events(SpyOn::One(strategy.contract_address));

    // Unpause strategy.
    strategy.unpause(market_id);
    assert(!strategy.is_paused(market_id), 'Unpaused');

    // Check event emitted.
    spy
        .assert_emitted(
            @array![
                (
                    strategy.contract_address,
                    ReplicatingStrategy::Event::Unpause(ReplicatingStrategy::Unpause { market_id })
                )
            ]
        );
}

#[test]
#[should_panic(expected: ('AlreadyUnpaused',))]
fn test_pause_already_unpaused() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    start_prank(CheatTarget::One(strategy.contract_address), owner());
    strategy.unpause(market_id);
}

fn swap_test_cases(width: u32) -> Array<SwapCase> {
    let mut cases: Array<SwapCase> = array![
        // Large amounts with no price limit.
        SwapCase {
            is_buy: false,
            exact_input: true,
            amount: to_e18(10),
            threshold_sqrt_price: Option::None(()),
        },
        SwapCase {
            is_buy: true,
            exact_input: true,
            amount: to_e18(1),
            threshold_sqrt_price: Option::None(()),
        },
        SwapCase {
            is_buy: false,
            exact_input: false,
            amount: to_e18(1),
            threshold_sqrt_price: Option::None(())
        },
        SwapCase {
            is_buy: true,
            exact_input: false,
            amount: to_e18(10),
            threshold_sqrt_price: Option::None(())
        },
        // Small amounts with no price limit.
        SwapCase {
            is_buy: false, exact_input: true, amount: 100000, threshold_sqrt_price: Option::None(())
        },
        SwapCase {
            is_buy: true, exact_input: true, amount: 100000, threshold_sqrt_price: Option::None(())
        },
        SwapCase {
            is_buy: false,
            exact_input: false,
            amount: 100000,
            threshold_sqrt_price: Option::None(())
        },
        SwapCase {
            is_buy: true, exact_input: false, amount: 100000, threshold_sqrt_price: Option::None(())
        },
        // Large amount.
        SwapCase {
            is_buy: true,
            exact_input: true,
            amount: to_e18(100000),
            threshold_sqrt_price: Option::Some(
                price_math::limit_to_sqrt_price(7906620 + 760000, width)
            )
        },
        SwapCase {
            is_buy: false,
            exact_input: true,
            amount: to_e18(1000000000),
            threshold_sqrt_price: Option::Some(
                price_math::limit_to_sqrt_price(7906620 + 734000, width)
            )
        },
        SwapCase {
            is_buy: true,
            exact_input: false,
            amount: to_e18(1000000000),
            threshold_sqrt_price: Option::Some(
                price_math::limit_to_sqrt_price(7906620 + 760000, width)
            )
        },
        SwapCase {
            is_buy: false,
            exact_input: false,
            amount: to_e18(1000000000),
            threshold_sqrt_price: Option::Some(
                price_math::limit_to_sqrt_price(7906620 + 734000, width)
            )
        },
    ];

    cases
}

fn oracle_prices() -> Array<u128> {
    let prices: Array<u128> = array![
        166878000000,
        164025000000,
        112500000000,
        172500000000,
        172500000000,
        174500000000,
        172800000000,
        172800000000,
        172800000000,
        172800000000,
        172800000000,
        172800000000,
    ];
    prices
}

#[test]
fn test_swap_cases() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before(true);

    // Set oracle price.
    start_warp(CheatTarget::One(oracle.contract_address), 1000);
    oracle.set_data_with_USD_hop('ETH', 'USDC', 166878000000, 8, 999, 5);

    // Deposit initial.
    start_prank(CheatTarget::One(strategy.contract_address), owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let shares_init = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Fetch test cases.
    let prices = oracle_prices();
    let swap_cases = swap_test_cases(10);

    let mut index = 0;
    loop {
        if index >= prices.len() {
            break ();
        }
        // Set oracle price.
        let price = *prices[index];
        oracle.set_data_with_USD_hop('ETH', 'USDC', price, 8, 999, 5);

        if index < 9 {
            ('*** PRICE 01' + index.into()).print();
        } else {
            ('*** PRICE 10' + (index - 9).into()).print();
        }

        // Fetch swap test case.
        let swap_case: SwapCase = *swap_cases[index];

        if index < 9 {
            ('*** SWAP 01' + index.into()).print();
        } else {
            ('*** SWAP 10' + (index - 9).into()).print();
        }

        let mut params = swap_params(
            strategy.contract_address,
            market_id,
            swap_case.is_buy,
            swap_case.exact_input,
            swap_case.amount,
            swap_case.threshold_sqrt_price,
            Option::None(()),
            Option::None(()),
        );
        start_prank(CheatTarget::One(market_manager.contract_address), strategy.contract_address);
        start_prank(CheatTarget::One(strategy.contract_address), market_manager.contract_address);
        let (amount_in, amount_out, fees) = swap(market_manager, params);

        'amount_in'.print();
        amount_in.print();
        'amount_out'.print();
        amount_out.print();
        'fees'.print();
        fees.print();

        // Return position base amount.
        let bid = strategy.bid(market_id);
        let ask = strategy.ask(market_id);
        let bid_position = market_manager
            .position(
                market_id, strategy.contract_address.into(), bid.lower_limit, bid.upper_limit
            );
        let ask_position = market_manager
            .position(
                market_id, strategy.contract_address.into(), ask.lower_limit, ask.upper_limit
            );

        index += 1;
    };
}

////////////////////////////////
// HELPERS
////////////////////////////////

#[derive(Drop, Copy, Serde)]
struct Snapshot {
    lp_base_bal: u256,
    lp_quote_bal: u256,
    strategy_base_bal: u256,
    strategy_quote_bal: u256,
    market_base_bal: u256,
    market_quote_bal: u256,
    market_base_res: u256,
    market_quote_res: u256,
    market_state: MarketState,
    strategy_state: StrategyState,
}

fn _snapshot_state(
    market_manager: IMarketManagerDispatcher,
    strategy: IReplicatingStrategyDispatcher,
    market_id: felt252,
    base_token: ERC20ABIDispatcher,
    quote_token: ERC20ABIDispatcher,
    lp: ContractAddress,
) -> Snapshot {
    let lp_base_bal = base_token.balance_of(lp);
    let lp_quote_bal = quote_token.balance_of(lp);
    let strategy_base_bal = base_token.balance_of(strategy.contract_address);
    let strategy_quote_bal = quote_token.balance_of(strategy.contract_address);
    let market_base_bal = base_token.balance_of(market_manager.contract_address);
    let market_quote_bal = quote_token.balance_of(market_manager.contract_address);
    let market_base_res = market_manager.reserves(base_token.contract_address);
    let market_quote_res = market_manager.reserves(quote_token.contract_address);
    let market_state = market_manager.market_state(market_id);
    let strategy_state = strategy.strategy_state(market_id);

    Snapshot {
        lp_base_bal,
        lp_quote_bal,
        strategy_base_bal,
        strategy_quote_bal,
        market_base_bal,
        market_quote_bal,
        market_base_res,
        market_quote_res,
        market_state,
        strategy_state,
    }
}

fn _contains(span: Span<felt252>, value: felt252) -> bool {
    let mut index = 0;
    let mut result = false;
    loop {
        if index >= span.len() {
            break (result);
        }

        if *span.at(index) == value {
            break (true);
        }

        index += 1;
    }
}
