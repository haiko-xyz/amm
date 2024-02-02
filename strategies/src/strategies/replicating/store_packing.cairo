// Core lib imports.
use starknet::StorePacking;
use integer::{u128_safe_divmod, u128_as_non_zero};
use traits::{Into, TryInto};
use option::OptionTrait;

// Local imports.
use amm::libraries::constants::MAX_FEE_FACTOR;
use strategies::strategies::replicating::types::{
    StrategyParams, OracleParams, StrategyState, PackedStrategyParams, PackedOracleParams,
    PackedStrategyState
};

////////////////////////////////
// CONSTANTS
////////////////////////////////

const TWO_POW_4: felt252 = 0x10;
const TWO_POW_32: felt252 = 0x100000000;
const TWO_POW_64: felt252 = 0x10000000000000000;
const TWO_POW_96: felt252 = 0x100000000000000000000000;
const TWO_POW_97: felt252 = 0x200000000000000000000000;
const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;
const TWO_POW_129: felt252 = 0x200000000000000000000000000000000;

const MASK_32: u256 = 0xffffffff;
const MASK_64: u256 = 0xffffffffffffffff;

////////////////////////////////
// IMPLS
////////////////////////////////

impl StrategyParamsStorePacking of StorePacking<StrategyParams, PackedStrategyParams> {
    fn pack(value: StrategyParams) -> PackedStrategyParams {
        let mut slab0: u256 = value.min_spread.into();
        slab0 += value.range.into() * TWO_POW_32.into();
        slab0 += value.max_delta.into() * TWO_POW_64.into();
        slab0 += bool_to_u256(value.allow_deposits) * TWO_POW_96.into();
        slab0 += bool_to_u256(value.use_whitelist) * TWO_POW_97.into();

        PackedStrategyParams { slab0: slab0.try_into().unwrap(), }
    }

    fn unpack(value: PackedStrategyParams) -> StrategyParams {
        let slab0: u256 = value.slab0.into();
        let min_spread: u32 = (slab0 & MASK_32).try_into().unwrap();
        let range: u32 = ((slab0 / TWO_POW_32.into()) & MASK_32).try_into().unwrap();
        let max_delta: u32 = ((slab0 / TWO_POW_64.into()) & MASK_32).try_into().unwrap();
        let allow_deposits: bool = u256_to_bool((slab0 / TWO_POW_96.into()) & 1);
        let use_whitelist: bool = u256_to_bool((slab0 / TWO_POW_97.into()) & 1);

        StrategyParams { min_spread, range, max_delta, allow_deposits, use_whitelist, }
    }
}

impl OracleParamsStorePacking of StorePacking<OracleParams, PackedOracleParams> {
    fn pack(value: OracleParams) -> PackedOracleParams {
        let slab0: u256 = value.min_sources.into() + value.max_age.into() * TWO_POW_32.into();

        PackedOracleParams {
            base_currency_id: value.base_currency_id,
            quote_currency_id: value.quote_currency_id,
            slab0: slab0.try_into().unwrap(),
        }
    }

    fn unpack(value: PackedOracleParams) -> OracleParams {
        let min_sources = value.slab0.into() & MASK_32;
        let max_age = (value.slab0.into() / TWO_POW_32.into()) & MASK_64;

        OracleParams {
            base_currency_id: value.base_currency_id,
            quote_currency_id: value.quote_currency_id,
            min_sources: min_sources.try_into().unwrap(),
            max_age: max_age.try_into().unwrap(),
        }
    }
}

impl StrategyStateStorePacking of StorePacking<StrategyState, PackedStrategyState> {
    fn pack(value: StrategyState) -> PackedStrategyState {
        let slab0: felt252 = value.base_reserves.try_into().unwrap();
        let slab1: felt252 = value.quote_reserves.try_into().unwrap();
        let mut slab2: u256 = value.bid_lower.into();
        slab2 += value.bid_upper.into() * TWO_POW_32.into();
        slab2 += value.ask_lower.into() * TWO_POW_64.into();
        slab2 += value.ask_upper.into() * TWO_POW_96.into();
        slab2 += bool_to_u256(value.is_initialised) * TWO_POW_128.into();
        slab2 += bool_to_u256(value.is_paused) * TWO_POW_129.into();

        PackedStrategyState { slab0, slab1, slab2: slab2.try_into().unwrap(), }
    }

    fn unpack(value: PackedStrategyState) -> StrategyState {
        let base_reserves: u256 = value.slab0.into();
        let quote_reserves: u256 = value.slab1.into();
        let bid_lower: u32 = (value.slab2.into() & MASK_32).try_into().unwrap();
        let bid_upper: u32 = ((value.slab2.into() / TWO_POW_32.into()) & MASK_32)
            .try_into()
            .unwrap();
        let ask_lower: u32 = ((value.slab2.into() / TWO_POW_64.into()) & MASK_32)
            .try_into()
            .unwrap();
        let ask_upper: u32 = ((value.slab2.into() / TWO_POW_96.into()) & MASK_32)
            .try_into()
            .unwrap();
        let is_initialised: bool = u256_to_bool((value.slab2.into() / TWO_POW_128.into()) & 1);
        let is_paused: bool = u256_to_bool((value.slab2.into() / TWO_POW_129.into()) & 1);

        StrategyState {
            base_reserves,
            quote_reserves,
            bid_lower,
            bid_upper,
            ask_lower,
            ask_upper,
            is_initialised,
            is_paused,
        }
    }
}

////////////////////////////////
// INTERNAL HELPERS
////////////////////////////////

fn bool_to_u256(value: bool) -> u256 {
    if value {
        1
    } else {
        0
    }
}

fn u256_to_bool(value: u256) -> bool {
    value == 1
}
