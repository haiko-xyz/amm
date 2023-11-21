// Core lib imports.
use cmp::{min, max};

// Local imports.
use amm::libraries::constants::{OFFSET, MIN_LIMIT, MIN_SQRT_PRICE, MAX_SQRT_PRICE, MAX, MAX_NUM_LIMITS, MAX_LIMIT};
use amm::libraries::math::fee_math;
use amm::types::i256::I256Trait;
use amm::interfaces::{IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait}, IQuoter:: {IQuoterDispatcher, IQuoterDispatcherTrait}};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap, swap_multiple},
    token::{declare_token, deploy_token, fund, approve}, quoter::deploy_quoter
};
use amm::tests::common::params::{
    owner, alice, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, encode_sqrt_price};

// External imports.
use snforge_std::{start_prank, PrintTrait};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, felt252, ERC20ABIDispatcher, ERC20ABIDispatcher, IQuoterDispatcher) {
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

    let quoter = deploy_quoter(owner(), market_manager.contract_address);

    (market_manager, market_id, base_token, quote_token, quoter)
}

#[test]
fn test_quote_fuzz(
    swap1_amount: u128,
    swap2_amount: u128,
    swap3_amount: u128,
    swap4_amount: u128,
    swap5_amount: u128,
    price_fuzzer: u128
) {
    let (market_manager, market_id, base_token, quote_token, quoter) = before();
    
    let position_params = modify_position_params(alice(), market_id, OFFSET - MIN_LIMIT, OFFSET + MAX_LIMIT, I256Trait::new(to_e18(100000), false));
    modify_position(market_manager, position_params);

    //initialise swap params
    let swap1_is_buy = swap1_amount % 2 == 0;
    let swap1_exact_input = swap1_amount % 3 == 0;
    let swap2_is_buy = swap2_amount % 2 == 0;
    let swap2_exact_input = swap2_amount % 3 == 0;
    let swap3_is_buy = swap3_amount % 2 == 0;
    let swap3_exact_input = swap3_amount % 3 == 0;
    let swap4_is_buy = swap4_amount % 2 == 0;
    let swap4_exact_input = swap4_amount % 3 == 0;
    let swap5_is_buy = swap5_amount % 2 == 0;
    let swap5_exact_input = swap5_amount % 3 == 0;

    let swap1_amount_used = swap1_amount % 1000;
    let swap2_amount_used = swap2_amount % 1000;
    let swap3_amount_used = swap3_amount % 1000;
    let swap4_amount_used = swap4_amount % 1000;
    let swap5_amount_used = swap5_amount % 1000;

    let swap_params = array![
        (swap1_is_buy, swap1_exact_input, swap1_amount_used),
        (swap2_is_buy, swap2_exact_input, swap2_amount_used),
        (swap3_is_buy, swap3_exact_input, swap3_amount_used),
        (swap4_is_buy, swap4_exact_input, swap4_amount_used),
        (swap5_is_buy, swap5_exact_input, swap5_amount_used)
    ].span();

    let mut j = 0;
    // loop {
    //     if j >= swap_params.len(){
    //         break;
    //     }
        let (is_buy, exact_input, amount) = *swap_params.at(0);
        if amount != 0 && price_fuzzer != 0 {

            let price_fuzzer_u256: u256 = price_fuzzer.into();
            let amount_u256: u256 = amount.into();
            let current_price = market_manager.market_state(market_id).curr_sqrt_price;
            
            let threshold_sqrt_price = if is_buy {
                min(current_price + (price_fuzzer_u256 % current_price), MAX_SQRT_PRICE - 1)
            } else {
                max(current_price - (price_fuzzer_u256 % current_price), MIN_SQRT_PRICE + 1)
            };

            let params = swap_params(alice(), market_id, is_buy, exact_input, amount_u256, Option::Some((threshold_sqrt_price)), Option::None(()));
            let quote = quoter.quote(market_id, is_buy, amount_u256, exact_input, Option::Some((threshold_sqrt_price)));
            
            let (amount_in, amount_out, _) = swap(market_manager, params);

            let quote_exp = if exact_input {
                amount_out
            } else {
                amount_in
            };

            // quote_exp.print();
            // '========'.print();
            // z.unwrap().print();
            // assert(quote == quote_exp, 'quote value not equal');
        }
    // }

}