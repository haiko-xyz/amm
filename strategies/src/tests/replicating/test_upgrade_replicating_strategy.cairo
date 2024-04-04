use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::syscalls::call_contract_syscall;
use starknet::get_block_timestamp;
use starknet::class_hash::ClassHash;

use amm::libraries::id;
use amm::libraries::math::math;
use amm::types::i128::I128Trait;
use amm::interfaces::IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait};
use amm::interfaces::IStrategy::{IStrategyDispatcher, IStrategyDispatcherTrait};
use amm::types::core::{MarketState, PositionInfo};
use amm::tests::common::utils::to_e18;
use strategies::strategies::replicating::interface::{
    IReplicatingStrategyDispatcher, IReplicatingStrategyDispatcherTrait
};

use snforge_std::{start_prank, stop_prank, CheatTarget, declare, ContractClass, ContractClassTrait};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

// This is a fork test that tests the functionality of the AMM after upgrading to 
// a new class hash.
// It is disabled by default and enabled only for contract upgrades.
// TODO: replace RPC URL with private one before running this test.
// Run with `snforge test test_upgrade_replicating_strategy --max-n-steps 4294967295` to override step limit.
#[test]
#[fork("MAINNET")]
fn test_upgrade_replicating_strategy() {
    // Define constants.
    let owner = contract_address_const::<
        0x043777A54D5e36179709060698118f1F6F5553Ca1918D1004b07640dFc425000
    >();
    let lp = contract_address_const::<
        0x0469334529F1414f16B7eC53Ce369e79928847cC6A022993f155B44D3378C50C
    >();
    let market_manager_addr = contract_address_const::<
        0x38925b0bcf4dce081042ca26a96300d9e181b910328db54a6c89e5451503f5
    >();
    let strategy_addr = contract_address_const::<
        0x2ffce9d48390d497f7dfafa9dfd22025d9c285135bcc26c955aea8741f081d2
    >();
    let regular_market_id = 0x2ed8f2415d626661678b075d24dee9f2853e1bfbd45660ad78d97a0930c6699;
    let strategy_market_id = 0xf62b32bcbb3f2662000bdd8f3c51b528f0131ed7ca6a964a3004b4cc0d586b;
    let old_market_manager_class: felt252 =
        0x731820e650cf7522d36f262b26f8ba0961a916ec647e14a167f95dfd385d83a;
    let old_strategy_class: felt252 =
        0x3ffd318f6a7db6f8c3c1433024a94e66cd8c692e11d6eda39e7008d0647b380;

    // Define dispatchers.
    let market_manager = IMarketManagerDispatcher { contract_address: market_manager_addr };
    let market_info = market_manager.market_info(regular_market_id);
    let strategy = IReplicatingStrategyDispatcher { contract_address: strategy_addr };
    let strategy_alt = IStrategyDispatcher { contract_address: strategy_addr };
    let base_token = ERC20ABIDispatcher { contract_address: market_info.base_token };
    let quote_token = ERC20ABIDispatcher { contract_address: market_info.quote_token };

    // Declare new class hash and upgrade contract.
    start_prank(CheatTarget::One(market_manager_addr), owner);
    let new_market_manager_class = declare("MarketManager");
    market_manager.upgrade(new_market_manager_class.class_hash);
    println!("Upgraded MarketManager");
    start_prank(CheatTarget::One(strategy_addr), owner);
    let new_strategy_class = declare("ReplicatingStrategy");
    strategy.upgrade(new_strategy_class.class_hash);
    println!("Upgraded ReplicatingStrategy");

    // First approve the contract to spend the tokens.
    let base_amount = to_e18(1000);
    let quote_amount = 1000 * 1000000;
    // Approve Market Manager
    start_prank(CheatTarget::One(market_info.base_token), lp);
    base_token.approve(market_manager_addr, base_amount);
    stop_prank(CheatTarget::One(market_info.base_token));
    start_prank(CheatTarget::One(market_info.quote_token), lp);
    quote_token.approve(market_manager_addr, quote_amount);
    stop_prank(CheatTarget::One(market_info.quote_token));
    // Approve Replicating Strategy
    start_prank(CheatTarget::One(market_info.base_token), lp);
    base_token.approve(strategy_addr, base_amount);
    stop_prank(CheatTarget::One(market_info.base_token));
    start_prank(CheatTarget::One(market_info.quote_token), lp);
    quote_token.approve(strategy_addr, quote_amount);
    stop_prank(CheatTarget::One(market_info.quote_token));
    // Approve Replicating Strategy to spend Market Manager tokens
    start_prank(CheatTarget::One(market_info.base_token), market_manager_addr);
    base_token.approve(strategy_addr, base_amount);
    stop_prank(CheatTarget::One(market_info.base_token));
    start_prank(CheatTarget::One(market_info.quote_token), market_manager_addr);
    quote_token.approve(strategy_addr, quote_amount);
    stop_prank(CheatTarget::One(market_info.quote_token));
    println!("Approved tokens");

    // Swap STRK to get some USDC.
    start_prank(CheatTarget::One(market_manager_addr), lp);
    market_manager
        .swap(
            regular_market_id,
            false,
            to_e18(500),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );
    stop_prank(CheatTarget::One(market_manager_addr));
    println!("Swapped to obtain USDC");

    // Test common ops.

    // 1. Deposit to strategy vault.
    start_prank(CheatTarget::One(strategy_addr), lp);
    let strategy_state = strategy.strategy_state(strategy_market_id);
    let base_deposit = to_e18(100);
    let quote_deposit = math::mul_div(
        base_deposit, strategy_state.quote_reserves, strategy_state.base_reserves, false
    );
    let (_, _, shares) = strategy.deposit(strategy_market_id, base_deposit, quote_deposit);
    println!("1. Deposited to vault");

    // 2. Partially withdraw from strategy vault.
    strategy.withdraw(strategy_market_id, shares / 2);
    println!("2. Partially withdrawn from vault");

    // 3. Swap against strategy vault.
    // This must be done as market manager to overcome a limitation with `prank` that causes tx to 
    // revert for a non-strategy caller.
    start_prank(CheatTarget::One(market_manager_addr), strategy_addr);
    start_prank(CheatTarget::One(strategy_addr), market_manager_addr);
    let mut market_state = market_manager.market_state(strategy_market_id);
    println!("* START STRATEGY STATE *");
    let mut bid = strategy.bid(strategy_market_id);
    let mut ask = strategy.ask(strategy_market_id);
    print_strategy_state(market_state, bid, ask);
    println!("* QUEUED POSITIONS (uncond) *");
    let queued_positions = strategy_alt.queued_positions(strategy_market_id, Option::None(()));
    print_strategy_state(market_state, *queued_positions.at(0), *queued_positions.at(1));
    market_manager
        .swap(
            strategy_market_id,
            false,
            to_e18(100),
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );
    println!("* AFTER SELL SWAP *");
    market_state = market_manager.market_state(strategy_market_id);
    bid = strategy.bid(strategy_market_id);
    ask = strategy.ask(strategy_market_id);
    print_strategy_state(market_state, bid, ask);
    market_manager
        .swap(
            strategy_market_id,
            true,
            50 * 1000000,
            true,
            Option::None(()),
            Option::None(()),
            Option::None(())
        );
    println!("* AFTER BUY SWAP *");
    market_state = market_manager.market_state(strategy_market_id);
    bid = strategy.bid(strategy_market_id);
    ask = strategy.ask(strategy_market_id);
    print_strategy_state(market_state, bid, ask);
    println!("3. Swapped against vault");

    // 4. Fully withdraw from strategy vault.
    start_prank(CheatTarget::One(strategy_addr), lp);
    strategy.withdraw(strategy_market_id, shares - shares / 2);
    println!("4. Fully withdrawn from vault");

    // 5. Downgrade back to old class hash (to test upgrade() function)
    start_prank(CheatTarget::One(market_manager_addr), owner);
    market_manager.upgrade(old_market_manager_class.try_into().unwrap());
    println!("5a. Downgraded MarketManager");
    start_prank(CheatTarget::One(strategy_addr), owner);
    strategy.upgrade(old_strategy_class.try_into().unwrap());
    println!("5b. Downgraded ReplicatingStrategy");
}

fn print_strategy_state(market_state: MarketState, bid: PositionInfo, ask: PositionInfo) {
    println!("[Curr limit] {}", market_state.curr_limit);
    println!(
        "[Bid] Lower: {}, Upper: {}, Liquidity: {}", bid.lower_limit, bid.upper_limit, bid.liquidity
    );
    println!(
        "[Ask] Lower: {}, Upper: {}, Liquidity: {}", ask.lower_limit, ask.upper_limit, ask.liquidity
    );
}
