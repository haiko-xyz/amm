// Core lib imports.
use starknet::testing::set_contract_address;
use starknet::deploy_syscall;

// Local imports.
use amm::libraries::constants::{OFFSET, MAX_LIMIT};
use amm::libraries::math::price_math;
use amm::libraries::math::liquidity_math;
use amm::contracts::test::manual_strategy::{
    ManualStrategy, IManualStrategyDispatcher, IManualStrategyDispatcherTrait
};
use amm::interfaces::IMarketManager::{
    IMarketManager, IMarketManagerDispatcher, IMarketManagerDispatcherTrait
};
use amm::interfaces::IStrategy::{IStrategyDispatcher, IStrategyDispatcherTrait};
use amm::types::i128::{i128, I128Trait};
use amm::tests::cairo_test::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position},
    token::{deploy_token, fund, approve}, strategy::deploy_manual_strategy,
};
use amm::tests::common::params::{
    owner, alice, treasury, default_token_params, default_market_params
};
use amm::tests::common::utils::{encode_sqrt_price, to_e18, approx_eq};
use amm::tests::cairo_test::helpers::market_manager::swap;

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (
    IMarketManagerDispatcher,
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    felt252,
    IManualStrategyDispatcher,
) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Deploy strategy.
    let strategy = deploy_manual_strategy(owner());

    // Create market.
    let mut params = default_market_params();
    params.width = 1;
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = OFFSET + 741930; // initial limit
    params.strategy = strategy.contract_address;
    let market_id = create_market(market_manager, params);

    // Initialise strategy.
    strategy
        .initialise(
            'Manual Strategy', 'MANU', '1.0.0', market_manager.contract_address, market_id,
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

    // Fund LP with initial token balances and approve market manager as spender.
    fund(base_token, alice(), base_amount);
    fund(quote_token, alice(), quote_amount);
    approve(base_token, alice(), market_manager.contract_address, base_amount);
    approve(quote_token, alice(), market_manager.contract_address, quote_amount);

    (market_manager, base_token, quote_token, market_id, strategy)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(1000000000)]
fn test_strategy() {
    let (market_manager, base_token, quote_token, market_id, strategy) = before();

    // Snapshot initial balances.
    let base_balance_start = base_token.balance_of(owner());
    let quote_balance_start = quote_token.balance_of(owner());

    // Set positions and deposit liquidity.
    set_contract_address(owner());
    strategy.set_positions(OFFSET + 721930, OFFSET + 741930, OFFSET + 742550, OFFSET + 762550);
    let base_amount = to_e18(10000);
    let quote_amount = to_e18(125000000);
    strategy.deposit(base_amount, quote_amount);

    // Execute swap.
    set_contract_address(alice());
    let amount = to_e18(10);
    let (amount_in, amount_out, fees) = market_manager
        .swap(market_id, true, amount, true, Option::None(()), Option::None(()), Option::None(()));

    // Check swap amounts and position.
    let placed_positions = IStrategyDispatcher { contract_address: strategy.contract_address }
        .placed_positions(market_id);
    let bid = *placed_positions.at(0);
    let ask = *placed_positions.at(1);

    let base_amount_exp = 5940973053462648;
    let quote_amount_exp = 9999939999999999999;
    assert(amount_in == amount, 'Amount in');
    assert(approx_eq(amount_out, base_amount_exp, 10), 'Amount out');
    assert(approx_eq(fees, 29999999999999999, 10), 'Fees');
    assert(approx_eq(bid.liquidity.into(), 32164247211318427176429769, 10), 'Bid: liquidity');
    assert(approx_eq(ask.liquidity.into(), 4304816299654341048944538, 10), 'Ask: liquidity');
    assert(bid.lower_limit == OFFSET + 721930, 'Bid: lower limit');
    assert(bid.upper_limit == OFFSET + 741930, 'Bid: upper limit');
    assert(ask.lower_limit == OFFSET + 742550, 'Ask: lower limit');
    assert(ask.upper_limit == OFFSET + 762550, 'Ask: upper limit');

    // Withdraw liquidity.
    set_contract_address(owner());
    strategy.withdraw();

    // Snapshot end balances.
    let base_balance_end = base_token.balance_of(owner());
    let quote_balance_end = quote_token.balance_of(owner());

    // Check balances.
    assert(approx_eq(base_balance_start - base_balance_end, base_amount_exp, 10), 'Base balance');
    assert(
        approx_eq(quote_balance_end - quote_balance_start, quote_amount_exp, 10), 'Quote balance'
    );
}
