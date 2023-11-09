use amm::types::core::MarketInfo;
use amm::libraries::id;
use debug::PrintTrait;
use starknet::contract_address_const;

#[test]
#[available_gas(2000000)]
fn position_id() {
    let market_id = 0x5027d547580851650aebe16b71643a1885e0b5b7eb7f16cd2439ae2f729a512;
    let owner = 0x1fdb6ce2bb27420c779b59c4329c13d23f224b6bc30359c392e0e0b3f358e27;
    let lower_limit = 8388600 + 732660;
    let upper_limit = 8388600 + 737660;
    let id = id::position_id(market_id, owner, lower_limit, upper_limit);
    id.print();
    assert(true, id);
}

#[test]
#[available_gas(2000000)]
fn market_id() {
    let base_token = contract_address_const::<
        0x041b47f933fcfdb696521b89a704a3662c5aa446ed8a29b352fb6fa9a748a8a3
    >();
    let quote_token = contract_address_const::<
        0x072b09174080f7d1f158b26f1c6639964f4c8568bd5bc1fc3580b3047e500e99
    >();

    let market_info = MarketInfo {
        base_token,
        quote_token,
        width: 1,
        strategy: contract_address_const::<0x0>(),
        swap_fee_rate: 1,
        fee_controller: contract_address_const::<0x0>(),
        allow_positions: true,
        allow_orders: true
    };

    let id = id::market_id(market_info);
    id.print();
    assert(true, id);
}
