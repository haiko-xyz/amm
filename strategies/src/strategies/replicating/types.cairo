// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address::ContractAddressZeroable;

// Local imports.
use amm::types::core::PositionInfo;

////////////////////////////////
// TYPES
////////////////////////////////

// Strategy parameters.
//
// * `min_spread` - default spread between reference price and bid/ask price
// * `range` - range parameter (width, in limits, of bid and ask liquidity positions)
// * `max_delta` - inventory delta, or the max additional single-sided spread applied on an imbalanced portfolio
// * `allow_deposits` - whether strategy allows deposits
// * `use_whitelist` - whether whitelisting is enabled
#[derive(Drop, Copy, Serde, PartialEq)]
struct StrategyParams {
    min_spread: u32,
    range: u32,
    max_delta: u32,
    allow_deposits: bool,
    use_whitelist: bool,
}

#[derive(Drop, Copy, Serde)]
struct OracleParams {
    // Pragma base currency id
    base_currency_id: felt252,
    // Pragma quote currency id
    quote_currency_id: felt252,
    // Minimum number of data sources aggregated
    min_sources: u32,
    // Maximum age of quoted price
    max_age: u64,
}

#[derive(Drop, Copy, Serde, Default)]
struct StrategyState {
    // Whether strategy is initialised
    is_initialised: bool,
    // Whether strategy is paused
    is_paused: bool,
    // Base reserves
    base_reserves: u256,
    // Quote reserves
    quote_reserves: u256,
    // Placed bid lower limit, or 0 if none placed
    bid_lower: u32,
    // Placed bid upper limit, or 0 if none placed
    bid_upper: u32,
    // Placed ask lower limit, or 0 if none placed
    ask_lower: u32,
    // Placed ask upper limit, or 0 if none placed
    ask_upper: u32,
}

// // Number of limits, defined either as:
// // * `Fixed` - fixed number of limits
// // * `Var` - variable number of limits computed over:
// //    * `base` (u32) - base number of limits
// //    * `default_value` (u128) - the default volatility for the market
// //    * `multiplier` (u32) - sensitivity of number of limits to volatility (denominator of 10000)
// //    * `is_min_base` (bool) - whether number of limits is floored at `base` as minimum
// #[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
// enum Limits {
//     Fixed: u32,
//     Vol: (u32, u128, u32, bool),
// }

////////////////////////////////
// PACKED TYPES
////////////////////////////////

// Packed strategy parameters.
//
// * `slab0` - `min_spread` + `range` + `max_delta` + `allow_deposits` + `use_whitelist`
#[derive(starknet::Store)]
struct PackedStrategyParams {
    slab0: felt252
}

// Packed oracle parameters.
//
// * `base_currency_id` - base currency id
// * `quote_currency_id` - quote currency id
// * `slab0` - `min_sources` + `max_age`
#[derive(starknet::Store)]
struct PackedOracleParams {
    base_currency_id: felt252,
    quote_currency_id: felt252,
    slab0: felt252
}

// Packed strategy state.
//
// * `slab0` - base reserves (coerced to felt252)
// * `slab1` - quote reserves (coerced to felt252)
// * `slab2` - `bid_lower_limit` + `bid_upper_limit` + `ask_lower_limit` + `ask_upper_limit` + `is_initialised` + `is_paused`
#[derive(starknet::Store)]
struct PackedStrategyState {
    slab0: felt252,
    slab1: felt252,
    slab2: felt252,
}
