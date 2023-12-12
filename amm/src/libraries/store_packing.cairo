// Core lib imports.
use starknet::StorePacking;
use integer::{u128_safe_divmod, u128_as_non_zero};
use traits::{Into, TryInto};
use option::OptionTrait;

// Local imports.
use amm::types::core::{
    MarketInfo, MarketState, MarketConfigs, Config, ConfigOption, ValidLimits, LimitInfo, Position,
    OrderBatch, LimitOrder, PackedMarketInfo, PackedMarketState, PackedLimitInfo, PackedPosition,
    PackedOrderBatch, PackedLimitOrder, PackedMarketConfigs
};
use amm::types::i128::I128Trait;

////////////////////////////////
// CONSTANTS
////////////////////////////////

const TWO_POW_4: felt252 = 0x10;
const TWO_POW_5: felt252 = 0x20;
const TWO_POW_6: felt252 = 0x40;
const TWO_POW_16: felt252 = 0x10000;
const TWO_POW_32: felt252 = 0x100000000;
const TWO_POW_38: felt252 = 0x4000000000;
const TWO_POW_48: felt252 = 0x1000000000000;
const TWO_POW_64: felt252 = 0x10000000000000000;
const TWO_POW_96: felt252 = 0x1000000000000000000000000;
const TWO_POW_124: felt252 = 0x10000000000000000000000000000000;
const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;
const TWO_POW_132: felt252 = 0x1000000000000000000000000000000000;
const TWO_POW_136: felt252 = 0x10000000000000000000000000000000000;
const TWO_POW_140: felt252 = 0x100000000000000000000000000000000000;
const TWO_POW_144: felt252 = 0x1000000000000000000000000000000000000;
const TWO_POW_148: felt252 = 0x10000000000000000000000000000000000000;
const TWO_POW_152: felt252 = 0x100000000000000000000000000000000000000;
const TWO_POW_153: felt252 = 0x200000000000000000000000000000000000000;
const TWO_POW_154: felt252 = 0x400000000000000000000000000000000000000;
const TWO_POW_155: felt252 = 0x800000000000000000000000000000000000000;
const TWO_POW_156: felt252 = 0x1000000000000000000000000000000000000000;
const TWO_POW_157: felt252 = 0x2000000000000000000000000000000000000000;
const TWO_POW_158: felt252 = 0x4000000000000000000000000000000000000000;

const MASK_1: u256 = 0x1;
const MASK_2: u256 = 0x3;
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
        let slab0 = value.width.into() + value.swap_fee_rate.into() * TWO_POW_32;

        PackedMarketInfo {
            base_token: value.base_token.into(),
            quote_token: value.quote_token.into(),
            strategy: value.strategy.into(),
            fee_controller: value.fee_controller.into(),
            controller: value.controller.into(),
            slab0,
        }
    }

    fn unpack(value: PackedMarketInfo) -> MarketInfo {
        let slab0: u256 = value.slab0.into();
        let width: u32 = (slab0 & MASK_32).try_into().unwrap();
        let swap_fee_rate: u16 = ((slab0 / TWO_POW_32.into()) & MASK_16).try_into().unwrap();

        MarketInfo {
            base_token: value.base_token.try_into().unwrap(),
            quote_token: value.quote_token.try_into().unwrap(),
            width,
            strategy: value.strategy.try_into().unwrap(),
            swap_fee_rate,
            fee_controller: value.fee_controller.try_into().unwrap(),
            controller: value.controller.try_into().unwrap(),
        }
    }
}

impl MarketStateStorePacking of StorePacking<MarketState, PackedMarketState> {
    fn pack(value: MarketState) -> PackedMarketState {
        let curr_sqrt_price: felt252 = value.curr_sqrt_price.try_into().expect('CurrSqrtPriceOF');
        let base_fee_factor: felt252 = value.base_fee_factor.try_into().expect('BaseFeeFactorOF');
        let quote_fee_factor: felt252 = value
            .quote_fee_factor
            .try_into()
            .expect('QuoteFeeFactorOF');

        let mut slab0: u256 = value.protocol_share.into();
        slab0 += value.curr_limit.into() * TWO_POW_16.into();
        slab0 += value.liquidity.into() * TWO_POW_48.into();

        PackedMarketState {
            curr_sqrt_price, base_fee_factor, quote_fee_factor, slab0: slab0.try_into().unwrap(),
        }
    }

    fn unpack(value: PackedMarketState) -> MarketState {
        let curr_sqrt_price: u256 = value.curr_sqrt_price.into();
        let base_fee_factor: u256 = value.base_fee_factor.into();
        let quote_fee_factor: u256 = value.quote_fee_factor.into();
        let protocol_share: u16 = (value.slab0.into() & MASK_16.into()).try_into().unwrap();
        let curr_limit: u32 = ((value.slab0.into() / TWO_POW_16.into()) & MASK_32.into())
            .try_into()
            .unwrap();
        let liquidity: u128 = ((value.slab0.into() / TWO_POW_48.into()) & MASK_128.into())
            .try_into()
            .unwrap();

        MarketState {
            liquidity,
            curr_sqrt_price,
            base_fee_factor,
            quote_fee_factor,
            protocol_share,
            curr_limit,
        }
    }
}

impl MarketConfigsStorePacking of StorePacking<MarketConfigs, PackedMarketConfigs> {
    fn pack(value: MarketConfigs) -> PackedMarketConfigs {
        let mut slab: u256 = value.limits.value.min_lower.into();
        slab += value.limits.value.max_lower.into() * TWO_POW_32.into();
        slab += value.limits.value.min_upper.into() * TWO_POW_64.into();
        slab += value.limits.value.max_upper.into() * TWO_POW_96.into();
        slab += status_to_u256(value.add_liquidity.value) * TWO_POW_128.into();
        slab += status_to_u256(value.remove_liquidity.value) * TWO_POW_132.into();
        slab += status_to_u256(value.create_bid.value) * TWO_POW_136.into();
        slab += status_to_u256(value.create_ask.value) * TWO_POW_140.into();
        slab += status_to_u256(value.collect_order.value) * TWO_POW_144.into();
        slab += status_to_u256(value.swap.value) * TWO_POW_148.into();
        slab += bool_to_u256(value.limits.fixed) * TWO_POW_152.into();
        slab += bool_to_u256(value.add_liquidity.fixed) * TWO_POW_153.into();
        slab += bool_to_u256(value.remove_liquidity.fixed) * TWO_POW_154.into();
        slab += bool_to_u256(value.create_bid.fixed) * TWO_POW_155.into();
        slab += bool_to_u256(value.create_ask.fixed) * TWO_POW_156.into();
        slab += bool_to_u256(value.collect_order.fixed) * TWO_POW_157.into();
        slab += bool_to_u256(value.swap.fixed) * TWO_POW_158.into();

        PackedMarketConfigs { slab: slab.try_into().unwrap() }
    }

    fn unpack(value: PackedMarketConfigs) -> MarketConfigs {
        let slab: u256 = value.slab.into();
        let min_lower: u32 = (slab & MASK_32).try_into().unwrap();
        let max_lower: u32 = ((slab / TWO_POW_32.into()) & MASK_32).try_into().unwrap();
        let min_upper: u32 = ((slab / TWO_POW_64.into()) & MASK_32).try_into().unwrap();
        let max_upper: u32 = ((slab / TWO_POW_96.into()) & MASK_32).try_into().unwrap();
        let add_liquidity: ConfigOption = u256_to_status((slab / TWO_POW_128.into()) & MASK_2);
        let remove_liquidity: ConfigOption = u256_to_status((slab / TWO_POW_132.into()) & MASK_2);
        let create_bid: ConfigOption = u256_to_status((slab / TWO_POW_136.into()) & MASK_2);
        let create_ask: ConfigOption = u256_to_status((slab / TWO_POW_140.into()) & MASK_2);
        let collect_order: ConfigOption = u256_to_status((slab / TWO_POW_144.into()) & MASK_2);
        let swap: ConfigOption = u256_to_status((slab / TWO_POW_148.into()) & MASK_2);
        let limits_fixed: bool = u256_to_bool((slab / TWO_POW_152.into()) & MASK_1);
        let add_liquidity_fixed: bool = u256_to_bool((slab / TWO_POW_153.into()) & MASK_1);
        let remove_liquidity_fixed: bool = u256_to_bool((slab / TWO_POW_154.into()) & MASK_1);
        let create_bid_fixed: bool = u256_to_bool((slab / TWO_POW_155.into()) & MASK_1);
        let create_ask_fixed: bool = u256_to_bool((slab / TWO_POW_156.into()) & MASK_1);
        let collect_order_fixed: bool = u256_to_bool((slab / TWO_POW_157.into()) & MASK_1);
        let swap_fixed: bool = u256_to_bool((slab / TWO_POW_158.into()) & MASK_1);

        let limits = ValidLimits { min_lower, max_lower, min_upper, max_upper };

        MarketConfigs {
            limits: Config { value: limits, fixed: limits_fixed },
            add_liquidity: Config { value: add_liquidity, fixed: add_liquidity_fixed },
            remove_liquidity: Config { value: remove_liquidity, fixed: remove_liquidity_fixed },
            create_bid: Config { value: create_bid, fixed: create_bid_fixed },
            create_ask: Config { value: create_ask, fixed: create_ask_fixed },
            collect_order: Config { value: collect_order, fixed: collect_order_fixed },
            swap: Config { value: swap, fixed: swap_fixed },
        }
    }
}

impl LimitInfoStorePacking of StorePacking<LimitInfo, PackedLimitInfo> {
    fn pack(value: LimitInfo) -> PackedLimitInfo {
        let base_fee_factor: felt252 = value.base_fee_factor.try_into().unwrap();
        let quote_fee_factor: felt252 = value.quote_fee_factor.try_into().unwrap();
        let mut slab0: u256 = value.liquidity.into();
        slab0 += (value.liquidity_delta.val.into() % TWO_POW_124.into()) * TWO_POW_128.into();

        let mut slab1: u256 = value.liquidity_delta.val.into() / TWO_POW_124.into();
        slab1 += bool_to_u256(value.liquidity_delta.sign) * TWO_POW_4.into();
        slab1 += value.nonce.into() * TWO_POW_5.into();

        PackedLimitInfo {
            base_fee_factor,
            quote_fee_factor,
            slab0: slab0.try_into().unwrap(),
            slab1: slab1.try_into().unwrap(),
        }
    }

    fn unpack(value: PackedLimitInfo) -> LimitInfo {
        let base_fee_factor: u256 = value.base_fee_factor.into();
        let quote_fee_factor: u256 = value.quote_fee_factor.into();
        let liquidity: u128 = (value.slab0.into() & MASK_128).try_into().unwrap();
        let abs_liquidity_delta: u256 = (value.slab0.into() / TWO_POW_128.into())
            + (value.slab1.into() & MASK_4) * TWO_POW_124.into();
        let sign: bool = ((value.slab1.into() / TWO_POW_4.into()) & MASK_1) == 1;
        let nonce: u128 = ((value.slab1.into() / TWO_POW_5.into()) & MASK_128).try_into().unwrap();

        LimitInfo {
            liquidity,
            liquidity_delta: I128Trait::new(abs_liquidity_delta.try_into().unwrap(), sign),
            base_fee_factor,
            quote_fee_factor,
            nonce,
        }
    }
}

impl OrderBatchStorePacking of StorePacking<OrderBatch, PackedOrderBatch> {
    fn pack(value: OrderBatch) -> PackedOrderBatch {
        let mut slab0: u256 = value.base_amount.into();
        slab0 += (value.quote_amount.into() % TWO_POW_124.into()) * TWO_POW_128.into();

        let mut slab1: u256 = value.quote_amount.into() / TWO_POW_124.into();
        slab1 += bool_to_u256(value.filled) * TWO_POW_4.into();
        slab1 += bool_to_u256(value.is_bid) * TWO_POW_5.into();
        slab1 += value.limit.into() * TWO_POW_6.into();
        slab1 += value.liquidity.into() * TWO_POW_38.into();

        PackedOrderBatch { slab0: slab0.try_into().unwrap(), slab1: slab1.try_into().unwrap(), }
    }

    fn unpack(value: PackedOrderBatch) -> OrderBatch {
        let base_amount: u128 = (value.slab0.into() & MASK_128).try_into().unwrap();
        let quote_amount: u128 = (value.slab0.into() / TWO_POW_128.into()
            + (value.slab1.into() & MASK_4.into()) * TWO_POW_124.into())
            .try_into()
            .unwrap();
        let filled: bool = ((value.slab1.into() / TWO_POW_4.into()) & MASK_1) == 1;
        let is_bid: bool = ((value.slab1.into() / TWO_POW_5.into()) & MASK_1) == 1;
        let limit: u32 = ((value.slab1.into() / TWO_POW_6.into()) & MASK_32).try_into().unwrap();
        let liquidity: u128 = ((value.slab1.into() / TWO_POW_38.into()) & MASK_128)
            .try_into()
            .unwrap();

        OrderBatch { liquidity, filled, limit, is_bid, base_amount, quote_amount, }
    }
}

impl PositionStorePacking of StorePacking<Position, PackedPosition> {
    fn pack(value: Position) -> PackedPosition {
        let base_fee_factor_last: felt252 = value
            .base_fee_factor_last
            .try_into()
            .expect('BaseFeeFactorLastOF');
        let quote_fee_factor_last: felt252 = value
            .quote_fee_factor_last
            .try_into()
            .expect('QuoteFeeFactorLastOF');

        let mut slab0: u256 = value.lower_limit.into();
        slab0 += value.upper_limit.into() * TWO_POW_32.into();
        slab0 += value.liquidity.into() * TWO_POW_64.into();

        PackedPosition {
            market_id: value.market_id,
            base_fee_factor_last,
            quote_fee_factor_last,
            slab0: slab0.try_into().unwrap()
        }
    }

    fn unpack(value: PackedPosition) -> Position {
        let market_id = value.market_id;
        let base_fee_factor_last: u256 = value.base_fee_factor_last.into();
        let quote_fee_factor_last: u256 = value.quote_fee_factor_last.into();
        let lower_limit: u32 = (value.slab0.into() & MASK_32).try_into().unwrap();
        let upper_limit: u32 = ((value.slab0.into() / TWO_POW_32.into()) & MASK_32)
            .try_into()
            .unwrap();
        let liquidity: u128 = ((value.slab0.into() / TWO_POW_64.into()) & MASK_128)
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
        PackedLimitOrder { batch_id: value.batch_id, liquidity: value.liquidity.into(), }
    }

    fn unpack(value: PackedLimitOrder) -> LimitOrder {
        LimitOrder { batch_id: value.batch_id, liquidity: value.liquidity.try_into().unwrap(), }
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

fn status_to_u256(value: ConfigOption) -> u256 {
    match value {
        ConfigOption::Enabled => 0,
        ConfigOption::Disabled => 1,
        ConfigOption::OnlyOwner => 2,
        ConfigOption::OnlyStrategy => 3,
    }
}

fn u256_to_status(value: u256) -> ConfigOption {
    if value == 0 {
        ConfigOption::Enabled
    } else if value == 1 {
        ConfigOption::Disabled
    } else if value == 2 {
        ConfigOption::OnlyOwner
    } else {
        ConfigOption::OnlyStrategy
    }
}
