// Core lib imports.
use starknet::StorePacking;
use integer::{u128_safe_divmod, u128_as_non_zero};
use traits::{Into, TryInto};
use option::OptionTrait;

// Local imports.
use amm::types::core::{
    MarketInfo, MarketState, LimitInfo, Position, OrderBatch, LimitOrder, PackedMarketInfo,
    PackedMarketState, PackedLimitInfo, PackedPosition, PackedOrderBatch, PackedLimitOrder
};
use amm::types::i256::I256Trait;

////////////////////////////////
// CONSTANTS
////////////////////////////////

const TWO_POW_4: felt252 = 0x10;
const TWO_POW_8: felt252 = 0x100;
const TWO_POW_12: felt252 = 0x1000;
const TWO_POW_13: felt252 = 0x2000;
const TWO_POW_14: felt252 = 0x4000;
const TWO_POW_16: felt252 = 0x10000;
const TWO_POW_17: felt252 = 0x20000;
const TWO_POW_32: felt252 = 0x100000000;
const TWO_POW_44: felt252 = 0x100000000000;
const TWO_POW_48: felt252 = 0x1000000000000;
const TWO_POW_49: felt252 = 0x2000000000000;
const TWO_POW_64: felt252 = 0x10000000000000000;

const MASK_1: u256 = 0x1;
const MASK_4: u256 = 0xf;
const MASK_8: u256 = 0xff;
const MASK_16: u256 = 0xffff;
const MASK_32: u256 = 0xffffffff;
const MASK_64: u256 = 0xffffffffffffffff;
const MASK_128: u256 = 0xffffffffffffffffffffffffffffffff;

////////////////////////////////
// IMPLS
////////////////////////////////

impl MarketInfoStorePacking of StorePacking<MarketInfo, PackedMarketInfo> {
    fn pack(value: MarketInfo) -> PackedMarketInfo {
        let slab0 = value.width.into()
            + value.swap_fee_rate.into() * TWO_POW_32
            + value.allow_positions.into() * TWO_POW_48
            + value.allow_orders.into() * TWO_POW_49;

        PackedMarketInfo {
            base_token: value.base_token.into(),
            quote_token: value.quote_token.into(),
            strategy: value.strategy.into(),
            fee_controller: value.fee_controller.into(),
            slab0,
        }
    }

    fn unpack(value: PackedMarketInfo) -> MarketInfo {
        let slab0: u256 = value.slab0.into();
        let width: u32 = (slab0 & MASK_32).try_into().unwrap();
        let swap_fee_rate: u16 = ((slab0 / MASK_32.into()) & MASK_16).try_into().unwrap();
        let allow_positions: bool = ((slab0 / TWO_POW_48.into()) & MASK_1) == 1;
        let allow_orders: bool = ((slab0 / TWO_POW_49.into()) & MASK_1) == 1;

        MarketInfo {
            base_token: value.base_token.try_into().unwrap(),
            quote_token: value.quote_token.try_into().unwrap(),
            width,
            strategy: value.strategy.try_into().unwrap(),
            swap_fee_rate,
            fee_controller: value.fee_controller.try_into().unwrap(),
            allow_positions,
            allow_orders,
        }
    }
}

impl MarketStateStorePacking of StorePacking<MarketState, PackedMarketState> {
    fn pack(value: MarketState) -> PackedMarketState {
        let slab0: felt252 = (value.liquidity / TWO_POW_4.into()).try_into().unwrap();
        let slab1: felt252 = (value.curr_sqrt_price / TWO_POW_4.into()).try_into().unwrap();
        let slab2: felt252 = (value.base_fee_factor / TWO_POW_4.into()).try_into().unwrap();
        let slab3: felt252 = (value.quote_fee_factor / TWO_POW_4.into()).try_into().unwrap();

        let mut slab4: u256 = (value.liquidity % TWO_POW_4.into());
        slab4 += (value.curr_sqrt_price % TWO_POW_4.into()) * TWO_POW_4.into();
        slab4 += (value.base_fee_factor % TWO_POW_4.into()) * TWO_POW_8.into();
        slab4 += (value.quote_fee_factor % TWO_POW_4.into()) * TWO_POW_12.into();
        slab4 += value.protocol_share.into() * TWO_POW_16.into();
        slab4 += value.curr_limit.into() * TWO_POW_32.into();
        slab4 += bool_to_u256(value.is_concentrated) * TWO_POW_64.into();

        PackedMarketState { slab0, slab1, slab2, slab3, slab4: slab4.try_into().unwrap(), }
    }

    fn unpack(value: PackedMarketState) -> MarketState {
        let liquidity: u256 = value.slab0.into() * TWO_POW_4.into()
            + (value.slab4.into() & MASK_4.into());
        let curr_sqrt_price: u256 = value.slab1.into() * TWO_POW_4.into()
            + ((value.slab4.into() / TWO_POW_4.into()) & MASK_4.into());
        let base_fee_factor: u256 = value.slab2.into() * TWO_POW_4.into()
            + ((value.slab4.into() / TWO_POW_8.into()) & MASK_4.into());
        let quote_fee_factor: u256 = value.slab3.into() * TWO_POW_4.into()
            + ((value.slab4.into() / TWO_POW_12.into()) & MASK_4.into());
        let protocol_share: u16 = ((value.slab4.into() / TWO_POW_16.into()) & MASK_16.into())
            .try_into()
            .unwrap();
        let curr_limit: u32 = ((value.slab4.into() / TWO_POW_32.into()) & MASK_32.into())
            .try_into()
            .unwrap();
        let is_concentrated: bool = ((value.slab4.into() / TWO_POW_64.into()) & MASK_1) == 1;

        MarketState {
            liquidity,
            curr_sqrt_price,
            base_fee_factor,
            quote_fee_factor,
            is_concentrated,
            protocol_share,
            curr_limit,
        }
    }
}

impl LimitInfoStorePacking of StorePacking<LimitInfo, PackedLimitInfo> {
    fn pack(value: LimitInfo) -> PackedLimitInfo {
        let slab0: felt252 = (value.liquidity / TWO_POW_4.into()).try_into().unwrap();
        let slab1: felt252 = (value.liquidity_delta.val / TWO_POW_4.into()).try_into().unwrap();
        let slab2: felt252 = (value.base_fee_factor / TWO_POW_4.into()).try_into().unwrap();
        let slab3: felt252 = (value.quote_fee_factor / TWO_POW_4.into()).try_into().unwrap();

        let mut slab4: u256 = (value.liquidity % TWO_POW_4.into());
        slab4 += (value.liquidity_delta.val % TWO_POW_4.into()) * TWO_POW_4.into();
        slab4 += (value.base_fee_factor % TWO_POW_4.into()) * TWO_POW_8.into();
        slab4 += (value.quote_fee_factor % TWO_POW_4.into()) * TWO_POW_12.into();
        slab4 += bool_to_u256(value.liquidity_delta.sign) * TWO_POW_16.into();
        slab4 += value.nonce.into() * TWO_POW_17.into();

        PackedLimitInfo { slab0, slab1, slab2, slab3, slab4: slab4.try_into().unwrap(), }
    }

    fn unpack(value: PackedLimitInfo) -> LimitInfo {
        let liquidity: u256 = value.slab0.into() * TWO_POW_4.into()
            + (value.slab4.into() & MASK_4.into());
        let abs_liquidity_delta: u256 = value.slab1.into() * TWO_POW_4.into()
            + ((value.slab4.into() / TWO_POW_4.into()) & MASK_4.into());
        let base_fee_factor: u256 = value.slab2.into() * TWO_POW_4.into()
            + ((value.slab4.into() / TWO_POW_8.into()) & MASK_4.into());
        let quote_fee_factor: u256 = value.slab3.into() * TWO_POW_4.into()
            + ((value.slab4.into() / TWO_POW_12.into()) & MASK_4.into());
        let sign: bool = ((value.slab4.into() / TWO_POW_16.into()) & MASK_1) == 1;
        let nonce: u128 = ((value.slab4.into() / TWO_POW_17.into()) & MASK_128).try_into().unwrap();

        LimitInfo {
            liquidity,
            liquidity_delta: I256Trait::new(abs_liquidity_delta, sign),
            base_fee_factor,
            quote_fee_factor,
            nonce,
        }
    }
}

impl OrderBatchStorePacking of StorePacking<OrderBatch, PackedOrderBatch> {
    fn pack(value: OrderBatch) -> PackedOrderBatch {
        let slab0: felt252 = (value.liquidity / TWO_POW_4.into()).try_into().unwrap();
        let slab1: felt252 = (value.base_amount / TWO_POW_4.into()).try_into().unwrap();
        let slab2: felt252 = (value.quote_amount / TWO_POW_4.into()).try_into().unwrap();

        let mut slab3: u256 = (value.liquidity % TWO_POW_4.into());
        slab3 += (value.base_amount % TWO_POW_4.into()) * TWO_POW_4.into();
        slab3 += (value.quote_amount % TWO_POW_4.into()) * TWO_POW_8.into();
        slab3 += bool_to_u256(value.filled) * TWO_POW_12.into();
        slab3 += bool_to_u256(value.is_bid) * TWO_POW_13.into();
        slab3 += value.limit.into() * TWO_POW_14.into();

        PackedOrderBatch { slab0, slab1, slab2, slab3: slab3.try_into().unwrap(), }
    }

    fn unpack(value: PackedOrderBatch) -> OrderBatch {
        let liquidity: u256 = value.slab0.into() * TWO_POW_4.into()
            + (value.slab3.into() & MASK_4.into());
        let base_amount: u256 = value.slab1.into() * TWO_POW_4.into()
            + ((value.slab3.into() / TWO_POW_4.into()) & MASK_4.into());
        let quote_amount: u256 = value.slab2.into() * TWO_POW_4.into()
            + ((value.slab3.into() / TWO_POW_8.into()) & MASK_4.into());
        let filled: bool = ((value.slab3.into() / TWO_POW_12.into()) & MASK_1) == 1;
        let is_bid: bool = ((value.slab3.into() / TWO_POW_13.into()) & MASK_1) == 1;
        let limit: u32 = ((value.slab3.into() / TWO_POW_14.into()) & MASK_32).try_into().unwrap();

        OrderBatch { liquidity, filled, limit, is_bid, base_amount, quote_amount, }
    }
}

impl PositionStorePacking of StorePacking<Position, PackedPosition> {
    fn pack(value: Position) -> PackedPosition {
        let slab0: felt252 = value.market_id;
        let slab1: felt252 = (value.liquidity / TWO_POW_4.into()).try_into().unwrap();
        let slab2: felt252 = (value.base_fee_factor_last / TWO_POW_4.into()).try_into().unwrap();
        let slab3: felt252 = (value.quote_fee_factor_last / TWO_POW_4.into()).try_into().unwrap();

        let mut slab4: u256 = (value.liquidity % TWO_POW_4.into());
        slab4 += (value.base_fee_factor_last % TWO_POW_4.into()) * TWO_POW_4.into();
        slab4 += (value.quote_fee_factor_last % TWO_POW_4.into()) * TWO_POW_8.into();
        slab4 += (value.lower_limit.into()) * TWO_POW_12.into();
        slab4 += (value.upper_limit.into()) * TWO_POW_44.into();

        PackedPosition { slab0, slab1, slab2, slab3, slab4: slab4.try_into().unwrap() }
    }

    fn unpack(value: PackedPosition) -> Position {
        let market_id = value.slab0;
        let liquidity: u256 = value.slab1.into() * TWO_POW_4.into()
            + (value.slab4.into() & MASK_4.into());
        let base_fee_factor_last: u256 = value.slab2.into() * TWO_POW_4.into()
            + ((value.slab4.into() / TWO_POW_4.into()) & MASK_4.into());
        let quote_fee_factor_last: u256 = value.slab3.into() * TWO_POW_4.into()
            + ((value.slab4.into() / TWO_POW_8.into()) & MASK_4.into());
        let lower_limit: u32 = ((value.slab4.into() / TWO_POW_12.into()) & MASK_32)
            .try_into()
            .unwrap();
        let upper_limit: u32 = ((value.slab4.into() / TWO_POW_44.into()) & MASK_128)
            .try_into()
            .unwrap();

        Position {
            market_id,
            lower_limit,
            upper_limit,
            liquidity,
            base_fee_factor_last,
            quote_fee_factor_last
        }
    }
}

impl LimitOrderStorePacking of StorePacking<LimitOrder, PackedLimitOrder> {
    fn pack(value: LimitOrder) -> PackedLimitOrder {
        PackedLimitOrder {
            batch_id: value.batch_id, liquidity: value.liquidity.try_into().unwrap(),
        }
    }

    fn unpack(value: PackedLimitOrder) -> LimitOrder {
        LimitOrder { batch_id: value.batch_id, liquidity: value.liquidity.into(), }
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
