////////////////////////////////
// IMPORTS
////////////////////////////////

// Core lib imports.
use starknet::ContractAddress;
use starknet::storage_access::StorePacking;

// Local imports.
use amm::libraries::constants::{OFFSET, MAX_LIMIT, MAX_LIMIT_SHIFTED, MAX_WIDTH};
use amm::types::i128::i128;
use amm::types::i256::i256;

////////////////////////////////
// TYPES
////////////////////////////////

// Immutable information about a market. 
// 
// * `base_token` - address of base token
// * `quote_token` - address of quote token
// * `width` - width of limits denominated in 1/10 bp
// * `strategy` - liquidity strategy contract
// * `swap_fee_rate` - swap fee denominated in bps (overridden by fee controller)
// * `fee_controller` - fee controller contract, if unset then swap fee is 0
// * `controller` - market controller, or 0 if market is not controlled
#[derive(Copy, Drop, Serde)]
pub struct MarketInfo {
    pub base_token: ContractAddress,
    pub quote_token: ContractAddress,
    pub width: u32,
    pub strategy: ContractAddress,
    pub swap_fee_rate: u16,
    pub fee_controller: ContractAddress,
    pub controller: ContractAddress,
}

// Granular market settings for creating custom market types.
//
// Notes: 
//  1. Each market setting controls an aspect of a market (e.g. liquidity positions, limit orders),
//     or the entire market (e.g. pausing, deprecation), and can be either fixed or upgradeable. 
//     If upgradeable, the market owner can update a setting at any time. If fixed, the setting is 
//     immutable. 
//  2. A market owner can permanently fix an upgradeable market setting at any time, but not vice versa. 
//  3. By default, all features are enabled and upgradeable.
//  4. The market owner must be set during `create_market` to enable upgradeable settings.
//
// * `limits` - valid ranges of lower and upper limits
// * `add_liquidity` - whether adding liquidity is enabled
// * `remove_liquidity` - whether removing liquidity is enabled
// * `create_bid` - whether creating bid limit orders is enabled
// * `create_ask` - whether creating ask limit orders is enabled
// * `collect_order` - whether collecting orders is enabled
// * `swap` - whether swapping is enabled
#[derive(Copy, Drop, Serde, PartialEq)]
pub struct MarketConfigs {
    pub limits: Config<ValidLimits>,
    pub add_liquidity: Config<ConfigOption>,
    pub remove_liquidity: Config<ConfigOption>,
    pub create_bid: Config<ConfigOption>,
    pub create_ask: Config<ConfigOption>,
    pub collect_order: Config<ConfigOption>,
    pub swap: Config<ConfigOption>,
}

// Default market configs.
//  1. If an owner is set, all market configs are upgradeable by default.
//  2. If an owner is not set, all features are enabled by default.
impl DefaultMarketConfigs of Default<MarketConfigs> {
    fn default() -> MarketConfigs {
        MarketConfigs {
            limits: Config { value: Default::default(), fixed: false },
            add_liquidity: Config { value: ConfigOption::Enabled, fixed: false },
            remove_liquidity: Config { value: ConfigOption::Enabled, fixed: false },
            create_bid: Config { value: ConfigOption::Enabled, fixed: false },
            create_ask: Config { value: ConfigOption::Enabled, fixed: false },
            collect_order: Config { value: ConfigOption::Enabled, fixed: false },
            swap: Config { value: ConfigOption::Enabled, fixed: false },
        }
    }
}

// An individual market config.
//
// * `value` - current value
// * `fixed` - whether config is fixed at its current value
#[derive(Copy, Drop, Serde, PartialEq)]
pub struct Config<T> {
    pub value: T,
    pub fixed: bool,
}

// Struct representing valid limits.
//
// * `min_lower` - minimum lower limit
// * `max_lower` - maximum lower limit
// * `min_upper` - minimum upper limit
// * `max_upper` - maximum upper limit
// * `min_width` - minimum width
// * `max_width` - maximum width
#[derive(Copy, Drop, Serde, PartialEq)]
pub struct ValidLimits {
    pub min_lower: u32,
    pub max_lower: u32,
    pub min_upper: u32,
    pub max_upper: u32,
    pub min_width: u32,
    pub max_width: u32,
}

// Default valid limits.
// Allows placing positions across entire market range.
impl DefaultValidLimits of Default<ValidLimits> {
    fn default() -> ValidLimits {
        ValidLimits {
            min_lower: 0,
            max_lower: MAX_LIMIT_SHIFTED,
            min_upper: 0,
            max_upper: MAX_LIMIT_SHIFTED,
            min_width: 1,
            max_width: MAX_WIDTH,
        }
    }
}

// Market setting controlling the status of a feature.
//
// * `Enabled` - setting is enabled for all users
// * `Disabled` - setting is disabled for all users
// * `OnlyOwner` - setting is enabled only for market owner
// * `OnlyStrategy` - setting is enabled only for the market strategy
#[derive(Copy, Drop, Serde, PartialEq)]
pub enum ConfigOption {
    Enabled,
    Disabled,
    OnlyOwner,
    OnlyStrategy,
}

// Mutable state of a market.
//
// * `liquidity` - active liquidity in market
// * `curr_limit` - current limit (shifted)
// * `curr_sqrt_price` - current sqrt price of market (constrained to felt252)
// * `base_fee_factor` - accumulated base fees per unit of liquidity (constrained to felt252)
// * `quote_fee_factor` - accumulated quote fees per unit of liquidity (constrained to felt252)
#[derive(Copy, Drop, Serde, PartialEq, Default)]
pub struct MarketState {
    pub liquidity: u128,
    pub curr_limit: u32,
    pub curr_sqrt_price: u256,
    pub base_fee_factor: u256,
    pub quote_fee_factor: u256,
}

// An individual price limit.
//
// * `liquidity` - total liquidity referenced by limit
// * `liquidity_delta` - liquidity added or removed from limit when it is traversed
// * `base_fee_factor` - cumulative base fee factor outside of current price (constrained to felt252)
// * `quote_fee_factor` - cumulative quote fee factor outside of current price (constrained to felt252) 
// * `nonce` - current nonce of limit, used for batching limit orders
#[derive(Copy, Drop, Serde)]
pub struct LimitInfo {
    pub liquidity: u128,
    pub liquidity_delta: i128,
    pub base_fee_factor: u256,
    pub quote_fee_factor: u256,
    pub nonce: u128,
}

// A liquidity position.
//
// * `market_id` - market id of position
// * `lower_limit` - lower limit of position
// * `upper_limit` - upper limit of position
// * `liquidity` - amount of liquidity in position
// * `base_fee_factor_last` - base fee factor of position at last update
// * `quote_fee_factor_last` - quote fee factor of position at last update
#[derive(Copy, Drop, Serde)]
pub struct Position {
    pub market_id: felt252,
    pub lower_limit: u32,
    pub upper_limit: u32,
    pub liquidity: u128,
    pub base_fee_factor_last: i256,
    pub quote_fee_factor_last: i256,
}

// Information about batched limit orders within a nonce.
//
// * `liquidity` - total liquidity of limit orders in batch
// * `filled` - whether batch has been fully filled and removed from order book
// * `limit` - limit of batch
// * `is_bid` - whether limit orders are bids or asks
// * `base_amount` - base amounts withdrawn and pending collection
// * `quote_amount` - quote amounts withdrawn and pending collection
#[derive(Copy, Drop, Serde, PartialEq)]
pub struct OrderBatch {
    pub liquidity: u128,
    pub filled: bool,
    pub limit: u32,
    pub is_bid: bool,
    pub base_amount: u128,
    pub quote_amount: u128,
}

// A limit order.
//
// * `batch_id` - order batch to which order belongs
// * `liquidity` - liquidity of order
#[derive(Copy, Drop, Serde)]
pub struct LimitOrder {
    pub batch_id: felt252,
    pub liquidity: u128,
}

// Information about a swap.
//
// * `is_buy` - whether swap is buy or sell
// * `amount` - amount swapped in or out
// * `exact_input` - whether amount is exact input or exact output
#[derive(Copy, Drop, Serde)]
pub struct SwapParams {
    pub is_buy: bool,
    pub amount: u256,
    pub exact_input: bool,
}

// Strategy position info.
//
// * `lower_limit` - lower limit of position
// * `upper_limit` - upper limit of position
// * `liquidity` - liquidity of position
#[derive(Copy, Drop, Serde, starknet::Store, Default, PartialEq)]
pub struct PositionInfo {
    pub lower_limit: u32,
    pub upper_limit: u32,
    pub liquidity: u128,
}

// Depth data.
//
// * `limit` - price limit
// * `liquidity_delta` - liquidity delta at price limit
#[derive(Copy, Drop, Serde, PartialEq)]
pub struct Depth {
    pub limit: u32,
    pub price: u256,
    pub liquidity_delta: i128,
}

// Position info returned for ERC721.
//
// * `base_token` - base token address
// * `quote_token` - quote token address
// * `width` - width of market position is in
// * `strategy` - strategy contract address of market
// * `swap_fee_rate` - swap fee denominated in bps
// * `fee_controller` - fee controller contract address of market (or 0 if not controlled)
// * `controller` - controller contract address of market (or 0 if not controlled)
// * `liquidity` - liquidity of position
// * `base_amount` - amount of base tokens inside position
// * `quote_amount` - amount of quote tokens inside position
// * `lower_limit` - lower limit of position
// * `upper_limit` - upper limit of position
#[derive(Copy, Drop, Serde)]
pub struct ERC721PositionInfo {
    pub base_token: ContractAddress,
    pub quote_token: ContractAddress,
    pub width: u32,
    pub strategy: ContractAddress,
    pub swap_fee_rate: u16,
    pub fee_controller: ContractAddress,
    pub controller: ContractAddress,
    pub liquidity: u128,
    pub base_amount: u256,
    pub quote_amount: u256,
    pub lower_limit: u32,
    pub upper_limit: u32,
}

////////////////////////////////
// PACKED TYPES
////////////////////////////////

// Packed version of `MarketInfo`.
//
// * `base_token` - address of base token
// * `quote_token` - address of quote token
// * `strategy` - liquidity strategy contract
// * `fee_controller` - fee controller contract
// * `controller` - market controller (or 0 if market is not controlled)
// * `slab0` - packed `width` + `swap_fee_rate`
#[derive(starknet::Store)]
pub struct PackedMarketInfo {
    pub base_token: felt252,
    pub quote_token: felt252,
    pub strategy: felt252,
    pub fee_controller: felt252,
    pub controller: felt252,
    pub slab0: felt252,
}

// Packed version of `MarketState`.
//
// * `curr_sqrt_price` - curr_sqrt_price (constrained to felt252)
// * `base_fee_factor` - base_fee_factor (constrained to felt252)
// * `quote_fee_factor` - quote_fee_factor (constrained to felt252)
// * `slab0` - `curr_limit` + `liquidity`
#[derive(starknet::Store)]
pub struct PackedMarketState {
    pub curr_sqrt_price: felt252,
    pub base_fee_factor: felt252,
    pub quote_fee_factor: felt252,
    pub slab0: felt252,
}

// Packed version of `MarketConfigs`.
// 
// `ValidLimits` - 128 bits
// `ConfigOption` - 2 bits for variants
// `Config` - 1 bit
//
// * `slab` - 128 bits of `ValidLimits` + 12 bits of `ConfigOption`s + 7 bits of `Config`s
#[derive(starknet::Store)]
pub struct PackedMarketConfigs {
    pub slab: felt252,
}

// Packed version of `LimitInfo`.
//
// * `base_fee_factor` - `base_fee_factor` (constrained to felt252)
// * `quote_fee_factor` - `quote_fee_factor` (constrained to felt252)
// * `slab0` - `liquidity` + first 124 bits of `liquidity_delta`
// * `slab1` - last 4 bits of `liquidity_delta` + sign of `liquidity_delta` + `nonce` 
#[derive(starknet::Store)]
pub struct PackedLimitInfo {
    pub base_fee_factor: felt252,
    pub quote_fee_factor: felt252,
    pub slab0: felt252,
    pub slab1: felt252,
}

// Packed version of `OrderBatch`.
//
// * `slab0` - first 128 bits of `base_amount` + first 124 bits of `quote_amount`
// * `slab1` - last 4 bits of `quote_amount` + `filled` + `is_bid` + `limit` + `liquidity`
#[derive(starknet::Store)]
pub struct PackedOrderBatch {
    pub slab0: felt252,
    pub slab1: felt252,
}

// Packed version of `Position`.
//
// * `market_id` - market id
// * `base_fee_factor_last` - `base_fee_factor_last` (constrained to felt252, with sign packed at top bit)
// * `quote_fee_factor_last` - `quote_fee_factor_last` (constrained to felt252, with sign packed at top bit)
// * `slab0` - `lower_limit` + `upper_limit` + `liquidity`
#[derive(starknet::Store)]
pub struct PackedPosition {
    pub market_id: felt252,
    pub base_fee_factor_last: felt252,
    pub quote_fee_factor_last: felt252,
    pub slab0: felt252,
}

// A limit order.
//
// * `batch_id` - batch id
// * `liquidity` - liquidity of order coerced to felt252
#[derive(starknet::Store)]
pub struct PackedLimitOrder {
    pub batch_id: felt252,
    pub liquidity: felt252,
}
