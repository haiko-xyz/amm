// Core lib imports.
use starknet::ContractAddress;
use starknet::contract_address::ContractAddressZeroable;

// Local imports.
use amm::types::core::PositionInfo;

// Number of limits, defined either as:
// * `Fixed` - fixed number of limits
// * `Var` - variable number of limits computed over:
//    * `base` (u32) - base number of limits
//    * `default_value` (u128) - the default volatility for the market
//    * `multiplier` (u32) - sensitivity of number of limits to volatility (denominator of 10000)
//    * `is_min_base` (bool) - whether number of limits is floored at `base` as minimum
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
enum Limits {
    Fixed: u32,
    Vol: (u32, u128, u32, bool),
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
struct StrategyParams {
    // default spread between reference price and bid/ask price (TODO: replace with volatility)
    min_spread: Limits,
    // range parameter (width, in limits, of bid and ask liquidity positions)
    range: Limits,
    // inventory delta, or the max additional single-sided spread applied on an imbalanced portfolio
    max_delta: u32,
    // lookback period for calculating realised volatility (in seconds)
    vol_period: u64,
    // whether strategy allows deposits
    allow_deposits: bool,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
struct OracleParams {
    // Pragma base currency id
    base_currency_id: felt252,
    // Pragma quote currency id
    quote_currency_id: felt252,
    // Pragma pair id
    pair_id: felt252,
    // Oracle price guard - maximum difference in limits between oracle price and market price 
    // before strategy is automatically paused
    max_oracle_dev: u32,
}

#[derive(Drop, Copy, Serde, Default, starknet::Store)]
struct StrategyState {
    // Whether strategy is initialised
    is_initialised: bool,
    // Strategy owner for market
    owner: ContractAddress,
    // Whether strategy is paused
    is_paused: bool,
    // Base reserves
    base_reserves: u256,
    // Quote reserves
    quote_reserves: u256,
    // Placed bid position, or 0 if none placed
    bid: PositionInfo,
    // Placed ask position, or 0 if none placed
    ask: PositionInfo,
}

impl DefaultContractAddress of Default<ContractAddress> {
    fn default() -> ContractAddress {
        ContractAddressZeroable::zero()
    }
}
