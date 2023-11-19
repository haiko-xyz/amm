use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::syscalls::call_contract_syscall;

use amm::types::core::{SwapParams, Position};
use amm::types::i256::I256Trait;
use amm::libraries::id;
use amm::libraries::liquidity as liquidity_helpers;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IQuoter::{IQuoterDispatcher, IQuoterDispatcherTrait};
use snforge_std::{start_prank, stop_prank, PrintTrait};

#[derive(Drop, Copy, Serde, starknet::Store)]
struct PositionInfo {
    lower_limit: u32,
    upper_limit: u32,
    liquidity: u256,
}

#[starknet::interface]
trait ILegacyStrategy<TContractState> {
    fn market_manager(self: @TContractState) -> ContractAddress;
    fn market_id(self: @TContractState) -> felt252;
    fn strategy_name(self: @TContractState) -> felt252;
    fn strategy_symbol(self: @TContractState) -> felt252;
    fn bid(self: @TContractState) -> PositionInfo;
    fn ask(self: @TContractState) -> PositionInfo;
    fn update_positions(ref self: TContractState);
    fn cleanup(ref self: TContractState);
    fn get_bid_ask(self: @TContractState) -> (u32, u32);
}

#[starknet::interface]
trait ILegacyMarketManager<TContractState> {
    fn position(self: @TContractState, position_id: felt252) -> Position;
}

#[test]
#[fork("TESTNET")]
fn test_strategy_update_using_forked_state() {
    let market_manager_addr = contract_address_const::<
        0x0761298ceec8306112ba3341d71088dba09944bb371e9cf5f191b7fae9fe19ed
    >();
    let strategy_addr = contract_address_const::<
        0x05adb7246dec49c092d781b0f9f9dbef88d3d4e645ef1caaea9f8699453f5462
    >();
    let market_id: felt252 = 0x7a16b2fd8115d0916af5c17250ff5d0c09f988952146bea315e90875619fb4;

    // start_prank(strategy_addr, market_manager_addr);
    let strategy = ILegacyStrategyDispatcher { contract_address: strategy_addr };
    // strategy.update_positions();
    // stop_prank(strategy_addr);

    start_prank(market_manager_addr, strategy_addr);

    let market_manager = IMarketManagerDispatcher { contract_address: market_manager_addr };
    // Remove existing positions.
    let bid = strategy.bid();
    let ask = strategy.ask();
    market_manager
        .modify_position(
            market_id, bid.lower_limit, bid.upper_limit, I256Trait::new(bid.liquidity, true)
        );
    market_manager
        .modify_position(
            market_id, ask.lower_limit, ask.upper_limit, I256Trait::new(ask.liquidity, true)
        );
    'removed existing positions'.print();

    // Add new positions.
    let (bid_upper_limit, ask_lower_limit) = strategy.get_bid_ask();
    let bid_lower_limit = bid_upper_limit - 5000;
    // market_manager.modify_position(
    //     market_id, bid_lower_limit, bid_upper_limit, I256Trait::new(bid.liquidity, false)
    // );
    let position_id = id::position_id(
        market_id, strategy_addr.into(), bid_lower_limit, bid_upper_limit
    );
    let position = ILegacyMarketManagerDispatcher { contract_address: market_manager_addr }
        .position(position_id);
    let market_state = market_manager.market_state(market_id);

    let lower_limit_info = market_manager.limit_info(market_id, bid_lower_limit);
    let upper_limit_info = market_manager.limit_info(market_id, bid_upper_limit);

    'bid lower limit'.print();
    bid_lower_limit.print();
    'curr limit'.print();
    market_state.curr_limit.print();
    'liquidity before'.print();
    lower_limit_info.liquidity.print();
    if lower_limit_info.liquidity == 0 && bid_lower_limit <= market_state.curr_limit {
        'init lower bff at market'.print();
    } else {
        'init lower bff at 0'.print();
    }

    'bid upper limit'.print();
    bid_upper_limit.print();
    'curr limit'.print();
    market_state.curr_limit.print();
    'liquidity before'.print();
    upper_limit_info.liquidity.print();
    if upper_limit_info.liquidity == 0 && bid_upper_limit <= market_state.curr_limit {
        'init upper bff at market'.print();
    } else {
        'init upper bff at 0'.print();
    }

    'added new positions'.print();

    stop_prank(market_manager_addr);
}
