use starknet::ContractAddress;
use starknet::testing::set_contract_address;

use amm::libraries::id;
use amm::libraries::constants::{OFFSET, MAX_LIMIT};
use amm::libraries::math::price_math;
use amm::libraries::math::liquidity_math;
use amm::interfaces::IMarketManager::{
    IMarketManager, IMarketManagerDispatcher, IMarketManagerDispatcherTrait
};
use amm::types::core::{MarketState};
use amm::types::i256::{i256, I256Trait};
use amm::interfaces::IERC20::{IERC20Dispatcher, IERC20DispatcherTrait};
use amm::tests::helpers::actions::{
    market_manager::{deploy_market_manager, create_market, modify_position},
    token::{deploy_token, fund, approve},
    params::{
        owner, alice, treasury, default_token_params, default_market_params, modify_position_params,
        swap_params
    }
};
use amm::tests::helpers::utils::encode_sqrt_price;
use amm::tests::helpers::actions::market_manager::swap;
use amm::libraries::liquidity as liquidity_helpers;
use amm::libraries::constants::MAX;
use strategies::tests::replicating::{
    actions::{deploy_replicating_strategy, deploy_mock_pragma_oracle},
    mock_pragma_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
};
use strategies::strategies::replicating::{
    replicating_strategy::{IReplicatingStrategyDispatcher, IReplicatingStrategyDispatcherTrait},
    pragma_interfaces::{DataType, PragmaPricesResponse},
};
use strategies::tests::utils::{to_e18, to_e28, approx_eq};
use integer::BoundedU128;

use debug::PrintTrait;

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> (
    IMarketManagerDispatcher,
    IERC20Dispatcher,
    IERC20Dispatcher,
    felt252,
    IMockPragmaOracleDispatcher,
    IReplicatingStrategyDispatcher,
) {
    // Get default owner.
    let owner = owner();

    // Deploy market manager.
    let market_manager = deploy_market_manager(owner);

    // Deploy tokens.
    let (treasury, base_token_params, quote_token_params) = default_token_params();
    let base_token = deploy_token(base_token_params);
    let quote_token = deploy_token(quote_token_params);

    // Deploy oracle contract.
    let oracle = deploy_mock_pragma_oracle(owner);

    // Deploy replicating strategy.
    let strategy = deploy_replicating_strategy(owner);

    // Create market.
    let mut params = default_market_params();
    params.width = 10;
    params.base_token = base_token.contract_address;
    params.quote_token = quote_token.contract_address;
    params.start_limit = 9127310; // initial limit
    params.strategy = strategy.contract_address;
    let market_id = create_market(market_manager, params);

    // Initialise strategy.
    strategy
        .initialise(
            'ETH-USDC Replicating 10 0.2%',
            'ETH-USDC REPL-10-0.2%',
            market_manager.contract_address,
            market_id,
            oracle.contract_address,
            'ETH',
            'USDC',
            100000000000000000000, // 10^20 = 10^28 / 10^8
            10, // ~0.01% min spread
            10000, // ~20% slippage
            200, // ~0.2% delta
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

    // Fund LP with initial token balances and approve strategy and market manager as spenders.
    fund(base_token, alice(), base_amount);
    fund(quote_token, alice(), quote_amount);
    approve(base_token, alice(), market_manager.contract_address, base_amount);
    approve(quote_token, alice(), market_manager.contract_address, quote_amount);
    approve(base_token, alice(), strategy.contract_address, base_amount);
    approve(quote_token, alice(), strategy.contract_address, quote_amount);

    (market_manager, base_token, quote_token, market_id, oracle, strategy)
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(10000000000)]
fn test_failing_swap() {
    let (market_manager, base_token, quote_token, market_id, oracle, strategy) = before();

    // Set price.
    oracle.set_data_with_USD_hop('ETH', 'USDC', 161650000000);

    // Deposit initial.
    set_contract_address(owner());
    let initial_base_amount = to_e18(10000);
    let initial_quote_amount = to_e18(16330000);
    strategy.deposit_initial(initial_base_amount, initial_quote_amount);

    market_manager
        .swap(market_id, true, 100000000000000000000, true, Option::None(()), Option::None(()));

    oracle.set_data_with_USD_hop('ETH', 'USDC', 161750000000);
    market_manager
        .swap(market_id, false, 120000000000000000, true, Option::None(()), Option::None(()));

    oracle.set_data_with_USD_hop('ETH', 'USDC', 161850000000);
    market_manager.swap(market_id, false, 2, false, Option::None(()), Option::None(()));

    let order_id = market_manager.create_order(market_id, true, 9126500, to_e18(25));

    oracle.set_data_with_USD_hop('ETH', 'USDC', 162250000000);
    market_manager.swap(market_id, true, 10000000000, true, Option::None(()), Option::None(()));
}
// {
//   "data": {
//     "swaps": [
//       {
//         "market": {
//           "id": "0x187ce35ee40479684c63994489f2208ccab90e2d61d3cc4bd18ce343d48139b"
//         },
//         "timestamp": 1696540384,
//         "isBuy": false,
//         "exactInput": false,
//         "amountIn": "0.000000000000000001",
//         "amountOut": "0.000000000000000002"
//       },
//       {
//         "market": {
//           "id": "0x6ed8eef55a7f2e98b2aab771084a2678c7fd4d2e77cac98024413ffa9a35050"
//         },
//         "timestamp": 1696541316,
//         "isBuy": true,
//         "exactInput": true,
//         "amountIn": "0.00000001",
//         "amountOut": "0.000000000005964222"
//       },
//       {
//         "market": {
//           "id": "0x187ce35ee40479684c63994489f2208ccab90e2d61d3cc4bd18ce343d48139b"
//         },
//         "timestamp": 1696541500,
//         "isBuy": true,
//         "exactInput": true,
//         "amountIn": "0.00000001",
//         "amountOut": "0.000000000006174792"
//       }
//     ]
//   }
// }


