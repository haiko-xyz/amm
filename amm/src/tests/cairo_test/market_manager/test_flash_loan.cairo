// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::contracts::market_manager::MarketManager;
use amm::libraries::constants::OFFSET;
use amm::interfaces::IMarketManager::IMarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::ILoanReceiver::ILoanReceiver;
use amm::interfaces::ILoanReceiver::{ILoanReceiverDispatcher, ILoanReceiverDispatcherTrait};
use amm::types::i256::{i256, I256Trait};
use amm::tests::cairo_test::helpers::market_manager::{
    deploy_market_manager, create_market, modify_position
};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::cairo_test::helpers::loan_receiver::deploy_loan_receiver;
use amm::tests::common::params::{
    owner, alice, treasury, default_token_params, default_market_params, modify_position_params
};
use amm::tests::common::contracts::flash_loan_receiver;
use amm::tests::common::utils::{to_e28, to_e18};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before(
    return_funds: bool
) -> (
    IMarketManagerDispatcher,
    ERC20ABIDispatcher,
    ERC20ABIDispatcher,
    felt252,
    ILoanReceiverDispatcher
) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Deploy loan receiver.
    let loan_receiver = deploy_loan_receiver(market_manager.contract_address, return_funds);

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = OFFSET - 0; // initial limit
    let market_id = create_market(market_manager, params);

    // Fund LP with initial token balances and approve market manager as spender. Fund loan receiver.
    let initial_base_amount = to_e28(500000);
    let initial_quote_amount = to_e28(10000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);
    fund(base_token, loan_receiver.contract_address, initial_base_amount);
    fund(quote_token, loan_receiver.contract_address, initial_quote_amount);

    (market_manager, base_token, quote_token, market_id, loan_receiver)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(1000000000)]
fn test_flash_loan() {
    let (market_manager, base_token, quote_token, market_id, loan_receiver) = before(true);

    // Create position.
    set_contract_address(alice());
    let mut lower_limit = OFFSET - 10000;
    let mut upper_limit = OFFSET + 10000;
    let mut liquidity = I256Trait::new(to_e18(10000), false);
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);

    // Borrow non-zero amount of both assets. Works if flash loan fee has not been set.
    set_contract_address(loan_receiver.contract_address);
    market_manager.flash_loan(base_token.contract_address, 10000000000);
    market_manager.flash_loan(quote_token.contract_address, 10000000000);

    // Set flash loan fee.
    set_contract_address(owner());
    market_manager.set_flash_loan_fee(base_token.contract_address, 10);
    market_manager.set_flash_loan_fee(quote_token.contract_address, 25);

    // Borrow max amount of both assets. 
    set_contract_address(loan_receiver.contract_address);
    let base_start = base_token.balance_of(loan_receiver.contract_address);
    let quote_start = quote_token.balance_of(loan_receiver.contract_address);
    market_manager.flash_loan(base_token.contract_address, 487703376934855106884);
    market_manager.flash_loan(quote_token.contract_address, 487703376934855106884);
    let base_end = base_token.balance_of(loan_receiver.contract_address);
    let quote_end = quote_token.balance_of(loan_receiver.contract_address);

    // Check that fee is deducted.
    assert(base_end == base_start - 487703376934855107, 'Base loan fee');
    assert(quote_end == quote_start - 1219258442337137768, 'Quote loan fee');
}

#[test]
#[should_panic(expected: ('LoanInsufficient', 'ENTRYPOINT_FAILED',))]
#[available_gas(1000000000)]
fn test_flash_loan_no_liquidity() {
    let (market_manager, base_token, quote_token, market_id, loan_receiver) = before(true);

    set_contract_address(loan_receiver.contract_address);
    market_manager.flash_loan(base_token.contract_address, 10000000000);
}

#[test]
#[should_panic(expected: ('LoanNotReturned', 'ENTRYPOINT_FAILED',))]
#[available_gas(1000000000)]
fn test_flash_loan_unreturned() {
    let (market_manager, base_token, quote_token, market_id, loan_receiver) = before(false);

    // Create position.
    set_contract_address(alice());
    let mut lower_limit = OFFSET - 10000;
    let mut upper_limit = OFFSET + 10000;
    let mut liquidity = I256Trait::new(to_e18(10000), false);
    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    modify_position(market_manager, params);

    // Flash loan and don't return amount.
    set_contract_address(loan_receiver.contract_address);
    market_manager.flash_loan(base_token.contract_address, 10000000000);
}

#[test]
#[should_panic(expected: ('LoanAmtZero', 'ENTRYPOINT_FAILED',))]
#[available_gas(1000000000)]
fn test_flash_loan_amount_zero() {
    let (market_manager, base_token, quote_token, market_id, loan_receiver) = before(true);

    set_contract_address(loan_receiver.contract_address);
    market_manager.flash_loan(base_token.contract_address, 0);
}
