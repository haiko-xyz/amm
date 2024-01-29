use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::syscalls::call_contract_syscall;
use starknet::info::get_block_timestamp;
use integer::BoundedU32;

use amm::libraries::id;
use amm::types::i128::I128Trait;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IStrategy::{IStrategyDispatcher, IStrategyDispatcherTrait};

use snforge_std::{start_prank, stop_prank, PrintTrait, CheatTarget};

#[test]
#[fork("TESTNET")]
fn test_failing_fee_factor() {
    let market_manager_addr = contract_address_const::<
        0xbaa40f0fc9b0e069639a88c8f642d6f2e85e18332060592acf600e46564204
    >();
    let strategy_addr = contract_address_const::<
        0xbde0fa5bc66282fac21655f029b9727f306048de75afdb88042517beb0aa24
    >();
    let market_id = 0x0288d0abcfa6f2d23cd10584f502b4095d14cef132d632da876a7089c1310072;

    let market_manager = IMarketManagerDispatcher { contract_address: market_manager_addr };
    let strategy = IStrategyDispatcher { contract_address: strategy_addr };
    let placed_positions = strategy.placed_positions(market_id);
    let queued_positions = strategy.queued_positions(market_id, Option::None(()));

    let placed_bid = *placed_positions.at(0);
    let placed_ask = *placed_positions.at(1);
    let queued_bid = *queued_positions.at(0);
    let queued_ask = *queued_positions.at(1);

    'Placed bid'.print();
    placed_bid.lower_limit.print();
    placed_bid.upper_limit.print();
    placed_bid.liquidity.print();
    'Placed ask'.print();
    placed_ask.lower_limit.print();
    placed_ask.upper_limit.print();
    placed_ask.liquidity.print();
    'Queued bid'.print();
    queued_bid.lower_limit.print();
    queued_bid.upper_limit.print();
    queued_bid.liquidity.print();
    'Queued ask'.print();
    queued_ask.lower_limit.print();
    queued_ask.upper_limit.print();
    queued_ask.liquidity.print();

    let placed_bid_pos_id = id::position_id(
        market_id, strategy_addr.into(), placed_bid.lower_limit, placed_bid.upper_limit
    );
    let placed_bid_amts = market_manager.amounts_inside_position(placed_bid_pos_id);
    let placed_ask_pos_id = id::position_id(
        market_id, strategy_addr.into(), placed_ask.lower_limit, placed_ask.upper_limit
    );
    let placed_ask_amts = market_manager.amounts_inside_position(placed_ask_pos_id);
    let queued_bid_pos_id = id::position_id(
        market_id, strategy_addr.into(), queued_bid.lower_limit, queued_bid.upper_limit
    );
    let (base_amt, quote_amt, base_fees, quote_fees) = market_manager
        .amounts_inside_position(queued_bid_pos_id);
    let queued_ask_pos_id = id::position_id(
        market_id, strategy_addr.into(), queued_ask.lower_limit, queued_ask.upper_limit
    );
    let queued_ask_amts = market_manager.amounts_inside_position(queued_ask_pos_id);
    'q bid amts and fees'.print();
    base_amt.print();
    quote_amt.print();
    base_fees.print();
    quote_fees.print();

    let lower_limit_info = market_manager.limit_info(market_id, queued_bid.lower_limit);
    let upper_limit_info = market_manager.limit_info(market_id, queued_bid.upper_limit);
    let market_state = market_manager.market_state(market_id);

    'curr limit'.print();
    market_state.curr_limit.print();
    'lower limit'.print();
    queued_bid.lower_limit.print();
    'upper limit'.print();
    queued_bid.upper_limit.print();

    'lower limit liquidity'.print();
    lower_limit_info.liquidity.print();
    'upper limit liquidity'.print();
    upper_limit_info.liquidity.print();
    'lower limit quote fee factor'.print();
    lower_limit_info.quote_fee_factor.print();
    'upper limit quote fee factor'.print();
    upper_limit_info.quote_fee_factor.print();
    'market state quote fee factor'.print();
    market_state.quote_fee_factor.print();

    start_prank(CheatTarget::One(market_manager_addr), strategy_addr);
    'Removing placed bid'.print();
    market_manager
        .modify_position(
            market_id,
            placed_bid.lower_limit,
            placed_bid.upper_limit,
            I128Trait::new(placed_bid.liquidity, true)
        );
    'Removing placed ask'.print();
    market_manager
        .modify_position(
            market_id,
            placed_ask.lower_limit,
            placed_ask.upper_limit,
            I128Trait::new(placed_ask.liquidity, true)
        );
    'Adding queued bid'.print();
    market_manager
        .modify_position(
            market_id,
            queued_bid.lower_limit,
            queued_bid.upper_limit,
            I128Trait::new(queued_bid.liquidity, false)
        );
    'Adding queued ask'.print();
    market_manager
        .modify_position(
            market_id,
            queued_ask.lower_limit,
            queued_ask.upper_limit,
            I128Trait::new(queued_ask.liquidity, false)
        );
}
