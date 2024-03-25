// Core lib imports.
use cmp::{min, max};
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::libraries::constants::{OFFSET, MIN_LIMIT, MAX_LIMIT};
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IQuoter::{IQuoterDispatcher, IQuoterDispatcherTrait};
use amm::types::i128::{i128, I128Trait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position, swap
};
use amm::tests::cairo_test::helpers::{
    token::{deploy_token, fund, approve}, quoter::deploy_quoter, strategy::deploy_manual_strategy,
};
use amm::contracts::mocks::manual_strategy::{
    ManualStrategy, IManualStrategyDispatcher, IManualStrategyDispatcherTrait
};
use amm::tests::common::params::{
    owner, alice, default_token_params, default_market_params, modify_position_params, swap_params
};
use amm::tests::common::utils::{to_e18, to_e28, encode_sqrt_price};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
struct SwapCase {
    is_buy: bool,
    exact_input: bool,
    amount: u256,
    bid_lower: u32,
    bid_upper: u32,
    ask_lower: u32,
    ask_upper: u32
}

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (
    IMarketManagerDispatcher,
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    felt252,
    IQuoterDispatcher,
    IManualStrategyDispatcher
) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (_treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Deploy strategy.
    let strategy = deploy_manual_strategy(owner());

    // Create the market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = OFFSET + 0;
    params.strategy = strategy.contract_address;
    let market_id = create_market(market_manager, params);

    // Deploy quoter.
    let quoter = deploy_quoter(owner(), market_manager.contract_address);

    // Initialise strategy.
    strategy
        .initialise('Manual Strategy', 'MANU', '1.0.0', market_manager.contract_address, market_id);

    // Fund LP with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(5000000000000000000000000);
    let initial_quote_amount = to_e28(10000000000000000000000000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    fund(base_token, owner(), initial_base_amount);
    fund(quote_token, owner(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);
    approve(base_token, owner(), strategy.contract_address, initial_base_amount);
    approve(quote_token, owner(), strategy.contract_address, initial_quote_amount);

    // Deposit to strategy.
    set_contract_address(owner());
    strategy.deposit(to_e18(1000000), to_e18(11250000));

    (market_manager, base_token, quote_token, market_id, quoter, strategy)
}

fn swap_test_cases() -> Array<SwapCase> {
    let mut cases = ArrayTrait::<SwapCase>::new();

    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: true,
                amount: to_e18(1),
                bid_lower: OFFSET - 200,
                bid_upper: OFFSET - 100,
                ask_lower: OFFSET + 100,
                ask_upper: OFFSET + 200
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: true,
                exact_input: false,
                amount: to_e18(1),
                bid_lower: OFFSET - MIN_LIMIT,
                bid_upper: OFFSET - 1,
                ask_lower: OFFSET + 1,
                ask_upper: OFFSET + MAX_LIMIT
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: true,
                amount: to_e18(1),
                bid_lower: OFFSET - 1000,
                bid_upper: OFFSET - 900,
                ask_lower: OFFSET + 900,
                ask_upper: OFFSET + 1000
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: true,
                exact_input: true,
                amount: to_e18(1),
                bid_lower: OFFSET - MIN_LIMIT,
                bid_upper: OFFSET - 1,
                ask_lower: OFFSET + 1,
                ask_upper: OFFSET + MAX_LIMIT
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: false,
                amount: to_e18(1),
                bid_lower: OFFSET - 500,
                bid_upper: OFFSET - 1,
                ask_lower: OFFSET + 10,
                ask_upper: OFFSET + 200
            }
        );

    cases
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_quote_with_strategy() {
    let (market_manager, _base_token, _quote_token, market_id, quoter, strategy) = before();

    // Iterate through swap test cases.
    set_contract_address(alice());
    let swap_cases = swap_test_cases();
    let mut swap_index = 0;
    loop {
        if swap_index >= swap_cases.len() {
            break ();
        }

        // Fetch swap test case.
        let swap_case: SwapCase = *swap_cases[swap_index];

        // Set positions, recentering around current limit to ensure all positions are 
        // single-sided.
        set_contract_address(owner());
        let curr_limit = market_manager.curr_limit(market_id);
        strategy
            .set_positions(
                swap_case.bid_lower,
                min(swap_case.bid_upper, curr_limit),
                max(swap_case.ask_lower, curr_limit),
                swap_case.ask_upper,
            );

        // Obtain quote.
        set_contract_address(alice());
        let quote = quoter
            .quote(market_id, swap_case.is_buy, swap_case.amount, swap_case.exact_input,);

        // Execute swap.
        let mut params = swap_params(
            alice(),
            market_id,
            swap_case.is_buy,
            swap_case.exact_input,
            swap_case.amount,
            Option::None(()),
            Option::None(()),
            Option::None(()),
        );
        let (amount_in, amount_out, _) = swap(market_manager, params);
        let amount = if swap_case.exact_input {
            amount_out
        } else {
            amount_in
        };

        // Check that the quote is correct.
        assert(quote == amount, 'Incorrect quote: Case 1' + swap_index.into());

        swap_index += 1;
    };
}
