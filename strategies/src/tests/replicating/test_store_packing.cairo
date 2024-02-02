// Core lib imports.
use starknet::deploy_syscall;
use starknet::contract_address::contract_address_const;
use starknet::testing::set_contract_address;

// Local imports.
use amm::types::core::PositionInfo;
use strategies::strategies::replicating::mocks::store_packing_contract::{
    StorePackingContract, IStorePackingContractDispatcher, IStorePackingContractDispatcherTrait
};
use strategies::strategies::replicating::types::{StrategyParams, StrategyState};

// External imports.
use snforge_std::{
    PrintTrait, declare, ContractClass, ContractClassTrait, start_prank, stop_prank, CheatTarget,
    spy_events, SpyOn, EventSpy, EventAssertions, EventFetcher, start_warp
};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> IStorePackingContractDispatcher {
    // Deploy store packing contract.
    let class = declare('StorePackingContract');
    let contract_address = class.deploy(@array![]).unwrap();
    IStorePackingContractDispatcher { contract_address }
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
fn test_store_packing_strategy_params() {
    let store_packing_contract = before();

    let strategy_params = StrategyParams {
        min_spread: 15,
        range: 15000,
        max_delta: 2532,
        allow_deposits: true,
        use_whitelist: false,
        base_currency_id: 12893128793123,
        quote_currency_id: 128931287,
        min_sources: 12,
        max_age: 3123712,
    };

    store_packing_contract.set_strategy_params(1, strategy_params);
    let unpacked = store_packing_contract.get_strategy_params(1);

    assert(unpacked.min_spread == strategy_params.min_spread, 'Strategy params: min spread');
    assert(unpacked.range == strategy_params.range, 'Strategy params: range');
    assert(unpacked.max_delta == strategy_params.max_delta, 'Strategy params: max delta');
    assert(
        unpacked.allow_deposits == strategy_params.allow_deposits, 'Strategy params: allow deposits'
    );
    assert(
        unpacked.use_whitelist == strategy_params.use_whitelist, 'Strategy params: use whitelist'
    );
    assert(
        unpacked.base_currency_id == strategy_params.base_currency_id,
        'Strategy params: base curr id'
    );
    assert(
        unpacked.quote_currency_id == strategy_params.quote_currency_id,
        'Strategy params: quote curr id'
    );
    assert(unpacked.min_sources == strategy_params.min_sources, 'Strategy params: min sources');
    assert(unpacked.max_age == strategy_params.max_age, 'Strategy params: max age');
}

#[test]
fn test_store_packing_strategy_state() {
    let store_packing_contract = before();

    let strategy_state = StrategyState {
        base_reserves: 1389123122000000000000000000000,
        quote_reserves: 2401299999999999999999999999999,
        bid: PositionInfo {
            lower_limit: 85719030, upper_limit: 90719030, liquidity: 123900000000000000000000
        },
        ask: PositionInfo {
            lower_limit: 105719030, upper_limit: 110719030, liquidity: 123900000000000000000000
        },
        is_initialised: true,
        is_paused: false,
    };

    store_packing_contract.set_strategy_state(1, strategy_state);
    let unpacked = store_packing_contract.get_strategy_state(1);

    assert(unpacked.base_reserves == strategy_state.base_reserves, 'Strategy state: base reserves');
    assert(
        unpacked.quote_reserves == strategy_state.quote_reserves, 'Strategy state: quote reserves'
    );
    assert(unpacked.bid == strategy_state.bid, 'Strategy state: bid');
    assert(unpacked.ask == strategy_state.ask, 'Strategy state: ask');
    assert(
        unpacked.is_initialised == strategy_state.is_initialised, 'Strategy state: is initialised'
    );
    assert(unpacked.is_paused == strategy_state.is_paused, 'Strategy state: is paused');
}
