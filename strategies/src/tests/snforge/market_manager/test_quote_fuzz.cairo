// use core::debug::PrintTrait;
use snforge_std::forge_print::PrintTrait;
use core::option::OptionTrait;
use core::clone::Clone;
use core::traits::Into;
use core::traits::SubEq;
use core::traits::TryInto;
use starknet::deploy_syscall;
use core::serde::Serde;
use core::array::ArrayTrait;
use core::array::SpanTrait;
use core::traits::AddEq;
// Core lib imports.
use cmp::{min, max};

// Local imports.
use amm::libraries::constants::{OFFSET, MIN_LIMIT, MIN_SQRT_PRICE, MAX_SQRT_PRICE, MAX, MAX_NUM_LIMITS, MAX_LIMIT};
use amm::libraries::math::fee_math;
use amm::types::i256::I256Trait;
use amm::interfaces::{IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait}, IQuoter:: {IQuoterDispatcher, IQuoterDispatcherTrait}};
use strategies::strategies::test::manual_strategy::{ManualStrategy, IManualStrategyDispatcher, IManualStrategyDispatcherTrait};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap, swap_multiple},
    token::{declare_token, deploy_token, fund, approve}, quoter::deploy_quoter
};
use strategies::tests::snforge::helpers::strategy::{deploy_strategy, initialise_strategy};
use amm::tests::common::params::{
    owner, alice, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, encode_sqrt_price};

// External imports.
use snforge_std::{start_prank, stop_prank};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, felt252, ERC20ABIDispatcher, ERC20ABIDispatcher, IQuoterDispatcher, IManualStrategyDispatcher) {
    // Deploy market manager.
    let market_manager = deploy_market_manager(owner());

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let erc20_class = declare_token();
    let base_token = deploy_token(erc20_class, base_token_params);
    let quote_token = deploy_token(erc20_class, quote_token_params);

    // fund owner with base and quote asset
    let initial_base_amount = to_e28(50000000000000000000000000000000000000);
    let initial_quote_amount = to_e28(1000000000000000000000000000000000000000);
    fund(base_token, owner(), initial_base_amount);
    fund(quote_token, owner(), initial_quote_amount);

    // Fund LP with initial token balances and approve market manager as spender.
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);

    let base_amount = to_e28(500000000000000000);
    let quote_amount = to_e28(10000000000000000000);

    //deploy manual strategy
    let strategy = deploy_strategy(owner());

    // approve spending for owner
    approve(base_token, owner(), market_manager.contract_address, base_amount);
    approve(quote_token, owner(), market_manager.contract_address, quote_amount);
    approve(base_token, owner(), strategy.contract_address, base_amount);
    approve(quote_token, owner(), strategy.contract_address, quote_amount);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    // params.start_limit = OFFSET;
    params.width = 1;
    params.strategy = strategy.contract_address;

    let market_id = create_market(market_manager, params);

    initialise_strategy(strategy, owner(), 'ETH-USDC Manual 1 0.3%', 'ETH-USDC MANU-1-0.3%', market_manager.contract_address, market_id);

    start_prank(strategy.contract_address, owner());
    strategy.set_positions(OFFSET - MIN_LIMIT, OFFSET + MAX_LIMIT, OFFSET - MIN_LIMIT, OFFSET + MAX_LIMIT);
    strategy.deposit(base_amount, quote_amount);
    stop_prank(strategy.contract_address);

    let quoter = deploy_quoter(owner(), market_manager.contract_address);

    (market_manager, market_id, base_token, quote_token, quoter, strategy)
}

#[test]
fn test_quote_fuzz(
    swap1_price: u128,
    swap1_amount: u128,
    swap2_price: u128,
    swap2_amount: u128,
    swap3_price: u128,
    swap3_amount: u128,
    swap4_price: u128,
    swap4_amount: u128,
    swap5_price: u128,
    swap5_amount: u128,
    ) {
    let (market_manager, market_id, base_token, quote_token, quoter, strategy) = before();

    let position_params = modify_position_params(alice(), market_id, OFFSET - MIN_LIMIT, OFFSET + MAX_LIMIT, I256Trait::new(to_e18(100000), false));
    modify_position(market_manager, position_params);

    //initialise swap params
    let swap1_exact_input = swap1_price % 2 == 0;
    let swap2_exact_input = swap2_price % 2 == 0;
    let swap3_exact_input = swap3_price % 2 == 0;
    let swap4_exact_input = swap4_price % 2 == 0;
    let swap5_exact_input = swap5_price % 2 == 0;

    let swap1_amount_used = swap1_amount % 1000;
    let swap2_amount_used = swap2_amount % 1000;
    let swap3_amount_used = swap3_amount % 1000;
    let swap4_amount_used = swap4_amount % 1000;
    let swap5_amount_used = swap5_amount % 1000;

    let swap_params = array![
        (swap1_exact_input, swap1_amount_used, swap1_price),
        (swap2_exact_input, swap2_amount_used, swap2_price),
        (swap3_exact_input, swap3_amount_used, swap3_price),
        (swap4_exact_input, swap4_amount_used, swap4_price),
        (swap5_exact_input, swap5_amount_used, swap5_price)
    ].span();
            '00000'.print();

    let mut j = 0;
    // loop {
    //     if j >= swap_params.len(){
    //         break;
    //     }

        let (exact_input, amount, price) = *swap_params.at(0);
        if amount != 0 && price != 0 {
            let current_price = market_manager.market_state(market_id).curr_sqrt_price;
            let price_u256: u256 = price.into();
            let amount_u256: u256 = amount.into();
            '111111'.print();

            let mut is_buy = true;
            if price_u256 < current_price {
                is_buy = false;
            }

            let threshold_sqrt_price = if is_buy {
                min(price_u256, MAX_SQRT_PRICE - 1)
            } else {
                max(price_u256, MIN_SQRT_PRICE + 1 )
            };
            '222222'.print();

            let mut params = swap_params(alice(), market_id, is_buy, exact_input, amount_u256, Option::Some((threshold_sqrt_price)), Option::None(()));
            '23233232'.print();

            // get quote
            let quote = quoter.quote(market_id, true, 50, true, Option::None(()));
            '333333'.print();
            
            // execute swap
            let (amount_in, amount_out, _) = swap(market_manager, params);
            let quote_exp = if exact_input {
                amount_out
            } else {
                amount_in
            };
            '77777'.print();

            quote_exp.print();
            '========'.print();
            quote_exp.print();
            // assert(quote == quote_exp, 'quote value not equal');
        }
    // }

}