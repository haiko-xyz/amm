// Local imports.
use amm::libraries::constants::OFFSET;
use amm::libraries::math::{fee_math, price_math};
use amm::types::i256::I256Trait;
use amm::contracts::market_manager::MarketManager;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market},
    token::{declare_token, deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, treasury, token_params, default_market_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, encode_sqrt_price};

// External imports.
use snforge_std::{start_prank, declare, PrintTrait, spy_events, SpyOn, EventSpy, EventAssertions};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher) {
    // Deploy market manager.
    let class = declare('MarketManager');
    let market_manager = deploy_market_manager(class, owner());

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let erc20_class = declare_token();
    let base_token = deploy_token(erc20_class, base_token_params);
    let quote_token = deploy_token(erc20_class, quote_token_params);

    // Fund LP with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000000000000);
    let initial_quote_amount = to_e28(10000000000000000000000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);

    (market_manager, base_token, quote_token)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_create_market_event() {
    let (market_manager, base_token, quote_token) = before();

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = OFFSET;
    params.width = 1;

    let mut spy = spy_events(SpyOn::One(market_manager.contract_address));
    let market_id = create_market(market_manager, params);

    spy
        .assert_emitted(
            @array![
                (
                    market_manager.contract_address,
                    MarketManager::Event::CreateMarket(
                        MarketManager::CreateMarket {
                            market_id,
                            base_token: base_token.contract_address,
                            quote_token: quote_token.contract_address,
                            width: params.width,
                            strategy: params.strategy,
                            swap_fee_rate: params.swap_fee_rate,
                            fee_controller: params.fee_controller,
                            start_limit: params.start_limit,
                            start_sqrt_price: price_math::limit_to_sqrt_price(
                                params.start_limit, params.width
                            ),
                            controller: params.controller,
                        }
                    )
                ),
                (
                    market_manager.contract_address,
                    MarketManager::Event::ChangeProtocolShare(
                        MarketManager::ChangeProtocolShare {
                            market_id, protocol_share: params.protocol_share,
                        }
                    )
                )
            ]
        );
}
