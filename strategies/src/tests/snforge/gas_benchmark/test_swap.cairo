// Core lib imports.
use cmp::{min, max};
use starknet::ContractAddress;
use dict::{Felt252Dict, Felt252DictTrait};

// Local imports.
use amm::libraries::constants::{MAX, OFFSET, MAX_LIMIT};
use amm::libraries::math::fee_math;
use amm::types::core::{SwapParams, PositionInfo};
use amm::libraries::id;
use amm::libraries::liquidity as liquidity_helpers;
use amm::types::core::{MarketState, LimitInfo};
use amm::types::i256::{i256, I256Trait, I256Zeroable};
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
    use amm::interfaces::IStrategy::{IStrategyDispatcher, IStrategyDispatcherTrait};
use strategies::strategies::replicating::{
    replicating_strategy::{IReplicatingStrategyDispatcher, IReplicatingStrategyDispatcherTrait},
    pragma_interfaces::{DataType, PragmaPricesResponse},
    mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait}
};
use amm::tests::snforge::helpers::{
    market_manager::{deploy_market_manager, create_market, modify_position, swap, swap_multiple},
    token::{declare_token, deploy_token, fund, approve},
};
use amm::tests::common::params::{
    owner, alice, treasury, token_params, default_market_params, modify_position_params,
    swap_params, swap_multiple_params, default_token_params
};
use amm::tests::common::utils::{to_e28, to_e18, approx_eq};
use strategies::tests::snforge::replicating::helpers::{
    deploy_replicating_strategy, deploy_mock_pragma_oracle
};

// External imports.
use snforge_std::{start_prank, stop_prank, PrintTrait, declare, ContractClass, ContractClassTrait};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

fn _before(
    width: u32, is_concentrated: bool, allow_orders: bool, allow_positions: bool
) -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let manager_class = declare('MarketManager');
    let market_manager = deploy_market_manager(manager_class, owner);

    // Deploy tokens.
    let erc20_class = declare_token();
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(erc20_class, base_token_params);
    let quote_token = deploy_token(erc20_class, quote_token_params);

    let strategy = deploy_replicating_strategy(owner());

    // Create market.
    let mut params = default_market_params();
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.width = width;
    params.start_limit = OFFSET - 230260; // initial limit
    params.is_concentrated = is_concentrated;
    params.allow_orders = allow_orders;
    params.allow_positions = allow_positions;
    params.strategy = strategy.contract_address;
    let market_id = create_market(market_manager, params);

    // Fund LPs with initial token balances and approve market manager as spender.
    let initial_base_amount = to_e28(500000);
    let initial_quote_amount = to_e28(10000000);
    fund(base_token, alice(), initial_base_amount);
    fund(quote_token, alice(), initial_quote_amount);
    fund(base_token, owner(), initial_base_amount);
    fund(quote_token, owner(), initial_quote_amount);
    approve(base_token, alice(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, alice(), market_manager.contract_address, initial_quote_amount);
    approve(base_token, owner(), market_manager.contract_address, initial_base_amount);
    approve(quote_token, owner(), market_manager.contract_address, initial_quote_amount);
    approve(base_token, owner(), strategy.contract_address, initial_base_amount);
    approve(quote_token, owner(), strategy.contract_address, initial_quote_amount);

    let oracle = deploy_mock_pragma_oracle(owner);
    start_prank(strategy.contract_address, owner());
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

    // Set initial oracle price.
    oracle.set_data_with_USD_hop('ETH/USD', 'USDC/USD', 100000000); // 1

    // Deposit initial to strategy.
    strategy.deposit_initial(to_e18(50000), to_e18(50000));
    stop_prank(strategy.contract_address);
    
    // Create position
    let mut upper_limit = 8388600;
    let mut lower_limit = 8368590;
    let mut liquidity = I256Trait::new(to_e18(1000000000000), false);

    let params = modify_position_params(alice(), market_id, lower_limit, upper_limit, liquidity);
    
    let (base_amount, quote_amount, base_fees, quote_fees) = modify_position(
        market_manager, params
    );
    (market_manager, base_token, quote_token, market_id)
}

fn before(
    width: u32
) -> (IMarketManagerDispatcher, ERC20ABIDispatcher, ERC20ABIDispatcher, felt252) {
    _before(width, true, true, true)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_single_swap() {
    let (market_manager, base_token, quote_token, market_id) = before(width: 1);

    let curr_sqrt_price = market_manager.market_state(market_id).curr_sqrt_price;
    let mut is_buy = false;
    let exact_input = true;
    let amount = 100;
    let sqrt_price = Option::Some(curr_sqrt_price - 1000);
    let threshold_amount = Option::Some(0);

    let mut swap_params = swap_params(
        alice(), market_id, is_buy, exact_input, amount, sqrt_price, threshold_amount, Option::None,
    );
    let gas_before = testing::get_available_gas();
    gas::withdraw_gas().unwrap();
    swap(market_manager, swap_params);

    'single swap gas used'.print();
    (gas_before - testing::get_available_gas()).print(); 
}
