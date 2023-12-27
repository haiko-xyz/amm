// Core lib imports.
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::libraries::constants::{OFFSET, MAX_LIMIT};
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IQuoter::{IQuoterDispatcher, IQuoterDispatcherTrait};
use amm::types::i128::{i128, I128Trait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position, swap
};
use amm::tests::cairo_test::helpers::{token::{deploy_token, fund, approve}, quoter::deploy_quoter};
use amm::tests::common::params::{
    owner, alice, default_token_params, default_market_params, modify_position_params, swap_params
};
use amm::tests::common::utils::{to_e18, to_e18_u128, to_e28, encode_sqrt_price};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (
    IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, IQuoterDispatcher
) {
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

    // Deploy quoter.
    let quoter = deploy_quoter(owner(), market_manager.contract_address);

    (market_manager, base_token, quote_token, quoter)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(15000000000)]
fn test_quote_array() {
    let (market_manager, base_token, quote_token, quoter) = before();

    // Create market 1.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    let market_id_1 = create_market(market_manager, params);

    // Create market 2.
    params.width = 5;
    let market_id_2 = create_market(market_manager, params);

    // Create market 3.
    params.width = 10;
    let market_id_3 = create_market(market_manager, params);

    // Mint position for market 1.
    set_contract_address(alice());
    let mut params = modify_position_params(
        alice(),
        market_id_1,
        7906620 + 749000,
        7906620 + 750000,
        I128Trait::new(to_e18_u128(100000), false),
    );
    modify_position(market_manager, params);

    // Mint position for market 2.
    params.market_id = market_id_2;
    params.liquidity_delta = I128Trait::new(to_e18_u128(75000), false);
    modify_position(market_manager, params);

    params.market_id = market_id_3;
    params.liquidity_delta = I128Trait::new(to_e18_u128(40000), false);
    modify_position(market_manager, params);

    // Obtain quotes.
    set_contract_address(alice());
    let market_ids = array![market_id_1, market_id_2, market_id_3].span();
    let is_buy = true;
    let amount = to_e18(1);
    let exact_input = true;
    let quotes = quoter.unsafe_quote_array(market_ids, is_buy, amount, exact_input);

    // Execute swaps and check quote is correct.
    let mut i = 0;
    loop {
        if i == market_ids.len() {
            break;
        }
        let params = swap_params(
            alice(),
            *market_ids.at(i),
            is_buy,
            exact_input,
            amount,
            Option::None(()),
            Option::None(()),
            Option::None(()),
        );
        let (_, amount_out, _) = swap(market_manager, params);

        // Check swap amount matches quote.
        let quote = *quotes.at(i);
        assert(quote == amount_out, 'Quote array: Case 1' + i.into());
        i += 1;
    };
}
