use amm::libraries::id;
use debug::PrintTrait;

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
