use starknet::deploy_syscall;
use starknet::contract_address::contract_address_const;
use starknet::testing::set_contract_address;

use strategies::strategies::replicating::mocks::store_packing_contract::{
    StorePackingContract, IStorePackingContractDispatcher, IStorePackingContractDispatcherTrait
};
use strategies::strategies::replicating::types::{StrategyParams, OracleParams, StrategyState};

////////////////////////////////
// SETUP
////////////////////////////////

fn before() -> IStorePackingContractDispatcher {
    // Deploy store packing contract.
    let constructor_calldata = ArrayTrait::<felt252>::new();
    let (deployed_address, _) = deploy_syscall(
        StorePackingContract::TEST_CLASS_HASH.try_into().unwrap(),
        0,
        constructor_calldata.span(),
        false
    )
        .unwrap();

    IStorePackingContractDispatcher { contract_address: deployed_address }
}

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(100000000)]
fn test_store_packing_strategy_params() {
    let store_packing_contract = before();

    let strategy_params = StrategyParams {
        min_spread: 15, range: 15000, max_delta: 2532, allow_deposits: true, use_whitelist: false,
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
}

#[test]
#[available_gas(100000000)]
fn test_store_packing_oracle_params() {
    let store_packing_contract = before();

    let oracle_params = OracleParams {
        base_currency_id: 12893128793123,
        quote_currency_id: 128931287,
        min_sources: 12,
        max_age: 3123712,
    };

    store_packing_contract.set_oracle_params(1, oracle_params);
    let unpacked = store_packing_contract.get_oracle_params(1);

    assert(
        unpacked.base_currency_id == oracle_params.base_currency_id, 'Oracle params: base curr id'
    );
    assert(
        unpacked.quote_currency_id == oracle_params.quote_currency_id,
        'Oracle params: quote curr id'
    );
    assert(unpacked.min_sources == oracle_params.min_sources, 'Oracle params: min sources');
    assert(unpacked.max_age == oracle_params.max_age, 'Oracle params: max age');
}

#[test]
#[available_gas(100000000)]
fn test_store_packing_strategy_state() {
    let store_packing_contract = before();

    let strategy_state = StrategyState {
        base_reserves: 1389123122000000000000000000000,
        quote_reserves: 2401299999999999999999999999999,
        bid_lower: 85719030,
        bid_upper: 90719030,
        ask_lower: 105719030,
        ask_upper: 110719030,
        is_initialised: true,
        is_paused: false,
    };

    store_packing_contract.set_strategy_state(1, strategy_state);
    let unpacked = store_packing_contract.get_strategy_state(1);

    assert(unpacked.base_reserves == strategy_state.base_reserves, 'Strategy state: base reserves');
    assert(
        unpacked.quote_reserves == strategy_state.quote_reserves, 'Strategy state: quote reserves'
    );
    assert(unpacked.bid_lower == strategy_state.bid_lower, 'Strategy state: bid lower limit');
    assert(unpacked.bid_upper == strategy_state.bid_upper, 'Strategy state: bid upper limit');
    assert(unpacked.ask_lower == strategy_state.ask_lower, 'Strategy state: ask lower limit');
    assert(unpacked.ask_upper == strategy_state.ask_upper, 'Strategy state: ask upper limit');
    assert(
        unpacked.is_initialised == strategy_state.is_initialised, 'Strategy state: is initialised'
    );
    assert(unpacked.is_paused == strategy_state.is_paused, 'Strategy state: is paused');
}
