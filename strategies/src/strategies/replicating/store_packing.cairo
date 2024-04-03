// Core lib imports.
use starknet::storage_access::StorePacking;

// Local imports.
use amm::libraries::constants::MAX_FEE_FACTOR;
use amm::types::core::PositionInfo;
use strategies::strategies::replicating::types::{
    StrategyParams, StrategyState, PositionRange, PackedStrategyParams, PackedStrategyState
};

////////////////////////////////
// CONSTANTS
////////////////////////////////

const TWO_POW_4: felt252 = 0x10;
const TWO_POW_32: felt252 = 0x100000000;
const TWO_POW_64: felt252 = 0x10000000000000000;
const TWO_POW_96: felt252 = 0x1000000000000000000000000;
const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;
const TWO_POW_129: felt252 = 0x200000000000000000000000000000000;
const TWO_POW_192: felt252 = 0x1000000000000000000000000000000000000000000000000;
const TWO_POW_193: felt252 = 0x2000000000000000000000000000000000000000000000000;
const TWO_POW_251: felt252 = 0x800000000000000000000000000000000000000000000000000000000000000;

const MASK_1: u256 = 0x1;
const MASK_32: u256 = 0xffffffff;
const MASK_64: u256 = 0xffffffffffffffff;
const MASK_128: u256 = 0xffffffffffffffffffffffffffffffff;

////////////////////////////////
// IMPLS
////////////////////////////////

pub(crate) impl StrategyParamsStorePacking of StorePacking<StrategyParams, PackedStrategyParams> {
    fn pack(value: StrategyParams) -> PackedStrategyParams {
        let mut slab0: u256 = value.min_spread.into();
        slab0 += value.range.into() * TWO_POW_32.into();
        slab0 += value.max_delta.into() * TWO_POW_64.into();
        slab0 += value.min_sources.into() * TWO_POW_96.into();
        slab0 += value.max_age.into() * TWO_POW_128.into();
        slab0 += bool_to_u256(value.allow_deposits) * TWO_POW_192.into();
        slab0 += bool_to_u256(value.use_whitelist) * TWO_POW_193.into();

        PackedStrategyParams {
            base_currency_id: value.base_currency_id,
            quote_currency_id: value.quote_currency_id,
            slab0: slab0.try_into().unwrap(),
        }
    }

    fn unpack(value: PackedStrategyParams) -> StrategyParams {
        let base_currency_id = value.base_currency_id;
        let quote_currency_id = value.quote_currency_id;
        let slab0: u256 = value.slab0.into();
        let min_spread: u32 = (slab0 & MASK_32).try_into().unwrap();
        let range: u32 = ((slab0 / TWO_POW_32.into()) & MASK_32).try_into().unwrap();
        let max_delta: u32 = ((slab0 / TWO_POW_64.into()) & MASK_32).try_into().unwrap();
        let min_sources: u32 = ((slab0 / TWO_POW_96.into()) & MASK_32).try_into().unwrap();
        let max_age: u64 = ((slab0 / TWO_POW_128.into()) & MASK_64).try_into().unwrap();
        let allow_deposits: bool = u256_to_bool((slab0 / TWO_POW_192.into()) & 1);
        let use_whitelist: bool = u256_to_bool((slab0 / TWO_POW_193.into()) & 1);

        StrategyParams {
            min_spread,
            range,
            max_delta,
            allow_deposits,
            use_whitelist,
            base_currency_id,
            quote_currency_id,
            min_sources,
            max_age
        }
    }
}

pub(crate) impl StrategyStateStorePacking of StorePacking<StrategyState, PackedStrategyState> {
    // Always pack strategy state as V2.
    fn pack(value: StrategyState) -> PackedStrategyState {
        let slab0: felt252 = value.base_reserves.try_into().unwrap();
        let slab1: felt252 = value.quote_reserves.try_into().unwrap();
        let mut slab2: u256 = value.bid.lower_limit.into();
        slab2 += value.bid.upper_limit.into() * TWO_POW_32.into();
        slab2 += value.ask.lower_limit.into() * TWO_POW_64.into();
        slab2 += value.ask.upper_limit.into() * TWO_POW_96.into();
        slab2 += bool_to_u256(value.is_initialised) * TWO_POW_128.into();
        slab2 += bool_to_u256(value.is_paused) * TWO_POW_129.into();
        // Add `is_v2` flag.
        slab2 += TWO_POW_251.into();

        PackedStrategyState { slab0, slab1, slab2: slab2.try_into().unwrap(), slab3: 0, }
    }

    // Legacy: v1 packing.
    // fn pack(value: StrategyState) -> PackedStrategyState {
    //     let slab0: felt252 = value.base_reserves.try_into().unwrap();
    //     let slab1: felt252 = value.quote_reserves.try_into().unwrap();
    //     let mut slab2: u256 = value.bid.lower_limit.into();
    //     slab2 += value.bid.upper_limit.into() * TWO_POW_32.into();
    //     slab2 += bool_to_u256(value.is_initialised) * TWO_POW_192.into();
    //     slab2 += bool_to_u256(value.is_paused) * TWO_POW_193.into();

    //     let mut slab3: u256 = value.ask.lower_limit.into();
    //     slab3 += value.ask.upper_limit.into() * TWO_POW_32.into();

    //     PackedStrategyState {
    //         slab0, slab1, slab2: slab2.try_into().unwrap(), slab3: slab3.try_into().unwrap(),
    //     }
    // }

    // TEST: Simulate randomly packed values, either in V1 or V2, and ensure correctly handled by `unpack`.
    // fn pack(value: StrategyState) -> PackedStrategyState {
    //     let is_v2 = (value.bid.lower_limit + value.bid.upper_limit + value.ask.lower_limit + value.ask.upper_limit) % 2 == 0;
    //     println!("[pack] is_v2: {}", is_v2);

    //     if is_v2 {
    //         let slab0: felt252 = value.base_reserves.try_into().unwrap();
    //         let slab1: felt252 = value.quote_reserves.try_into().unwrap();
    //         let mut slab2: u256 = value.bid.lower_limit.into();
    //         slab2 += value.bid.upper_limit.into() * TWO_POW_32.into();
    //         slab2 += value.ask.lower_limit.into() * TWO_POW_64.into();
    //         slab2 += value.ask.upper_limit.into() * TWO_POW_96.into();
    //         slab2 += bool_to_u256(value.is_initialised) * TWO_POW_128.into();
    //         slab2 += bool_to_u256(value.is_paused) * TWO_POW_129.into();
    //         // Add `is_v2` flag.
    //         slab2 += TWO_POW_251.into();

    //         PackedStrategyState {
    //             slab0, slab1, slab2: slab2.try_into().unwrap(), slab3: 0,
    //         }
    //     } else {
    //         let slab0: felt252 = value.base_reserves.try_into().unwrap();
    //         let slab1: felt252 = value.quote_reserves.try_into().unwrap();
    //         let mut slab2: u256 = value.bid.lower_limit.into();
    //         slab2 += value.bid.upper_limit.into() * TWO_POW_32.into();
    //         slab2 += bool_to_u256(value.is_initialised) * TWO_POW_192.into();
    //         slab2 += bool_to_u256(value.is_paused) * TWO_POW_193.into();

    //         let mut slab3: u256 = value.ask.lower_limit.into();
    //         slab3 += value.ask.upper_limit.into() * TWO_POW_32.into();

    //         PackedStrategyState {
    //             slab0, slab1, slab2: slab2.try_into().unwrap(), slab3: slab3.try_into().unwrap(),
    //         }
    //     }
    // }

    // Unpack strategy state as either V1 or V2 depending on whether slab3 is set.
    fn unpack(value: PackedStrategyState) -> StrategyState {
        // Unpack variables that are common between V1 and V2.
        let base_reserves: u256 = value.slab0.into();
        let quote_reserves: u256 = value.slab1.into();
        let bid_lower: u32 = (value.slab2.into() & MASK_32).try_into().unwrap();
        let bid_upper: u32 = ((value.slab2.into() / TWO_POW_32.into()) & MASK_32)
            .try_into()
            .unwrap();
        let mut ask_lower: u32 = 0;
        let mut ask_upper: u32 = 0;
        let mut is_initialised: bool = false;
        let mut is_paused: bool = false;

        // Check if the state is V1 or V2.
        let is_v2 = ((value.slab2.into() / TWO_POW_251.into()) & MASK_1) == 1;
        // Unpack the rest of the variables.
        if is_v2 {
            ask_lower = ((value.slab2.into() / TWO_POW_64.into()) & MASK_32).try_into().unwrap();
            ask_upper = ((value.slab2.into() / TWO_POW_96.into()) & MASK_32).try_into().unwrap();
            is_initialised = u256_to_bool((value.slab2.into() / TWO_POW_128.into()) & 1);
            is_paused = u256_to_bool((value.slab2.into() / TWO_POW_129.into()) & 1);
        } else {
            is_initialised = u256_to_bool((value.slab2.into() / TWO_POW_192.into()) & 1);
            is_paused = u256_to_bool((value.slab2.into() / TWO_POW_193.into()) & 1);
            ask_lower = (value.slab3.into() & MASK_32).try_into().unwrap();
            ask_upper = ((value.slab3.into() / TWO_POW_32.into()) & MASK_32).try_into().unwrap();
        }

        // Compile positions.
        let bid = PositionRange { lower_limit: bid_lower, upper_limit: bid_upper, };
        let ask = PositionRange { lower_limit: ask_lower, upper_limit: ask_upper, };

        StrategyState { base_reserves, quote_reserves, is_initialised, is_paused, bid, ask, }
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
