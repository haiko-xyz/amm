// Core lib imports.
use starknet::ContractAddress;
use starknet::testing::set_contract_address;
use integer::{BoundedU32, BoundedU128, BoundedU256};

// Local imports.
use amm::libraries::constants::{OFFSET, MAX_LIMIT, MAX_SCALED};
use amm::libraries::math::price_math;
use amm::libraries::math::liquidity_math;
use amm::interfaces::IMarketManager::{
    IMarketManager, IMarketManagerDispatcher, IMarketManagerDispatcherTrait
};
use amm::types::core::{MarketState};
use amm::types::i128::{i128, I128Trait};
use amm::tests::cairo_test::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap},
    token::{deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, treasury, default_token_params, default_market_params, modify_position_params,
    swap_params
};
use amm::tests::common::utils::{to_e18, to_e28, approx_eq, approx_eq_pct};
use strategies::strategies::replicating::{
    interface::{IReplicatingStrategyDispatcher, IReplicatingStrategyDispatcherTrait},
    pragma::{DataType, PragmaPricesResponse}, types::Limits,
    test::mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
};
use strategies::tests::cairo_test::replicating::helpers::{
    deploy_replicating_strategy, deploy_mock_pragma_oracle
};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

use debug::PrintTrait;

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

fn before() -> (
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
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

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
    strategy
        .add_market(
            market_id,
            owner,
            'ETH/USD',
            'USDC/USD',
            'ETH/USDC',
            40000, // ~50% deviation
            Limits::Fixed(10), // ~0.01% min spread
            Limits::Fixed(20000), // ~20% range
            200, // ~0.2% delta
            259200, // volatility lookback period of 3 days
            true,
        );

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

    (market_manager, base_token, quote_token, market_id, oracle, strategy)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(100000000)]
fn test_replicating_strategy_deposit_initial() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166878000000); // 1668.78

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let (base_amount, quote_amount, shares) = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);
    let base_liquidity_exp = 429406775392817428992841450;
    let quote_liquidity_exp = 286266946460287812818573174;
    let shares_exp = quote_liquidity_exp + base_liquidity_exp;

    assert(approx_eq(base_amount, initial_base_amount, 10), 'Deposit initial: base');
    assert(approx_eq(quote_amount, initial_quote_amount, 10), 'Deposit initial: quote');
    assert(approx_eq_pct(shares, shares_exp, 20), 'Deposit initial: shares');
    assert(
        approx_eq_pct(strategy.user_deposits(market_id, owner()), shares_exp, 20),
        'Deposit initial: balance'
    );
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_update_positions() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166878000000); // 1668.78

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let (base_amount, quote_amount, shares) = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 167250000000); // 1672.5

    // Execute swap and check positions updated.
    let amount = to_e18(500000);
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()), Option::None(()));
    let bid = strategy.bid(market_id);
    let ask = strategy.ask(market_id);
    let market_state = market_manager.market_state(market_id);

    assert(bid.lower_limit == 7906620 + 721930, 'Bid: lower limit');
    assert(bid.upper_limit == 7906620 + 741930, 'Bid: upper limit');
    assert(ask.lower_limit == 7906620 + 742050, 'Ask: lower limit');
    assert(ask.upper_limit == 7906620 + 762050, 'Ask: upper limit');
    assert(approx_eq_pct(bid.liquidity.into(), 286266946460287812818573174, 20), 'Bid: liquidity');
    assert(approx_eq_pct(ask.liquidity.into(), 429406775392817428992841450, 20), 'Ask: liquidity');
    assert(
        approx_eq(market_state.curr_sqrt_price, 408644240927203282685139153875, 100),
        'Market: curr sqrt price'
    );
    assert(market_state.curr_limit == 7906620 + 742055, 'Market: curr sqrt price');
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_multiple_swaps() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166700000000);

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let (base_amount, quote_amount, shares) = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 163277500000);

    // Execute swap 1 and check positions updated.
    let amount = to_e18(100);
    market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()), Option::None(()));
    let bid = strategy.bid(market_id);
    let ask = strategy.ask(market_id);
    let market_state = market_manager.market_state(market_id);
    assert(bid.lower_limit == 7906620 + 721870, 'Bid 1: lower limit');
    assert(bid.upper_limit == 7906620 + 741870, 'Bid 1: upper limit');
    assert(ask.lower_limit == 7906620 + 741940, 'Ask 1: lower limit');
    assert(ask.upper_limit == 7906620 + 761940, 'Ask 1: upper limit');
    assert(
        approx_eq_pct(bid.liquidity.into(), 286352838998000392443103695, 20), 'Bid 1: liquidity'
    );
    assert(
        approx_eq_pct(ask.liquidity.into(), 429170667782432169281955462, 20), 'Ask 1: liquidity'
    );
    assert(
        approx_eq_pct(market_state.curr_sqrt_price, 408407949181225947147258078960, 20),
        'Swap 1: end sqrt price'
    );
    assert(market_state.curr_limit == 7906620 + 741940, 'Swap 1: end limit');
    let (base_amount, quote_amount) = strategy.get_balances(market_id);

    // Execute swap 2 and check positions updated.
    market_manager
        .swap(market_id, false, amount, true, Option::None(()), Option::None(()), Option::None(()));
    let bid_2 = strategy.bid(market_id);
    let ask_2 = strategy.ask(market_id);
    let market_state_2 = market_manager.market_state(market_id);
    assert(bid_2.lower_limit == 7906620 + 719790, 'Bid 2: lower limit');
    assert(bid_2.upper_limit == 7906620 + 739790, 'Bid 2: upper limit');
    assert(ask_2.lower_limit == 7906620 + 741950, 'Ask 2: lower limit');
    assert(ask_2.upper_limit == 7906620 + 761950, 'Ask 2: upper limit');
    assert(
        approx_eq_pct(bid_2.liquidity.into(), 289346459271780151386678214, 20), 'Bid 2: liquidity'
    );
    assert(
        approx_eq_pct(ask_2.liquidity.into(), 429192101090792820578334882, 20), 'Ask 2: liquidity'
    );
    assert(
        approx_eq_pct(market_state_2.curr_sqrt_price, 404035472140796796041975907438, 20),
        'Swap 2: end sqrt price'
    );
    assert(market_state_2.curr_limit == 7906620 + 739787, 'Swap 2: end limit');
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_deposit() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166878000000);

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    strategy.deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Deposit.
    set_contract_address(alice());
    let base_amount_req = to_e18(500);
    let quote_amount_req = to_e18(700000); // Contains extra, should be partially refunded
    let (base_amount, quote_amount, new_shares) = strategy
        .deposit(market_id, base_amount_req, quote_amount_req);

    // Run checks.
    let market_state = market_manager.market_state(market_id);
    let state = strategy.strategy_state(market_id);

    let bid_init_shares_exp = 286266946460287812818573174;
    let ask_init_shares_exp = 429406775392817428992841450;
    let bid_new_shares_exp = 143133473230143906409286;
    let ask_new_shares_exp = 214703387696408714496420;

    assert(base_amount == base_amount_req, 'Deposit: base');
    assert(quote_amount == to_e18(556260), 'Deposit: quote');
    assert(approx_eq_pct(state.bid.liquidity.into(), bid_init_shares_exp, 10), 'Bid: liquidity');
    assert(approx_eq_pct(state.ask.liquidity.into(), ask_init_shares_exp, 10), 'Ask: liquidity');
    assert(
        approx_eq_pct(new_shares, bid_new_shares_exp + ask_new_shares_exp, 20), 'Deposit: shares'
    );
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_withdraw() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166878000000);

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let (base_amount_init, quote_amount_init, shares_init) = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Execute swap sell.
    let amount = to_e18(5000);
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, false, amount, true, Option::None(()), Option::None(()), Option::None(()));

    // Withdraw from strategy.
    let shares_init = 286266946460287812818573174 + 429406775392817428992841450;
    let shares_req = 357836860926552620905707312;
    let (base_amount, quote_amount) = strategy.withdraw(market_id, shares_req);
    let market_state = market_manager.market_state(market_id);
    let state = strategy.strategy_state(market_id);

    // Run checks.
    assert(
        approx_eq_pct((state.bid.liquidity + state.ask.liquidity).into(), shares_req, 20),
        'Withdraw: liquidity'
    );
    assert(amount_in == amount, 'Withdraw: amount in');
    assert(approx_eq_pct(amount_out, 8308093186237340625293077, 20), 'Withdraw: amount out');
    assert(fees == to_e18(15), 'Withdraw: fees');
    assert(approx_eq_pct(base_amount, 502499985000000000000000, 20), 'Withdraw: base amount');
    assert(approx_eq_pct(quote_amount, 552105953406881329687353461, 20), 'Withdraw: quote amount');
    assert(
        approx_eq_pct(state.bid.liquidity.into(), 143133473230143906409286587, 20),
        'Withdraw: bid liquidity'
    );
    assert(
        approx_eq_pct(state.ask.liquidity.into(), 214703387696408714496420725, 20),
        'Withdraw: ask liquidity'
    );
    assert(approx_eq(state.base_reserves, 7485000000000000000, 10), 'Withdraw: base reserves');
    assert(approx_eq(state.quote_reserves, 0, 10), 'Withdraw: quote reserves');
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_collect_and_pause() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 100100000);

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = 1000000;
    let initial_quote_amount = 1000000;
    let (base_amount_init, quote_amount_init, shares_init) = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Collect and pause.
    set_contract_address(owner());
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
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('DepositDisabled', 'ENTRYPOINT_FAILED'))]
fn test_replicating_strategy_disable_deposits() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166878000000);

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = 1000000;
    let initial_quote_amount = 1000000;
    let (base_amount_init, quote_amount_init, shares_init) = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Disable deposits.
    let params = strategy.strategy_params(market_id);
    strategy
        .set_params(
            market_id, params.min_spread, params.range, params.max_delta, params.vol_period, false
        );

    // Try to deposit.
    set_contract_address(alice());
    strategy.deposit(market_id, to_e18(500), to_e18(700000));
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_reenable_deposits() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166878000000);

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = 1000000;
    let initial_quote_amount = 1000000;
    let (base_amount_init, quote_amount_init, shares_init) = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Disable deposits.
    let params = strategy.strategy_params(market_id);
    strategy
        .set_params(
            market_id, params.min_spread, params.range, params.max_delta, params.vol_period, false
        );

    // Enable deposits.
    strategy
        .set_params(
            market_id, params.min_spread, params.range, params.max_delta, params.vol_period, true
        );

    // Deposit.
    set_contract_address(alice());
    strategy.deposit(market_id, to_e18(500), to_e18(700000));
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_oracle_guard() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Update price.
    set_contract_address(owner());
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166800000000);

    // Deposit initial.
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let (base_amount, quote_amount, shares) = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Lower price beyond threshold.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 70000000000);

    // Swap.
    let amount = to_e18(500000);
    market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()), Option::None(()));

    // Check strategy was paused and positions withdrawn.
    assert(strategy.is_paused(market_id), 'Oracle guard: paused');
    let bid = strategy.bid(market_id);
    let ask = strategy.ask(market_id);
    assert(bid.liquidity == 0, 'Oracle guard: bid liquidity');
    assert(ask.liquidity == 0, 'Oracle guard: ask liquidity');

    // Manually unpause and reset price.
    strategy.unpause(market_id);
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166800000000);

    // Increase price beyond threshold.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 340000000000);

    // Swap.
    market_manager
        .swap(market_id, false, amount, true, Option::None(()), Option::None(()), Option::None(()));

    // Check strategy was paused again and positions withdrawn.
    assert(strategy.is_paused(market_id), 'Oracle guard: pause 2');
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_lvr_rebalance_condition() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Update price.
    set_contract_address(owner());
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166780000000);

    // Deposit initial.
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let (base_amount, quote_amount, shares) = strategy
        .deposit_initial(market_id, initial_base_amount, initial_quote_amount);

    // Update price to within LVR rebalance threshold.
    set_contract_address(owner());
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 167300000000);

    let bid_before = strategy.bid(market_id);
    let ask_before = strategy.ask(market_id);

    // Swap and check positions not updated.
    let amount = to_e18(500000);
    market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()), Option::None(()));
    let mut bid_after = strategy.bid(market_id);
    let mut ask_after = strategy.ask(market_id);
    assert(bid_before == bid_after, 'LVR rebalance: bid 1');
    assert(ask_before == ask_after, 'LVR rebalance: ask 1');

    // Update price again.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166400000000);
    market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()), Option::None(()));
    bid_after = strategy.bid(market_id);
    ask_after = strategy.ask(market_id);
    assert(bid_before == bid_after, 'LVR rebalance: bid 2');
    assert(ask_before == ask_after, 'LVR rebalance: ask 2');
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_set_strategy_params() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    set_contract_address(owner());
    let params = strategy.strategy_params(market_id);
    let min_spread = Limits::Fixed(0);
    let range = Limits::Fixed(3000);
    let max_delta = 0;
    let vol_period = 0;
    let allow_deposits = true;
    strategy.set_params(market_id, min_spread, range, max_delta, vol_period, allow_deposits);

    let params = strategy.strategy_params(market_id);
    assert(params.min_spread == Limits::Fixed(0), 'Set params: min spread');
    assert(params.range == Limits::Fixed(3000), 'Set params: range');
    assert(params.max_delta == 0, 'Set params: max delta');
    assert(params.vol_period == 0, 'Set params: vol period');
    assert(params.allow_deposits == true, 'Set params: allow deposits');
}

#[test]
#[available_gas(1000000000)]
#[should_panic(expected: ('ParamsUnchanged', 'ENTRYPOINT_FAILED'))]
fn test_replicating_strategy_set_strategy_params_unchanged() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    set_contract_address(owner());
    let params = strategy.strategy_params(market_id);
    strategy
        .set_params(
            market_id,
            params.min_spread,
            params.range,
            params.max_delta,
            params.vol_period,
            params.allow_deposits
        );
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
#[available_gas(15000000000)]
fn test_replicating_strategy_swap_cases() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set oracle price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166878000000);

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    let (base_amount_init, quote_amount_init, shares_init) = strategy
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
        oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', price);

        if index < 9 {
            ('*** PRICE 01' + index.into()).print();
        } else {
            ('*** PRICE 10' + (index - 9).into()).print();
        }

        // Fetch swap test case.
        let swap_case: SwapCase = *swap_cases[index];

        // Snapshot state before.
        let (
            market_state_before,
            base_balance_before,
            quote_balance_before,
            liquidity_before,
            limit_before,
            sqrt_price_before
        ) =
            _snapshot_state(
            market_manager, market_id, base_token, quote_token
        );
        if index < 9 {
            ('*** SWAP 01' + index.into()).print();
        } else {
            ('*** SWAP 10' + (index - 9).into()).print();
        }

        let mut params = swap_params(
            alice(),
            market_id,
            swap_case.is_buy,
            swap_case.exact_input,
            swap_case.amount,
            swap_case.threshold_sqrt_price,
            Option::None(()),
            Option::None(()),
        );
        let (amount_in, amount_out, fees) = swap(market_manager, params);

        'amount_in'.print();
        amount_in.print();
        'amount_out'.print();
        amount_out.print();
        'fees'.print();
        fees.print();

        // Snapshot state after.
        let (
            market_state_after,
            base_balance_after,
            quote_balance_after,
            liquidity_after,
            limit_after,
            sqrt_price_after
        ) =
            _snapshot_state(
            market_manager, market_id, base_token, quote_token
        );

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

fn _snapshot_state(
    market_manager: IMarketManagerDispatcher,
    market_id: felt252,
    base_token: ERC20ABIDispatcher,
    quote_token: ERC20ABIDispatcher,
) -> (MarketState, u256, u256, u128, u32, u256) {
    let market_state = market_manager.market_state(market_id);
    let base_balance = base_token.balance_of(market_manager.contract_address);
    let quote_balance = quote_token.balance_of(market_manager.contract_address);
    let liquidity = market_manager.liquidity(market_id);
    let limit = market_manager.curr_limit(market_id);
    let sqrt_price = market_manager.curr_sqrt_price(market_id);

    (market_state, base_balance, quote_balance, liquidity, limit, sqrt_price)
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
