use amm::types::core::MarketInfo;
use amm::libraries::id;
use debug::PrintTrait;
use starknet::{ContractAddress, contract_address_const};

////////////////////////////////
// TESTS
////////////////////////////////

struct PositionIdInfo {
    market_id: felt252,
    owner: felt252,
    lower_limit: u32,
    upper_limit: u32,
}

struct BatchIdInfo {
    market_id: felt252,
    limit: u32,
    nonce: u128,
}

struct OrderIdInfo {
    batch_id: felt252,
    owner: ContractAddress,
}

////////////////////////////////
// TESTS
////////////////////////////////

// Test IDs by changing each parameter and checking id has changed.
#[test]
fn test_market_id() {
    // Define base market info.
    let mut market_info = MarketInfo {
        base_token: contract_address_const::<0x123>(),
        quote_token: contract_address_const::<0x456>(),
        width: 1,
        strategy: contract_address_const::<0x999>(),
        swap_fee_rate: 25,
        fee_controller: contract_address_const::<0x0>(),
        controller: contract_address_const::<0x8888>(),
    };
    let mut market_id = id::market_id(market_info);

    // Vary base token.
    market_info.base_token = contract_address_const::<0x321>();
    let mut last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: base token');

    // Vary quote token.
    market_info.quote_token = contract_address_const::<0x654>();
    last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: quote token');

    // Vary width.
    market_info.width = 2;
    last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: width');

    // Vary strategy.
    market_info.strategy = contract_address_const::<0x888>();
    last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: strategy');

    // Vary swap fee rate.
    market_info.swap_fee_rate = 50;
    last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: swap fee rate');

    // Vary fee controller.
    market_info.fee_controller = contract_address_const::<0x777>();
    last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: fee controller');

    // Vary allow positions.
    market_info.controller = contract_address_const::<0x666>();
    last_market_id = market_id;
    market_id = id::market_id(market_info);
    assert(market_id != last_market_id, 'Market id: controller');
}

// Test IDs by changing each parameter and checking id has changed.
#[test]
fn test_position_id() {
    // Define base position.
    let mut position = PositionIdInfo {
        market_id: 123, owner: 0x777, lower_limit: 1000, upper_limit: 2000,
    };
    let mut position_id = id::position_id(
        position.market_id, position.owner, position.lower_limit, position.upper_limit
    );

    // Vary market id.
    position.market_id = 456;
    let mut last_position_id = position_id;
    let mut position_id = id::position_id(
        position.market_id, position.owner, position.lower_limit, position.upper_limit
    );
    assert(position_id != last_position_id, 'Posiiton id: market id');

    // Vary owner.
    position.owner = 0x888;
    last_position_id = position_id;
    position_id =
        id::position_id(
            position.market_id, position.owner, position.lower_limit, position.upper_limit
        );
    assert(position_id != last_position_id, 'Posiiton id: owner');

    // Vary lower limit.
    position.lower_limit = 2000;
    last_position_id = position_id;
    position_id =
        id::position_id(
            position.market_id, position.owner, position.lower_limit, position.upper_limit
        );
    assert(position_id != last_position_id, 'Posiiton id: lower limit');

    // Vary upper limit.
    position.upper_limit = 3000;
    last_position_id = position_id;
    position_id =
        id::position_id(
            position.market_id, position.owner, position.lower_limit, position.upper_limit
        );
    assert(position_id != last_position_id, 'Posiiton id: upper limit');
}

// Test IDs by changing each parameter and checking id has changed.
#[test]
fn test_batch_id() {
    // Define base batch.
    let mut batch = BatchIdInfo { market_id: 123, limit: 1000, nonce: 18, };
    let mut batch_id = id::batch_id(batch.market_id, batch.limit, batch.nonce);

    // Vary market id.
    batch.market_id = 456;
    let mut last_batch_id = batch_id;
    batch_id = id::batch_id(batch.market_id, batch.limit, batch.nonce);
    assert(batch_id != last_batch_id, 'Batch id: market id');

    // Vary limit.
    batch.limit = 2000;
    last_batch_id = batch_id;
    batch_id = id::batch_id(batch.market_id, batch.limit, batch.nonce);
    assert(batch_id != last_batch_id, 'Batch id: limit');

    // Vary nonce.
    batch.nonce = 19;
    last_batch_id = batch_id;
    batch_id = id::batch_id(batch.market_id, batch.limit, batch.nonce);
    assert(batch_id != last_batch_id, 'Batch id: nonce');
}


// Test IDs by changing each parameter and checking id has changed.
#[test]
fn test_order_id() {
    // Define base order.
    let mut order = OrderIdInfo { batch_id: 123, owner: contract_address_const::<0x777>(), };
    let mut order_id = id::order_id(order.batch_id, order.owner);

    // Vary market id.
    order.batch_id = 456;
    let mut last_order_id = order_id;
    order_id = id::order_id(order.batch_id, order.owner);
    assert(order_id != last_order_id, 'Order id: market id');

    // Vary owner.
    order.owner = contract_address_const::<0x888>();
    last_order_id = order_id;
    order_id = id::order_id(order.batch_id, order.owner);
    assert(order_id != last_order_id, 'Order id: owner');
}

////////////////////////////////
// ID GENERATORS
////////////////////////////////

// #[test]
// Used to quickly generate IDs, not for testing.
fn position_id_generator() {
    let market_id = 0x5027d547580851650aebe16b71643a1885e0b5b7eb7f16cd2439ae2f729a512;
    let owner = 0x1fdb6ce2bb27420c779b59c4329c13d23f224b6bc30359c392e0e0b3f358e27;
    let lower_limit = 7906625 + 732660;
    let upper_limit = 7906625 + 737660;
    let id = id::position_id(market_id, owner, lower_limit, upper_limit);
    println!("Position ID: {}", id);
    assert(true, id);
}

// #[test]
fn market_id_generator() {
    let base_token = contract_address_const::<
        0x041b47f933fcfdb696521b89a704a3662c5aa446ed8a29b352fb6fa9a748a8a3
    >();
    let quote_token = contract_address_const::<
        0x072b09174080f7d1f158b26f1c6639964f4c8568bd5bc1fc3580b3047e500e99
    >();
    let strategy = contract_address_const::<
        0x42382d318c5a094cbeccb5e5ae4594dffdbe235708c527a370327a1cde808e
    >();

    let market_info = MarketInfo {
        base_token,
        quote_token,
        width: 10,
        strategy,
        swap_fee_rate: 5,
        fee_controller: contract_address_const::<0x0>(),
        controller: contract_address_const::<0x0>(),
    };

    let id = id::market_id(market_info);
    println!("Market ID: {}", id);
    assert(true, id);
}
