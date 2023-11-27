use snforge_std::forge_print::PrintTrait;
// Core lib imports.
use cmp::{min, max};
use core::traits::TryInto;
use integer::BoundedU256;
use traits::Into;
use option::OptionTrait;
use starknet::info::get_caller_address;
use starknet::ContractAddress;

// Local imports.
use amm::contracts::market_manager::MarketManager::{
    ContractState, market_info::InternalContractMemberStateTrait as MarketsStateTrait,
    positions::InternalContractMemberStateTrait as PositionsStateTrait,
    market_state::InternalContractMemberStateTrait as MarketStateTrait,
    limit_info::InternalContractMemberStateTrait as LimitInfoTrait,
};
use amm::contracts::market_manager::MarketManager::MarketManagerInternalTrait;
use amm::libraries::tree;
use amm::libraries::id;
use amm::types::core::{LimitInfo, MarketState, MarketInfo, Position};
use amm::libraries::math::{liquidity_math, price_math, fee_math, math};
use amm::types::i128::{I128Trait, i128};
use amm::types::i256::{i256, I256Trait, I256Zeroable};
use amm::interfaces::IMarketManager::IMarketManager;

////////////////////////////////
// FUNCTIONS
////////////////////////////////

// Helper function to add or remove liquidity from a position.
//
// # Arguments
// * `market_id` - market id
// * `owner` - user address (or batch id for limit orders)
// * `market_info` - struct containing current market state
// * `lower_limit` - lower limit of position
// * `upper_limit` - upper limit of position
// * `liquidity_delta` - amount of liquidity to add or remove from position
//
// # Returns
// * `base_amount` - base tokens to transfer in (+ve) or out (-ve), including fees
// * `quote_amount` - quote tokens to transfer in (+ve) or out (-ve), including fees
// * `base_fees` - base tokens collected in fees
// * `quote_fees` - quote tokens collected in fees
fn update_liquidity(
    ref self: ContractState,
    owner: felt252,
    market_info: @MarketInfo,
    market_id: felt252,
    lower_limit: u32,
    upper_limit: u32,
    liquidity_delta: i128,
) -> (i256, i256, u256, u256) {
    let mut gas_before = testing::get_available_gas();

    // Initialise state.
    let mut market_state = self.market_state.read(market_id);
    let curr_limit = market_state.curr_limit;
    let width = *market_info.width;

    'MP (upd_liq): read state'.print();
    (gas_before - testing::get_available_gas()).print(); 
    gas_before = testing::get_available_gas();

    // Update limits and bitmap.
    let lower_limit_info = update_limit(
        ref self, lower_limit, @market_state, market_id, curr_limit, liquidity_delta, true, width
    );
    self.limit_info.write((market_id, lower_limit), lower_limit_info);

    'MP (upd_liq): update lower [T]'.print();
    (gas_before - testing::get_available_gas()).print(); 
    gas_before = testing::get_available_gas();

    let upper_limit_info = update_limit(
        ref self, upper_limit, @market_state, market_id, curr_limit, liquidity_delta, false, width
    );
    self.limit_info.write((market_id, upper_limit), upper_limit_info);

    'MP (upd_liq): update upper [T]'.print();
    (gas_before - testing::get_available_gas()).print(); 
    gas_before = testing::get_available_gas();

    // If writing to position for first time, initialise immutables.
    let position_id = id::position_id(market_id, owner, lower_limit, upper_limit);
    let mut position = self.positions.read(position_id);
    if position.market_id == 0 {
        position.market_id = market_id;
        position.lower_limit = lower_limit;
        position.upper_limit = upper_limit;
    }

    'MP (upd_liq): init position'.print();
    (gas_before - testing::get_available_gas()).print(); 
    gas_before = testing::get_available_gas();

    // Get fee factors and calculate accrued fees.
    let (base_fees, quote_fees, base_fee_factor, quote_fee_factor) = fee_math::get_fee_inside(
        position,
        lower_limit_info,
        upper_limit_info,
        lower_limit,
        upper_limit,
        market_state.curr_limit,
        market_state.base_fee_factor,
        market_state.quote_fee_factor,
    );

    'MP (upd_liq): calc fees'.print();
    (gas_before - testing::get_available_gas()).print(); 
    gas_before = testing::get_available_gas();
    
    // Update liquidity position.
    if liquidity_delta.sign {
        assert(position.liquidity >= liquidity_delta.val, 'UpdatePosLiq');
    }
    liquidity_math::add_delta(ref position.liquidity, liquidity_delta);
    position.base_fee_factor_last = base_fee_factor;
    position.quote_fee_factor_last = quote_fee_factor;

    // Write updates to position.
    self.positions.write(position_id, position);

    'MP (upd_liq): update position'.print();
    (gas_before - testing::get_available_gas()).print(); 
    gas_before = testing::get_available_gas();

    // Calculate base and quote amounts to transfer.
    let (base_amount, quote_amount) = if liquidity_delta.val == 0 {
        (I256Zeroable::zero(), I256Zeroable::zero())
    } else {
        // Update global liquidity if range is active
        if lower_limit <= market_state.curr_limit && upper_limit > market_state.curr_limit {
            if liquidity_delta.sign {
                assert(market_state.liquidity >= liquidity_delta.val, 'UpdateLiqMarketLiq');
            }
            liquidity_math::add_delta(ref market_state.liquidity, liquidity_delta);
            self.market_state.write(market_id, market_state);
        }
        liquidity_math::liquidity_to_amounts(
            liquidity_delta,
            market_state.curr_sqrt_price,
            price_math::limit_to_sqrt_price(lower_limit, width),
            price_math::limit_to_sqrt_price(upper_limit, width),
            width,
        )
    };


    // Add fees to amounts.
    let base_total = base_amount + I256Trait::new(base_fees, true);
    let quote_total = quote_amount + I256Trait::new(quote_fees, true);

    'MP (upd_liq): calc token amts'.print();
    (gas_before - testing::get_available_gas()).print(); 

    // Return amounts.
    (base_total, quote_total, base_fees, quote_fees)
}

// Add or remove liquidity from a limit price and update bitmap.
// 
// # Arguments
// * `limit` - limit to update
// * `market_state` - struct containing current market state
// * `market_id` - market id
// * `curr_limit` - current limit of market
// * `liquidity_delta` - amount of liquidity to add or remove from position
// * `is_start` - whether limit is the start or end price of liquidity position
fn update_limit(
    ref self: ContractState,
    limit: u32,
    market_state: @MarketState,
    market_id: felt252,
    curr_limit: u32,
    liquidity_delta: i128,
    is_start: bool,
    width: u32,
) -> LimitInfo {
    let mut gas_before = testing::get_available_gas();
    // Fetch limit.
    let mut limit_info = self.limit_info.read((market_id, limit));

    // Add liquidity to limits.
    let liquidity_before = limit_info.liquidity;
    if liquidity_delta.sign {
        assert(limit_info.liquidity >= liquidity_delta.val, 'UpdateLimitLiq');
    }
    liquidity_math::add_delta(ref limit_info.liquidity, liquidity_delta);
    if is_start {
        limit_info.liquidity_delta += liquidity_delta;
    } else {
        limit_info.liquidity_delta += I128Trait::new(liquidity_delta.val, !liquidity_delta.sign);
    }

    'MP (upd_lim): update limit'.print();
    (gas_before - testing::get_available_gas()).print(); 
    gas_before = testing::get_available_gas();

    // Check for liquidity overflow.
    if !liquidity_delta.sign {
        assert(
            limit_info.liquidity.into() <= liquidity_math::max_liquidity_per_limit(width),
            'LimitLiqOF'
        );
    }

    'MP (upd_lim): check overflow'.print();
    (gas_before - testing::get_available_gas()).print(); 
    gas_before = testing::get_available_gas();

    // Update bitmap if necessary.
    if (liquidity_before == 0) != (limit_info.liquidity == 0) {
        // Checkpoint: gas used in updating tree
        gas_before = testing::get_available_gas();
        tree::flip(ref self, market_id, width, limit);
    }

    'MP (upd_lim): update bitmap'.print();
    (gas_before - testing::get_available_gas()).print(); 
    gas_before = testing::get_available_gas();

    // When liquidity at limit is first initialised, fee factor is set to either 0 or global fees:
    //   * Case 1: limit <= curr_limit -> fee factor = market fee factor
    //   * Case 2: limit > curr_limit -> fee factor = 0
    if liquidity_before == 0 && limit <= *market_state.curr_limit {
        limit_info.base_fee_factor = *market_state.base_fee_factor;
        limit_info.quote_fee_factor = *market_state.quote_fee_factor;
    }

    'MP (upd_lim): fee factors'.print();
    (gas_before - testing::get_available_gas()).print(); 

    // Return limit info
    limit_info
}

// Get token amounts inside a position.
//
// # Arguments
// * `market_id` - market id
// * `position_id` - position id
// * `lower_limit` - lower limit of position
// * `upper_limit` - upper limit of position
//
// # Returns
// * `base_amount` - base tokens in position, including accrued fees
// * `quote_amount` - quote tokens in position, including accrued fees
fn amounts_inside_position(
    self: @ContractState,
    market_id: felt252,
    position_id: felt252,
    lower_limit: u32,
    upper_limit: u32,
) -> (u256, u256) {

    // Checkpoint: gas used in fetching contract state
    let mut gas_before = testing::get_available_gas();
    // Fetch state.
    let market_state = self.market_state.read(market_id);
    let market_info = self.market_info.read(market_id);
    let position = self.positions.read(position_id);
    let lower_limit_info = self.limit_info.read((market_id, lower_limit));
    let upper_limit_info = self.limit_info.read((market_id, upper_limit));
    'AIP read state 1'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // Checkpoint End

    // Checkpoint: gas used in calculating base/quote fee factor
    gas_before = testing::get_available_gas();
    // Get fee factors and calculate accrued fees.
    let (base_fees, quote_fees, _, _) = fee_math::get_fee_inside(
        position,
        lower_limit_info,
        upper_limit_info,
        position.lower_limit,
        position.upper_limit,
        market_state.curr_limit,
        market_state.base_fee_factor,
        market_state.quote_fee_factor,
    );
    'AIP calc fee factors 2'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // Checkpoint End

    // Checkpoint: gas used in calculating base/quote amounts for position
    gas_before = testing::get_available_gas();
    // Calculate amounts inside position.
    let (base_amount, quote_amount) = liquidity_math::liquidity_to_amounts(
        I128Trait::new(position.liquidity, true),
        market_state.curr_sqrt_price,
        price_math::limit_to_sqrt_price(position.lower_limit, market_info.width),
        price_math::limit_to_sqrt_price(position.upper_limit, market_info.width),
        market_info.width,
    );
    'AIP calc amounts 4'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // Checkpoint End

    // Return amounts
    (base_amount.val + base_fees, quote_amount.val + quote_fees)
}
