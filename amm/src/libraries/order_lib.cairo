// Core lib imports.
use starknet::ContractAddress;
use starknet::get_caller_address;

// Local imports.
use amm::libraries::{id, liquidity_lib};
use amm::libraries::math::{math, price_math, fee_math, liquidity_math};
use amm::libraries::constants::ONE;
use amm::contracts::market_manager::MarketManager::{ContractState, MarketManagerInternalTrait};
use amm::contracts::market_manager::MarketManager::{
    orders::InternalContractMemberStateTrait as OrderStateTrait,
    limit_info::InternalContractMemberStateTrait as LimitInfoStateTrait,
    batches::InternalContractMemberStateTrait as BatchStateTrait,
    positions::InternalContractMemberStateTrait as PositionStateTrait,
    market_info::InternalContractMemberStateTrait as MarketInfoStateTrait,
};
use amm::types::core::{OrderBatch, LimitInfo};
use amm::types::i128::{i128, I128Trait};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

// Returns total amount of tokens inside of a limit order.
// User's share of batch is calculated based on the liquidity of their order relative to the 
// total liquidity of the batch. If we are collecting from the batch and it has not yet been 
// filled, we need to first remove our share of batch liquidity from the pool. However, if 
// the batch has accrued fees (e.g. through partial fills), it will also withdraw all fees
// from the position. To discourage this, fees are forfeited and not paid out to the user if 
// they collect from an unfilled batch.
// 
// # Arguments
// * `order_id` - order id
// * `market_id` - market id
//
// # Returns
// * `base_amount` - amount of base tokens inside order
// * `quote_amount` - amount of quote tokens inside order
fn amounts_inside_order(
    self: @ContractState, order_id: felt252, market_id: felt252
) -> (u256, u256) {
    // Get order and batch info.
    let market_info = self.market_info.read(market_id);
    let order = self.orders.read(order_id);
    let batch = self.batches.read(order.batch_id);

    // Calculate batch token amounts.
    let (batch_base, batch_quote) = if !batch.filled {
        let position_id = id::position_id(market_id, order.batch_id, batch.limit, batch.limit + market_info.width);
        let (base_amount, quote_amount, _, _) = liquidity_lib::amounts_inside_position(self, position_id);
        (base_amount, quote_amount)
    } else {
        (batch.base_amount.into(), batch.quote_amount.into())
    };

    // Allocate batch liquidity to order.
    let base_amount = math::mul_div(batch_base, order.liquidity.into(), batch.liquidity.into(), false);
    let quote_amount = math::mul_div(batch_quote, order.liquidity.into(), batch.liquidity.into(), false);

    (base_amount, quote_amount)
}

// Fully fill orders at the given limits.
// Calling `swap` returns an array of limits that were fully filled. This function iterates through
// this list and removes batch liquidity from the market.
// 
// # Arguments
// * `market_id` - market ID
// * `width` - limit width of market
// * `filled_limits` - list of limits that were fully filled, along with associated batch ids
fn fill_limits(
    ref self: ContractState, market_id: felt252, width: u32, filled_limits: Span<(u32, felt252)>,
) {
    let mut i = filled_limits.len();
    loop {
        if i == 0 {
            break;
        }

        // Get batch info.
        let (limit, batch_id) = *filled_limits.at(i - 1);
        let mut batch = self.batches.read(batch_id);

        // Remove liquidity from position.
        let (base_amount, quote_amount, base_fees, quote_fees) = self
            ._modify_position(
                batch_id,
                market_id,
                limit,
                limit + width,
                I128Trait::new(batch.liquidity, true),
                true
            );

        // Update batch info. If partial fills and unfills occured prior to the batch being fully
        // filled, the batch could have accrued swap fees in the opposite asset. Therefore, they
        // should be paid out to limit order placers. 
        batch.filled = true;
        batch.base_amount = base_amount.val.try_into().expect('BatchBaseAmtOF');
        batch.quote_amount = quote_amount.val.try_into().expect('BatchQuoteAmtOF');
        self.batches.write(batch_id, batch);

        // Update limit info. Limit info is changed by `modify_position` so must be refetched here.
        let mut limit_info = self.limit_info.read((market_id, limit));
        limit_info.nonce += 1;
        self.limit_info.write((market_id, limit), limit_info);

        // Move to next order.
        i -= 1;
    };
}

// Partially fill orders at the given limit.
// Calling `swap` may result in partially filling liquidity at a limit. This function updates the
// current order batch for the partially filled amount, either filling if swap is in the opposite
// direction of the order, or unfilling if swap is in the same direction as the order.
//
// # Arguments
// * `market_id` - market ID
// * `limit` - limit of market
// * `amount_in` - amount in
// * `amount_out` - amount out
// * `is_buy` - whether the order is a buy order
fn fill_partial_limit(
    ref self: ContractState,
    market_id: felt252,
    limit: u32,
    amount_in: u256,
    amount_out: u256,
    is_buy: bool,
) {
    // Get limit and batch info.
    let partial_limit_info = self.limit_info.read((market_id, limit));
    let batch_id = id::batch_id(market_id, limit, partial_limit_info.nonce);
    let mut batch = self.batches.read(batch_id);

    // Return if batch does not exist.
    if batch.liquidity == 0 {
        return;
    }
    // Otherwise, update for partial fill.
    // Fill
    let amount_in_u128: u128 = amount_in.try_into().expect('AmountInU128OF');
    let amount_out_u128: u128 = amount_out.try_into().expect('AmountOutU128OF');
    if is_buy != batch.is_bid {
        if batch.is_bid {
            batch.quote_amount -= amount_out_u128;
            batch.base_amount += amount_in_u128;
        } else {
            batch.base_amount -= amount_out_u128;
            batch.quote_amount += amount_in_u128;
        }
    } // Unfill 
    else {
        if batch.is_bid {
            batch.quote_amount += amount_in_u128;
            batch.base_amount -= amount_out_u128;
        } else {
            batch.base_amount += amount_in_u128;
            batch.quote_amount -= amount_out_u128;
        }
    }

    // Commit changes.
    self.batches.write(batch_id, batch);
}
