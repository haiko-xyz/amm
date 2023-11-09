// Core lib imports.
use core::traits::TryInto;
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
use amm::contracts::market_manager::MarketManager::InternalTrait;
use amm::libraries::tree;
use amm::libraries::id;
use amm::types::core::{LimitInfo, MarketState, MarketInfo, Position};
use amm::libraries::math::{liquidity_math, price_math, fee_math, math};
use amm::libraries::constants::{ONE, MAX_UNSCALED, MAX, HALF, MAX_NUM_LIMITS};
use amm::types::i256::{I256Trait, i256, I256Zeroable};
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
    liquidity_delta: i256,
) -> (i256, i256, u256, u256) {
    // Initialise state.
    let mut market_state = self.market_state.read(market_id);
    let curr_limit = market_state.curr_limit;
    let width = *market_info.width;

    // Update limits and bitmap.
    let lower_limit_info = update_limit(
        ref self, lower_limit, @market_state, market_id, curr_limit, liquidity_delta, true, width
    );
    let upper_limit_info = update_limit(
        ref self, upper_limit, @market_state, market_id, curr_limit, liquidity_delta, false, width
    );
    self.limit_info.write((market_id, lower_limit), lower_limit_info);
    self.limit_info.write((market_id, upper_limit), upper_limit_info);

    // If writing to position for first time, initialise immutables.
    let position_id = id::position_id(market_id, owner, lower_limit, upper_limit);
    let mut position = self.positions.read(position_id);
    if position.market_id == 0 {
        position.market_id = market_id;
        position.lower_limit = lower_limit;
        position.upper_limit = upper_limit;
    }

    // Get fee factors and calculate accrued fees.
    let (base_fee_factor, quote_fee_factor) = fee_math::get_fee_inside(
        lower_limit_info,
        upper_limit_info,
        lower_limit,
        upper_limit,
        market_state.curr_limit,
        market_state.base_fee_factor,
        market_state.quote_fee_factor,
    );
    // Asserts added here for debugging u256 overflow issues - can likely remove later.
    assert(base_fee_factor >= position.base_fee_factor_last, 'UpdateLiqBaseFees');
    let base_fees = math::mul_div(
        (base_fee_factor - position.base_fee_factor_last), position.liquidity, ONE, false
    );
    assert(quote_fee_factor >= position.quote_fee_factor_last, 'UpdateLiqQuoteFees');
    let quote_fees = math::mul_div(
        (quote_fee_factor - position.quote_fee_factor_last), position.liquidity, ONE, false
    );

    // Update liquidity position.
    if liquidity_delta.sign {
        assert(position.liquidity >= liquidity_delta.val, 'UpdatePosLiq');
    }
    liquidity_math::add_delta(ref position.liquidity, liquidity_delta);
    if !liquidity_delta.sign {
        assert(position.liquidity.into() < MAX, 'PosLiqOverflow');
    }
    position.base_fee_factor_last = base_fee_factor;
    position.quote_fee_factor_last = quote_fee_factor;

    // Write updates to position.
    self.positions.write(position_id, position);

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
            market_state.curr_limit,
            market_state.curr_sqrt_price,
            liquidity_delta,
            lower_limit,
            upper_limit,
            width,
        )
    };

    // Add fees to amounts.
    let base_total = base_amount + I256Trait::new(base_fees, true);
    let quote_total = quote_amount + I256Trait::new(quote_fees, true);

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
    liquidity_delta: i256,
    is_start: bool,
    width: u32,
) -> LimitInfo {
    // Fetch limit.
    let mut limit_info = self.limit_info.read((market_id, limit));

    // Add liquidity to limit.
    let liquidity_before = limit_info.liquidity;
    if liquidity_delta.sign {
        assert(limit_info.liquidity >= liquidity_delta.val, 'UpdateLimitLiq');
    }
    liquidity_math::add_delta(ref limit_info.liquidity, liquidity_delta);
    let directional_liquidity_delta = if is_start {
        liquidity_delta
    } else {
        I256Trait::new(liquidity_delta.val, !liquidity_delta.sign)
    };
    limit_info.liquidity_delta += directional_liquidity_delta;

    // Check for liquidity overflow.
    if !liquidity_delta.sign {
        assert(limit_info.liquidity.into() <= max_liquidity_per_limit(width), 'LimitLiqOverflow');
    }

    // Update bitmap if necessary.
    if (liquidity_before == 0) != (limit_info.liquidity == 0) {
        tree::flip(ref self, market_id, width, limit);
    }

    // When liquidity at limit is first initialised, fee factor is set to either 0 or global fees:
    //   * Case 1: limit <= curr_limit -> fee factor = market fee factor
    //   * Case 2: limit > curr_limit -> fee factor = 0
    if liquidity_before == 0 && !limit_info.initialised && limit <= *market_state.curr_limit {
        limit_info.base_fee_factor = *market_state.base_fee_factor;
        limit_info.quote_fee_factor = *market_state.quote_fee_factor;
        limit_info.initialised = true;
    }

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
// * `base_fees` - base tokens accrued in fees
// * `quote_fees` - quote tokens accrued in fees
fn amounts_inside_position(
    self: @ContractState,
    market_id: felt252,
    position_id: felt252,
    lower_limit: u32,
    upper_limit: u32,
) -> (u256, u256) {
    // Fetch state.
    let market_state = self.market_state.read(market_id);
    let market_info = self.market_info.read(market_id);
    let position = self.positions.read(position_id);
    let lower_limit_info = self.limit_info.read((market_id, lower_limit));
    let upper_limit_info = self.limit_info.read((market_id, upper_limit));

    // Get fee factors and calculate accrued fees.
    let (base_fee_factor, quote_fee_factor) = fee_math::get_fee_inside(
        lower_limit_info,
        upper_limit_info,
        position.lower_limit,
        position.upper_limit,
        market_state.curr_limit,
        market_state.base_fee_factor,
        market_state.quote_fee_factor,
    );

    // Calculate fees accrued since last update.
    // Includes various asserts for debugging u256_overflow errors - can be removed later.
    assert(base_fee_factor >= position.base_fee_factor_last, 'AmtsInsideBaseFeeFactor');
    let base_fees = math::mul_div(
        (base_fee_factor - position.base_fee_factor_last), position.liquidity.into(), ONE, false
    );
    assert(quote_fee_factor >= position.quote_fee_factor_last, 'AmtsInsideQuoteFeeFactor');
    let quote_fees = math::mul_div(
        (quote_fee_factor - position.quote_fee_factor_last), position.liquidity.into(), ONE, false
    );

    // Calculate amounts inside position.
    let (base_amount, quote_amount) = liquidity_math::liquidity_to_amounts(
        market_state.curr_limit,
        market_state.curr_sqrt_price,
        I256Trait::new(position.liquidity, false),
        position.lower_limit,
        position.upper_limit,
        market_info.width,
    );

    // Return amounts
    (base_amount.val + base_fees, quote_amount.val + quote_fees)
}

// Calculate max liquidity per limit.
//
// # Arguments
// * `market_id` - market id
fn max_liquidity_per_limit(width: u32) -> u256 {
    let intervals = MAX_NUM_LIMITS / width + if MAX_NUM_LIMITS % width != 0 {
        1
    } else {
        0
    };
    MAX_UNSCALED / intervals.into()
}