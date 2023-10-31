// Core lib imports.
use array::SpanTrait;
use starknet::ContractAddress;
use cmp::{min, max};
use debug::PrintTrait;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::liquidity as liquidity_helpers;
use amm::libraries::math::price_math;
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT};
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::types::core::MarketState;
use amm::types::i256::{i256, I256Trait};
use amm::tests::helpers::actions::market_manager::{
    deploy_market_manager, create_market, modify_position, swap
};
use amm::tests::helpers::actions::token::{deploy_token, fund, approve};
use amm::tests::helpers::params::{
    owner, alice, treasury, default_token_params, default_market_params, modify_position_params,
    swap_params
};
use amm::tests::helpers::utils::{to_e18, to_e28, encode_sqrt_price};

// External imports.
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
struct MarketStateCase {
    description: felt252,
    width: u32,
    swap_fee_rate: u16,
    start_limit: u32,
    positions: Span<Position>,
    skip_cases: Span<felt252>,
}

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
// exp: Span<(u256, u256)>,
}

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, IERC20Dispatcher, IERC20Dispatcher) {
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

    (market_manager, base_token, quote_token)
}

fn market_state_test_cases() -> Array<MarketStateCase> {
    let mut markets = ArrayTrait::<MarketStateCase>::new();

    //  0.05% swap fee, 1 width, 1:1 price, 2e28 liquidity over entire range
    markets
        .append(
            MarketStateCase {
                description: '.05% 1 1:1 2e28(max range)',
                width: 1,
                swap_fee_rate: 5,
                start_limit: OFFSET + 0,
                positions: array![
                    Position {
                        lower_limit: 0,
                        upper_limit: OFFSET + MAX_LIMIT,
                        liquidity: I256Trait::new(to_e28(2), false)
                    }
                ]
                    .span(),
                skip_cases: array![15, 16].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:1 price, 2e28 liquidity over entire range
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:1 2e28(max range)',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) + 0,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(to_e28(2), false)
                    }
                ]
                    .span(),
                skip_cases: array![15, 16].span(),
            }
        );

    // 1% swap fee, 100 width, 1:1 price, 2e28 liquidity over entire range
    markets
        .append(
            MarketStateCase {
                description: '1% 100 1:1 2e28(max range)',
                width: 100,
                swap_fee_rate: 100,
                start_limit: price_math::offset(100) + 0,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(100) - 8388600,
                        upper_limit: price_math::offset(100) + 8388600,
                        liquidity: I256Trait::new(to_e28(2), false)
                    }
                ]
                    .span(),
                skip_cases: array![15, 16].span(),
            }
        );

    // 0.25% swap fee, 10 width, 10:1 price, 2e28 liquidity over entire range
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 10:1 2e28(max range)',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) + 230260,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(to_e28(20), false)
                    }
                ]
                    .span(),
                skip_cases: array![6, 8, 13, 16].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:10 price, 2e28 liquidity over entire range
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:10 2e28(max range)',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) - 230260,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(to_e28(2), false)
                    }
                ]
                    .span(),
                skip_cases: array![3, 5, 7, 14, 15].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:1 price, 4e28 liquidity around (excluding) curr price
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:1 4e28(excl curr P)',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) - 0,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) - 10,
                        liquidity: I256Trait::new(to_e28(2), false)
                    },
                    Position {
                        lower_limit: price_math::offset(10) + 10,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(to_e28(2), false)
                    }
                ]
                    .span(),
                skip_cases: array![15, 16].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:1 price, liquidity around curr price and entire range
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:1 6e28 (arr curr P)',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) - 0,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(to_e28(2), false)
                    },
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) - 10,
                        liquidity: I256Trait::new(to_e28(2), false)
                    },
                    Position {
                        lower_limit: price_math::offset(10) + 10,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(to_e28(2), false)
                    }
                ]
                    .span(),
                skip_cases: array![15, 16].span(),
            }
        );

    // 0.05% swap fee, 1 width, 1:1 price, 2e28 liquidity around current price (stable)
    markets
        .append(
            MarketStateCase {
                description: '.05% 1 1:1 2e28 (stable)',
                width: 10,
                swap_fee_rate: 5,
                start_limit: price_math::offset(10) - 0,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 10,
                        upper_limit: price_math::offset(10) + 10,
                        liquidity: I256Trait::new(to_e28(25000), false)
                    }
                ]
                    .span(),
                skip_cases: array![13, 14, 15, 16].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:1 price, 2e28 quote liquidity only
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:1 2e28 (quote liq)',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) - 0,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 20000,
                        upper_limit: price_math::offset(10) - 0,
                        liquidity: I256Trait::new(to_e28(20), false)
                    }
                ]
                    .span(),
                skip_cases: array![2, 4, 6, 8, 10, 12, 13, 14, 15, 16].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:1 price, 2e28 base liquidity only
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:1 2e28 (base liq)',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) - 0,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 0,
                        upper_limit: price_math::offset(10) + 20000,
                        liquidity: I256Trait::new(to_e28(20), false)
                    }
                ]
                    .span(),
                skip_cases: array![1, 3, 5, 7, 9, 11, 13, 14, 15, 16].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:1 price, 2e28 near max start price
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:1 2e28 entire (max P)',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) + 8388500,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(to_e28(2), false)
                    }
                ]
                    .span(),
                skip_cases: array![4, 6, 8, 13, 16].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:1 price, 2e28 near min start price
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:1 2e28 entire (min P)',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) - 8388500,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(to_e28(2), false)
                    }
                ]
                    .span(),
                skip_cases: array![3, 5, 7, 14, 15].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:1 price, 2e28 max full range liquidity
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:1 2e28 max full rng',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) - 0,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(
                            liquidity_helpers::max_liquidity_per_limit(10), false
                        )
                    }
                ]
                    .span(),
                skip_cases: array![15, 16].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:1 price, 2e28 max limit
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:1 2e28 max limit',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) + 8388590,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(
                            liquidity_helpers::max_liquidity_per_limit(10), false
                        )
                    }
                ]
                    .span(),
                skip_cases: array![2, 4, 6, 8, 10, 12, 13, 16].span(),
            }
        );

    // 0.25% swap fee, 10 width, 1:1 price, 2e28 min limit
    markets
        .append(
            MarketStateCase {
                description: '.25% 10 1:1 2e28 min limit',
                width: 10,
                swap_fee_rate: 25,
                start_limit: price_math::offset(10) - 8388600,
                positions: array![
                    Position {
                        lower_limit: price_math::offset(10) - 8388600,
                        upper_limit: price_math::offset(10) + 8388600,
                        liquidity: I256Trait::new(
                            liquidity_helpers::max_liquidity_per_limit(10), false
                        )
                    }
                ]
                    .span(),
                skip_cases: array![1, 3, 5, 7, 9, 11, 14, 15].span(),
            }
        );

    markets
}

fn swap_test_cases() -> Array<SwapCase> {
    let mut cases = ArrayTrait::<SwapCase>::new();

    // Large amounts with no price limit.
    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: true,
                amount: to_e18(1),
                threshold_sqrt_price: Option::None(()),
            // exp: array![
            //     (999499999950049986, 500000000000000),
            //     (997499999950249686, 2500000000000000),
            //     (989999999950995000, 10000000000000000),
            //     (9975033855875133000, 2500000000000000),
            //     (99749661439251282, 2500000000000000),
            //     (997400255436287706, 2500000000000000),
            //     (997499999950249686, 2500000000000000),
            //     (999499999999975000, 500000000000000),
            //     (997499999995024960, 2500000000000000),
            //     (0, 0), // Market case 10 skipped 
            //     (32834863955144570450417977046769404770913564504, 2500000000000000),
            //     (0, 2500000000000000),
            //     (997496220905608333, 2500000000000000),
            //     (2690982850935827941860510835704150270452378172588937807, 2500000000000000),
            //     (0, 0), // Market case 15 skipped 
            // ].span(),
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: true,
                exact_input: true,
                amount: to_e18(1),
                threshold_sqrt_price: Option::None(()),
            // exp: array![
            //     (999499999950049987, 500000000000000),
            //     (997499999950249687, 2500000000000000),
            //     (989999999950995000, 10000000000000000),
            //     (99749661440667195, 2500000000000000),
            //     (9975033854459207087, 2500000000000000),
            //     (997499999950249687, 2500000000000000),
            //     (997499999950249687, 2500000000000000),
            //     (999499999999996003, 500000000000000),
            //     (0, 0), // Market case 9 skipped 
            //     (997499999995024960, 2500000000000000),
            //     (32834863955144570450417977046769404770913564504, 2500000000000000),
            //     (0, 2500000000000000),
            //     (997496220905608333, 2500000000000000),
            //     (0, 0), // Market case 14 skipped 
            //     (2690982850935827941860510835704150270452378172588937807, 2500000000000000),
            // ].span(),
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: false,
                amount: to_e18(1),
                threshold_sqrt_price: Option::None(())
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: true,
                exact_input: false,
                amount: to_e18(1),
                threshold_sqrt_price: Option::None(())
            }
        );

    // Large amounts with price limit.
    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: true,
                amount: to_e18(1),
                threshold_sqrt_price: Option::Some(encode_sqrt_price(50, 100))
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: true,
                exact_input: true,
                amount: to_e18(1),
                threshold_sqrt_price: Option::Some(encode_sqrt_price(200, 100))
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: false,
                amount: to_e18(1),
                threshold_sqrt_price: Option::Some(encode_sqrt_price(50, 100))
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: true,
                exact_input: false,
                amount: to_e18(1),
                threshold_sqrt_price: Option::Some(encode_sqrt_price(200, 100))
            }
        );

    // Small amounts with no price limit.
    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: true,
                amount: 100000,
                threshold_sqrt_price: Option::None(())
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: true,
                exact_input: true,
                amount: 100000,
                threshold_sqrt_price: Option::None(())
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: false,
                amount: 100000,
                threshold_sqrt_price: Option::None(())
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: true,
                exact_input: false,
                amount: 100000,
                threshold_sqrt_price: Option::None(())
            }
        );

    // Max possible within price limit.
    cases
        .append(
            SwapCase {
                is_buy: true,
                exact_input: true,
                amount: MAX / 1000000000000000000,
                threshold_sqrt_price: Option::Some(encode_sqrt_price(5, 2))
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: true,
                amount: MAX / 1000000000000000000,
                threshold_sqrt_price: Option::Some(encode_sqrt_price(2, 5))
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: false,
                exact_input: true,
                amount: MAX / 1000000000000000000,
                threshold_sqrt_price: Option::Some(encode_sqrt_price(5, 2))
            }
        );
    cases
        .append(
            SwapCase {
                is_buy: true,
                exact_input: true,
                amount: MAX / 1000000000000000000,
                threshold_sqrt_price: Option::Some(encode_sqrt_price(2, 5))
            }
        );

    cases
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(15000000000)]
fn test_swap_cases() {
    // Fetch test cases.
    let market_cases = market_state_test_cases();

    // Iterate through pool test cases.
    let mut index = 0;
    loop {
        if index >= market_cases.len() {
            break ();
        }

        // Fetch test cases.
        let market_case: MarketStateCase = *market_cases[index];
        let swap_cases = swap_test_cases();

        if index < 9 {
            ('*** MKT 01' + index.into()).print();
        } else {
            ('*** MKT 10' + (index - 9).into()).print();
        }

        // Iterate through swap test cases.
        let mut swap_index = 0;
        loop {
            if swap_index >= swap_cases.len() {
                break ();
            }

            // Fetch swap test case.
            let swap_case: SwapCase = *swap_cases[swap_index];

            if !_contains(market_case.skip_cases, swap_index.into() + 1) {
                let (market_manager, base_token, quote_token) = before();

                // Create the market.
                let mut params = default_market_params();
                params.base_token = base_token.contract_address;
                params.quote_token = quote_token.contract_address;
                params.start_limit = market_case.start_limit;
                params.width = market_case.width;
                params.swap_fee_rate = market_case.swap_fee_rate;

                market_case.description.print();
                let market_id = create_market(market_manager, params);

                // Mint positions.
                let mut pos_index = 0;
                loop {
                    if pos_index >= market_case.positions.len() {
                        break ();
                    }

                    let position: Position = *market_case.positions[pos_index];
                    let mut params = modify_position_params(
                        alice(),
                        market_id,
                        position.lower_limit,
                        position.upper_limit,
                        position.liquidity
                    );
                    modify_position(market_manager, params);

                    pos_index += 1;
                };

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
                if swap_index < 9 {
                    ('*** SWAP 01' + swap_index.into()).print();
                } else {
                    ('*** SWAP 10' + (swap_index - 9).into()).print();
                }
                // '* base balance'.print();
                // base_balance_before.print();
                // '* quote amount'.print();
                // quote_balance_before.print();
                // '* Liquidity'.print();
                // liquidity_before.print();
                // '* Limit'.print();
                // limit_before.print();
                // '* Sqrt price'.print();
                // sqrt_price_before.print();

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

                // 'amount_out'.print();
                // amount_out.print();
                // 'fees'.print();
                // fees.print();
                // let (amount_out_exp, fees_exp) = *swap_case.exp.at(index);
                // assert(amount_out == amount_out_exp, 'amount_out');
                // assert(fees == fees_exp, 'fees');

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
            // if swap_index < 10 {
            //     ('*** AFTER SWAP 01' + swap_index.into()).print();
            // } else {
            //     ('*** AFTER SWAP 10' + (swap_index - 9).into()).print();
            // }
            // '* base amount'.print();
            // (max(base_balance_before, base_balance_after)
            //     - min(base_balance_before, base_balance_after))
            //     .print();
            // '* quote amount'.print();
            // (max(quote_balance_before, quote_balance_after)
            //     - min(quote_balance_before, quote_balance_after))
            //     .print();
            // '* Liquidity after'.print();
            // liquidity_after.print();
            // '* Limit after'.print();
            // limit_after.print();
            // '* Sqrt price after'.print();
            // sqrt_price_after.print();
            }

            swap_index += 1;
        };

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
