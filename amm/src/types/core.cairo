////////////////////////////////
// IMPORTS
////////////////////////////////

// Core lib imports.
use starknet::ContractAddress;
use starknet::StorePacking;
use option::Option;

// Local imports.
use amm::libraries::constants::{OFFSET, MAX_LIMIT, MAX_LIMIT_SHIFTED};
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
struct MarketInfo {
    base_token: ContractAddress,
    quote_token: ContractAddress,
    width: u32,
    strategy: ContractAddress,
    swap_fee_rate: u16,
    fee_controller: ContractAddress,
    controller: ContractAddress,
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
struct MarketConfigs {
    limits: Config<ValidLimits>,
    add_liquidity: Config<ConfigOption>,
    remove_liquidity: Config<ConfigOption>,
    create_bid: Config<ConfigOption>,
    create_ask: Config<ConfigOption>,
    collect_order: Config<ConfigOption>,
    swap: Config<ConfigOption>,
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
struct Config<T> {
    value: T,
    fixed: bool,
}

// Struct representing valid limits.
//
// * `min_lower` - minimum lower limit
// * `max_lower` - maximum lower limit
// * `min_upper` - minimum upper limit
// * `max_upper` - maximum upper limit
#[derive(Copy, Drop, Serde, PartialEq)]
struct ValidLimits {
    min_lower: u32,
    max_lower: u32,
    min_upper: u32,
    max_upper: u32,
}

// Default valid limits.
// Allows placing positions across entire market range.
impl DefaultValidLimits of Default<ValidLimits> {
    fn default() -> ValidLimits {
        ValidLimits {
            min_lower: 0, max_lower: MAX_LIMIT_SHIFTED, min_upper: 0, max_upper: MAX_LIMIT_SHIFTED,
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
enum ConfigOption {
    Enabled,
    Disabled,
    OnlyOwner,
    OnlyStrategy,
}

// Mutable state of a market.
//
// * `liquidity` - active liquidity in market
// * `curr_limit` - current limit (shifted)
// * `curr_sqrt_price` - current sqrt price of market (encoded as UD47x28)
// * `protocol_share` - protocol share denominated 0.01% shares of swap fees (e.g. 500 = 5%)
// * `base_fee_factor` - accumulated base fees per unit of liquidity (encoded as UD47x28)
// * `quote_fee_factor` - accumulated quote fees per unit of liquidity (encoded as UD47x28)
#[derive(Copy, Drop, Serde, PartialEq)]
struct MarketState {
    liquidity: u256,
    curr_limit: u32,
    curr_sqrt_price: u256,
    protocol_share: u16,
    base_fee_factor: u256,
    quote_fee_factor: u256,
}

// An individual price limit.
//
// * `liquidity` - total liquidity referenced by limit
// * `liquidity_delta` - liquidity added or removed from limit when it is traversed
// * `base_fee_factor` - as above, but for base fees (encoded as UD47x28)
// * `quote_fee_factor` - cumulative fee factor below or above current price depending on curr price (encoded as UD47x28) 
// * `nonce` - current nonce of limit, used for batching limit orders
#[derive(Copy, Drop, Serde)]
struct LimitInfo {
    liquidity: u256,
    liquidity_delta: i256,
    base_fee_factor: u256,
    quote_fee_factor: u256,
    nonce: u128,
}

// A liquidity position.
//
// * `market_id` - market id of position
// * `lower_limit` - lower limit of position
// * `upper_limit` - upper limit of position
// * `liquidity` - amount of liquidity in position
// * `base_fee_factor_last` - base fee factor of position at last update (encoded as UD47x28)
// * `quote_fee_factor_last` - quote fee factor of position at last update (encoded as UD47x28)
#[derive(Copy, Drop, Serde)]
struct Position {
    market_id: felt252,
    lower_limit: u32,
    upper_limit: u32,
    liquidity: u256,
    base_fee_factor_last: u256,
    quote_fee_factor_last: u256,
}

// Information about batched limit orders within a nonce.
//
// * `liquidity` - total liquidity of limit orders in batch
// * `filled` - whether batch has been fully filled and removed from order book
// * `limit` - limit of batch
// * `is_bid` - whether limit orders are bids or asks
// * `base_amount` - total base amount
// * `quote_amount` - total quote amount
#[derive(Copy, Drop, Serde, PartialEq)]
struct OrderBatch {
    liquidity: u256,
    filled: bool,
    limit: u32,
    is_bid: bool,
    base_amount: u256,
    quote_amount: u256,
}

// A limit order.
//
// * `batch_id` - order batch to which order belongs
// * `liquidity` - liquidity of order
#[derive(Copy, Drop, Serde)]
struct LimitOrder {
    batch_id: felt252,
    liquidity: u256,
}

// Information about a partial fill.
//
// * `limit` - limit price
// * `amount_in` - amount swapped in from partial fill, inclusive of fees
// * `amount_out` - amount swapped out from partial fill
// * `is_buy` - whether partial fill is buy or sell
#[derive(Copy, Drop, Serde)]
struct PartialFillInfo {
    limit: u32,
    amount_out: u256,
    amount_in: u256,
    is_buy: bool,
}

// Information about a swap.
//
// * `is_buy` - whether swap is buy or sell
// * `amount` - amount swapped in or out
// * `exact_input` - whether amount is exact input or exact output
// * `threshold_sqrt_price` - minimum sqrt price for sell or maximum sqrt price for buy
// * `deadline` - deadline for swap
#[derive(Copy, Drop, Serde)]
struct SwapParams {
    is_buy: bool,
    amount: u256,
    exact_input: bool,
    threshold_sqrt_price: Option<u256>,
    deadline: Option<u64>,
}

// Strategy position info.
//
// * `lower_limit` - lower limit of position
// * `upper_limit` - upper limit of position
// * `liquidity` - liquidity of position
#[derive(Copy, Drop, Serde, starknet::Store, Default, PartialEq)]
struct PositionInfo {
    lower_limit: u32,
    upper_limit: u32,
    liquidity: u256,
}

// Position info returned for ERC721.
//
// * `base_token` - base token address
// * `quote_token` - quote token address
// * `width` - width of market position is in
// * `strategy` - strategy contract address of market
// * `swap_fee_rate` - swap fee denominated in bps
// * `fee_controller` - fee controller contract address of market
// * `liquidity` - liquidity of position
// * `base_amount` - amount of base tokens inside position
// * `quote_amount` - amount of quote tokens inside position
// * `lower_limit` - lower limit of position
// * `upper_limit` - upper limit of position
#[derive(Copy, Drop, Serde)]
struct ERC721PositionInfo {
    base_token: ContractAddress,
    quote_token: ContractAddress,
    width: u32,
    strategy: ContractAddress,
    swap_fee_rate: u16,
    fee_controller: ContractAddress,
    liquidity: u256,
    base_amount: u256,
    quote_amount: u256,
    lower_limit: u32,
    upper_limit: u32,
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
struct PackedMarketInfo {
    base_token: felt252,
    quote_token: felt252,
    strategy: felt252,
    fee_controller: felt252,
    controller: felt252,
    slab0: felt252,
}

// Packed version of `MarketState`.
//
// * `slab0` - first 252 bits of `liquidity`
// * `slab1` - first 252 bits of `curr_sqrt_price`
// * `slab2` - first 252 bits of `quote_fee_factor`
// * `slab3` - first 252 bits of `base_fee_factor`
// * `slab4` - last 4 bits of four variables above + protocol_share + curr_limit
#[derive(starknet::Store)]
struct PackedMarketState {
    slab0: felt252,
    slab1: felt252,
    slab2: felt252,
    slab3: felt252,
    slab4: felt252,
}

// Packed version of `MarketConfigs`.
// 
// `ValidLimits` - 128 bits
// `ConfigOption` - 2 bits for variants
// `Config` - 1 bit
//
// * `slab` - 128 bits of `ValidLimits` + 12 bits of `ConfigOption`s + 7 bits of `Config`s
#[derive(starknet::Store)]
struct PackedMarketConfigs {
    slab: felt252,
}

// Packed version of `LimitInfo`.
//
// * `slab0` - first 252 bits of `liquidity`
// * `slab1` - first 252 bits of `liquidity_delta`
// * `slab2` - first 252 bits of `quote_fee_factor`
// * `slab3` - first 252 bits of `base_fee_factor`
// * `slab4` - last 4 bits of four variables above + sign of `liquidity_delta` + `nonce` 
#[derive(starknet::Store)]
struct PackedLimitInfo {
    slab0: felt252,
    slab1: felt252,
    slab2: felt252,
    slab3: felt252,
    slab4: felt252,
}

// Packed version of `OrderBatch`.
//
// * `slab0` - first 252 bits of `liquidity`
// * `slab1` - first 252 bits of `base_amount`
// * `slab2` - first 252 bits of `quote_amount`
// * `slab3` - last 4 bits of three variables above + `filled` + `is_bid` + `limit`
#[derive(starknet::Store)]
struct PackedOrderBatch {
    slab0: felt252,
    slab1: felt252,
    slab2: felt252,
    slab3: felt252,
}

// Packed version of `Position`.
//
// * `slab0` - market id
// * `slab1` - first 252 bits of `liquidity`
// * `slab2` - first 252 bits of `base_fee_factor_last`
// * `slab3` - first 252 bits of `quote_fee_factor_last`
// * `slab4` - last 4 bits of three variables above + 'lower_limit' + 'upper_limit'
#[derive(starknet::Store)]
struct PackedPosition {
    slab0: felt252,
    slab1: felt252,
    slab2: felt252,
    slab3: felt252,
    slab4: felt252,
}

// A limit order.
//
// * `batch_id` - batch id
// * `liquidity` - liquidity of order coerced to felt252
#[derive(starknet::Store)]
struct PackedLimitOrder {
    batch_id: felt252,
    liquidity: felt252,
}
