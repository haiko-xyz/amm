// Core lib imports.
use traits::{Into, TryInto};
use array::ArrayTrait;
use serde::Serde;
use integer::u256_from_felt252;
use starknet::ContractAddress;
use starknet::ContractAddressIntoFelt252;
use poseidon::poseidon_hash_span;

// Local imports.
use amm::types::core::MarketInfo;

// Compute market id.
//   Poseidon(base_token, quote_token, width, strategy, swap_fee_rate, fee_controller, allow_positions, allow_orders)
//
// # Arguments
// * `base_token` - address of the base token
// * `quote_token` - address of the quote token
// * `width` - price width of the market
// * `strategy` - address of the strategy contract
// * `swap_fee_rate` - swap fee rate
// * `fee_controller` - address of the fee controller contract
// * `allow_positions` - whether positions are allowed
// * `allow_orders` - whether orders are allowed
//
// # Returns
// * `salt` - salt for Starknet contract address
fn market_id(params: MarketInfo) -> felt252 {
    let mut input = ArrayTrait::<felt252>::new();
    params.base_token.serialize(ref input);
    params.quote_token.serialize(ref input);
    params.width.serialize(ref input);
    params.strategy.serialize(ref input);
    params.swap_fee_rate.serialize(ref input);
    params.fee_controller.serialize(ref input);
    params.allow_positions.serialize(ref input);
    params.allow_orders.serialize(ref input);
    poseidon_hash_span(input.span())
}

// Compute position id.
//   Poseidon(market_id, owner, lower_limit, upper_limit)
//
// # Arguments
// * `market_id` - id of market where position is placed
// * `owner` - owner of the position
// * `lower_limit` - limit ID where position starts
// * `upper_limit` - limit ID where position ends
//
// # Returns
// * `position_id` - The position ID
fn position_id(market_id: felt252, owner: felt252, lower_limit: u32, upper_limit: u32,) -> felt252 {
    let mut input = ArrayTrait::<felt252>::new();
    market_id.serialize(ref input);
    owner.serialize(ref input);
    lower_limit.serialize(ref input);
    upper_limit.serialize(ref input);
    poseidon_hash_span(input.span())
}

// Compute order batch id.
//   Poseidon(market_id, limit, nonce)
// 
// # Arguments
// * `market_id` - id of market where order is placed
// * `limit` - limit ID where order is placed
// * `nonce` - nonce of the order
//
// # Returns
// * `batch_id` - The order ID
fn batch_id(market_id: felt252, limit: u32, nonce: u128,) -> felt252 {
    let mut input = ArrayTrait::<felt252>::new();
    market_id.serialize(ref input);
    limit.serialize(ref input);
    nonce.serialize(ref input);
    poseidon_hash_span(input.span())
}

// Compute order id.
//   Poseidon(market_id, limit, nonce, owner)
// 
// # Arguments
// * `market_id` - id of market where order is placed
// * `limit` - limit ID where order is placed
// * `nonce` - nonce of the order
// * `owner` - owner of the order
//
// # Returns
// * `order_id` - The order ID
fn order_id(market_id: felt252, limit: u32, nonce: u128, owner: ContractAddress,) -> felt252 {
    let mut input = ArrayTrait::<felt252>::new();
    market_id.serialize(ref input);
    limit.serialize(ref input);
    nonce.serialize(ref input);
    owner.serialize(ref input);
    poseidon_hash_span(input.span())
}
