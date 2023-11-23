// Core lib imports.
use starknet::testing::set_contract_address;
use debug::PrintTrait;

// Local imports.
use amm::libraries::constants::OFFSET;
use amm::types::core::{MarketConfigs, ConfigOption};
use amm::types::i256::I256Trait;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::cairo_test::helpers::market_manager::{deploy_market_manager, create_market};
use amm::tests::cairo_test::helpers::token::{deploy_token, fund, approve};
use amm::tests::common::params::{
    owner, alice, default_token_params, default_market_params, valid_limits, config
};
use amm::tests::common::utils::{to_e18, to_e28};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
    // Deploy market manager.
    let market_manager = deploy_market_manager(owner());

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Fund LPs and owner with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000);
    let initial_quote_amount = to_e28(10000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);
    fund(base_token, owner(), initial_base_amount);
    fund(quote_token, owner(), initial_quote_amount);
    approve(base_token, owner(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, owner(), market_manager.contract_address, initial_quote_amount);

    // Create dutch action market.
    // Set valid price range of $0.5 (-69310) to $20 (299570).
    let mut params = default_market_params();

    let valid_limits = valid_limits(
        8388600 - 69310, 8388600 + 299570, 8388600 - 69310, 8388600 + 299570
    );
    let market_configs = MarketConfigs {
        limits: config(valid_limits, true),
        add_liquidity: config(ConfigOption::Disabled, true),
        remove_liquidity: config(ConfigOption::Disabled, true),
        // make this upgradeable so we can disable bids after auction ends
        create_bid: config(ConfigOption::Enabled, false),
        create_ask: config(ConfigOption::Disabled, true),
        // make this upgradeable so we can disable order collection during order fill period
        collect_order: config(ConfigOption::Enabled, false),
        swap: config(ConfigOption::OnlyOwner, false),
    };
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.width = 10;
    params.swap_fee_rate = 0; // disable swap fees
    params.market_configs = Option::Some(market_configs);
    params.controller = owner();

    let market_id = create_market(market_manager, params);

    (market_manager, base_token, quote_token, market_id)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(1000000000)]
fn test_dutch_auction() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token, market_id) = before();

    // Auction sell amount.
    let sell_amount = to_e18(10);

    // Place some bids.
    set_contract_address(alice());
    let id_1 = market_manager.create_order(market_id, true, 8388600 + 0, to_e18(10000)); // $1.0
    let id_2 = market_manager.create_order(market_id, true, 8388600 + 91630, to_e18(50000)); // $2.5
    let id_3 = market_manager
        .create_order(market_id, true, 8388600 + 228240, to_e18(37000)); // $9.8

    // Should be able to withdraw bids before auction ends.
    market_manager.collect_order(market_id, id_2);

    // Market owner closes auction by disabling further bids and temporarily disabling collections.
    // Top bids are filled by swapping sale tokens. If the gas burden is too high, this can be done
    // across multiple swap transactions.
    set_contract_address(owner());
    let mut market_configs = market_manager.market_configs(market_id);
    market_configs.create_bid = config(ConfigOption::Disabled, true);
    market_configs.collect_order = config(ConfigOption::Disabled, false);
    market_manager.set_market_configs(market_id, market_configs);
    let (amount_in, amount_out, _) = market_manager
        .swap(
            market_id,
            false,
            sell_amount,
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );
    market_configs.collect_order = config(ConfigOption::Enabled, true);
    market_configs.swap = config(ConfigOption::Disabled, true);
    market_manager.set_market_configs(market_id, market_configs);

    // Bidders withdraw sale tokens.
    set_contract_address(alice());
    market_manager.collect_order(market_id, id_1);
    market_manager.collect_order(market_id, id_3);
}

#[test]
#[should_panic(expected: ('SwapDisabled', 'ENTRYPOINT_FAILED',))]
#[available_gas(1000000000)]
fn test_dutch_auction_swap_by_bidder() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token, market_id) = before();

    set_contract_address(alice());
    market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );
}

#[test]
#[should_panic(expected: ('CreateAskDisabled', 'ENTRYPOINT_FAILED',))]
#[available_gas(1000000000)]
fn test_dutch_auction_ask_order() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token, market_id) = before();

    set_contract_address(alice());
    market_manager.create_order(market_id, false, 8388600 + 0, to_e18(10000));
}

#[test]
#[should_panic(expected: ('AddLiqDisabled', 'ENTRYPOINT_FAILED',))]
#[available_gas(1000000000)]
fn test_dutch_auction_liquidity_position() {
    // Deploy market manager and tokens.
    let (market_manager, base_token, quote_token, market_id) = before();

    set_contract_address(alice());
    market_manager
        .modify_position(
            market_id, 8388600 + 0, 8388600 + 10, I256Trait::new(to_e18(10000), false)
        );
}

#[test]
#[should_panic(expected: ('CreateBidDisabled', 'ENTRYPOINT_FAILED',))]
#[available_gas(1000000000)]
fn test_dutch_auction_bid_after_auction_ends() {
    let (market_manager, base_token, quote_token, market_id) = before();

    set_contract_address(owner());
    let mut market_configs = market_manager.market_configs(market_id);
    market_configs.create_bid = config(ConfigOption::Disabled, true);
    market_configs.collect_order = config(ConfigOption::Disabled, false);
    market_manager.set_market_configs(market_id, market_configs);

    set_contract_address(alice());
    market_manager.create_order(market_id, true, 8388600 + 0, to_e18(10000));
}

#[test]
#[should_panic(expected: ('SwapDisabled', 'ENTRYPOINT_FAILED',))]
#[available_gas(1000000000)]
fn test_dutch_auction_swap_by_bidder_after_sale_ends() {
    let (market_manager, base_token, quote_token, market_id) = before();

    set_contract_address(owner());
    let mut market_configs = market_manager.market_configs(market_id);
    market_configs.create_bid = config(ConfigOption::Disabled, true);
    market_configs.collect_order = config(ConfigOption::Disabled, false);
    market_manager.set_market_configs(market_id, market_configs);

    set_contract_address(alice());
    market_manager
        .swap(
            market_id, true, to_e18(1), true, Option::None(()), Option::None(()), Option::None(())
        );
}
