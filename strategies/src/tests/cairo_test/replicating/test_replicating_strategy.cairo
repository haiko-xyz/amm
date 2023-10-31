// Core lib imports.
use starknet::ContractAddress;
use starknet::testing::set_contract_address;
use integer::BoundedU128;

// Local imports.
use amm::libraries::id;
use amm::libraries::constants::{OFFSET, MAX_LIMIT};
use amm::libraries::math::price_math;
use amm::libraries::math::liquidity_math;
use amm::interfaces::IMarketManager::{
    IMarketManager, IMarketManagerDispatcher, IMarketManagerDispatcherTrait
};
use amm::types::core::{MarketState};
use amm::types::i256::{i256, I256Trait};
use amm::tests::cairo_test::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position},
    token::{deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, treasury, default_token_params, default_market_params, modify_position_params, swap_params
};
use amm::tests::common::utils::encode_sqrt_price;
use amm::tests::cairo_test::helpers::market_manager::swap;
use amm::libraries::liquidity as liquidity_helpers;
use amm::libraries::constants::MAX;
use strategies::strategies::replicating::{
    replicating_strategy::{IReplicatingStrategyDispatcher, IReplicatingStrategyDispatcherTrait},
    pragma_interfaces::{DataType, PragmaPricesResponse},
};
use strategies::tests::{
    cairo_test::replicating::helpers::{deploy_replicating_strategy, deploy_mock_pragma_oracle},
    common::contracts::mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
    common::utils::{to_e18, to_e28, approx_eq},
};

// External imports.
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use debug::PrintTrait;

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
struct Position {
    lower_limit: u32,
    upper_limit: u32,
    liquidity: i256,
}

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
    IERC20Dispatcher,
    IERC20Dispatcher,
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
    let strategy = deploy_replicating_strategy(owner);

    // Create market.
    let mut params = default_market_params();
    params.width = 10;
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = 8388600 + 741930; // initial limit
    params.strategy = strategy.contract_address;
    let market_id = create_market(market_manager, params);

    // Initialise strategy.
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
        .deposit_initial(initial_base_amount, initial_quote_amount);

    let quote_liquidity_exp = 286281260093880636353279894;
    let base_liquidity_exp = 429385305698142922274058535;
    let shares_exp = quote_liquidity_exp + base_liquidity_exp;

    assert(approx_eq(base_amount, initial_base_amount, 10), 'Deposit initial: base');
    assert(approx_eq(quote_amount, initial_quote_amount, 10), 'Deposit initial: quote');
    assert(shares == shares_exp, 'Deposit initial: shares');
    let strategy_token = IERC20Dispatcher { contract_address: strategy.contract_address };
    assert(strategy_token.balance_of(owner()) == shares_exp, 'Deposit initial: balance');
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
        .deposit_initial(initial_base_amount, initial_quote_amount);

    // Update price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 167250000000); // 1672.5

    // Execute swap and check positions updated.
    let amount = to_e18(500000);
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()));
    let bid = strategy.bid();
    let ask = strategy.ask();
    let market_state = market_manager.market_state(market_id);

    assert(amount_in == amount, 'Swap: amount in');
    assert(amount_out == 297873123266873285108, 'Swap: amount out');
    assert(fees == to_e18(1500), 'Swap: fees');
    assert(bid.lower_limit == 8388600 + 721920, 'Bid: lower limit');
    assert(bid.upper_limit == 8388600 + 741920, 'Bid: upper limit');
    assert(ask.lower_limit == 8388600 + 742270, 'Ask: lower limit');
    assert(ask.upper_limit == 8388600 + 762270, 'Ask: upper limit');
    assert(
        market_state.curr_sqrt_price == 409093969122899599425907670249, 'Market: curr sqrt price'
    );
    assert(market_state.curr_limit == 8388600 + 742275, 'Market: curr sqrt price');
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_multiple_swaps() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166700000000);

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = to_e18(10000);
    let initial_quote_amount = to_e18(11125200);
    let (base_amount, quote_amount, shares) = strategy
        .deposit_initial(initial_base_amount, initial_quote_amount);

    // Update price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 163277500000);

    // Execute swap and check positions updated.
    let amount = to_e18(1);
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()));
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, false, amount, true, Option::None(()), Option::None(()));
}

#[test]
#[available_gas(1000000000)]
fn test_replicating_strategy_deposit_to_strategy() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 166878000000);

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = to_e18(1000000);
    let initial_quote_amount = to_e18(1112520000);
    strategy.deposit_initial(initial_base_amount, initial_quote_amount);

    // Deposit.
    set_contract_address(alice());
    let base_amount_req = to_e18(500);
    let quote_amount_req = to_e18(700000); // Contains extra, should be partially refunded
    let (base_amount, quote_amount, new_shares) = strategy
        .deposit(base_amount_req, quote_amount_req);

    // Run checks.
    let market_state = market_manager.market_state(market_id);
    let bid = strategy.bid();
    let ask = strategy.ask();
    let strategy_base_reserves = strategy.base_reserves();
    let strategy_quote_reserves = strategy.quote_reserves();

    let bid_init_shares_exp = 286281260093880636353279894;
    let ask_init_shares_exp = 429385305698142922274058535;
    let bid_new_shares_exp = 143140630046940318176639;
    let ask_new_shares_exp = 214692652849071461137029;

    assert(base_amount == base_amount_req, 'Deposit: base');
    assert(approx_eq(quote_amount, to_e18(556260), 10), 'Deposit: quote');
    assert(new_shares == bid_new_shares_exp + ask_new_shares_exp, 'Deposit: shares');
    assert(bid.liquidity == bid_init_shares_exp, 'Bid: liquidity');
    assert(ask.liquidity == ask_init_shares_exp, 'Ask: liquidity');
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
        .deposit_initial(initial_base_amount, initial_quote_amount);

    // Execute swap sell.
    let amount = to_e18(5000);
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, false, amount, true, Option::None(()), Option::None(()));

    // Withdraw from strategy.
    let shares_init = 286281260093880636353279894 + 429385305698142922274058535;
    let shares_req = 357833282896011779313669214;
    let (base_amount, quote_amount) = strategy.withdraw(shares_req);
    let market_state = market_manager.market_state(market_id);
    let bid = strategy.bid();
    let ask = strategy.ask();
    let base_reserves = strategy.base_reserves();
    let quote_reserves = strategy.quote_reserves();

    id::position_id(
        0x0302b338c5346fee8cb221ac9d6f722b5b4b6daa95b43758ff28062dc2419d12, 
        0x011d97ded7dfec9c6479c504db640184176438bc694187fd3592408f7c408359, 
        9118420, 
        9128420
    ).print();
    
    // Run checks.
    assert(
        approx_eq(bid.liquidity + ask.liquidity, shares_init - shares_req, 10),
        'Withdraw: liquidity'
    );
    assert(amount_in == amount, 'Withdraw: amount in');
    assert(amount_out == 8307263012937194335936819, 'Withdraw: amount out');
    assert(fees == to_e18(15), 'Withdraw: fees');
    assert(base_amount == 502499984999999999999997, 'Withdraw: base amount');
    assert(
        approx_eq(quote_amount, (initial_quote_amount - amount_out) / 2, 10),
        'Withdraw: quote amount'
    );
    assert(approx_eq(bid.liquidity, 143140630046940318176639947, 10), 'Withdraw: bid liquidity');
    assert(approx_eq(ask.liquidity, 214692652849071461137029268, 10), 'Withdraw: ask liquidity');
    assert(base_reserves == 7485000000000000000, 'Withdraw: base reserves');
    assert(quote_reserves == 0, 'Withdraw: quote reserves');
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
        .deposit_initial(initial_base_amount, initial_quote_amount);

    // Withdraw from strategy.
    strategy.collect_and_pause();
    let market_state = market_manager.market_state(market_id);
    let bid = strategy.bid();
    let ask = strategy.ask();
    let base_reserves = strategy.base_reserves();
    let quote_reserves = strategy.quote_reserves();

    // Run checks.
    let base_reserves_exp = 999999;
    let quote_reserves_exp = 999999;
    assert(market_state.liquidity == 0, 'Collect pause: mkt liquidity');
    assert(bid.liquidity == 0, 'Collect pause: bid liquidity');
    assert(ask.liquidity == 0, 'Collect pause: ask liquidity');
    assert(base_reserves == base_reserves_exp, 'Collect pause: base reserves');
    assert(quote_reserves == quote_reserves_exp, 'Collect pause: quote reserves');
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
        // Max possible within price limit.
        SwapCase {
            is_buy: true,
            exact_input: true,
            amount: MAX / 1000000000000000000,
            threshold_sqrt_price: Option::Some(
                price_math::limit_to_sqrt_price(8388600 + 746000, width)
            )
        },
        SwapCase {
            is_buy: false,
            exact_input: true,
            amount: MAX / 1000000000000000000,
            threshold_sqrt_price: Option::Some(
                price_math::limit_to_sqrt_price(8388600 + 736000, width)
            )
        },
        SwapCase {
            is_buy: false,
            exact_input: false,
            amount: MAX / 1000000000000000000,
            threshold_sqrt_price: Option::Some(
                price_math::limit_to_sqrt_price(8388600 + 736000, width)
            )
        },
        SwapCase {
            is_buy: true,
            exact_input: false,
            amount: MAX / 1000000000000000000,
            threshold_sqrt_price: Option::Some(
                price_math::limit_to_sqrt_price(8388600 + 746000, width)
            )
        }
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
        162012378123,
        163125000000,
        173000000000,
        173100099999,
        172800000000,
        123891238192312789312,
        0,
        1,
        BoundedU128::max(),
        1728000,
    ];
    prices
}

////////////////////////////////
// TESTS
////////////////////////////////

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
        .deposit_initial(initial_base_amount, initial_quote_amount);

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
        // '* base balance'.print();
        // base_balance_before.print();
        // '* quote amount'.print();
        // quote_balance_before.print();
        // '* Liquidity'.print();
        // liquidity_before.print();
        // '* Limit'.print();
        // limit_before.print();
        'Start Sqrt price'.print();
        sqrt_price_before.print();

        let mut params = swap_params(
            alice(),
            market_id,
            swap_case.is_buy,
            swap_case.exact_input,
            swap_case.amount,
            swap_case.threshold_sqrt_price,
            Option::None(()),
        );
        let (amount_in, amount_out, fees) = swap(market_manager, params);

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
        let bid = strategy.bid();
        let ask = strategy.ask();
        let bid_position = market_manager
            .position(
                id::position_id(
                    market_id, strategy.contract_address.into(), bid.lower_limit, bid.upper_limit
                )
            );
        let ask_position = market_manager
            .position(
                id::position_id(
                    market_id, strategy.contract_address.into(), ask.lower_limit, ask.upper_limit
                )
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
    base_token: IERC20Dispatcher,
    quote_token: IERC20Dispatcher,
) -> (MarketState, u256, u256, u256, u32, u256) {
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
