use snforge_std::forge_print::PrintTrait;
// Core lib imports.
use starknet::ContractAddress;
use starknet::get_caller_address;

// Local imports.
use amm::libraries::id;
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
use amm::types::i256::{i256, I256Trait};

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

// Fully fill orders at the given limits.
// Calling `swap` returns an array of limits that were fully filled. This function iterates through
// this list and removes batch liquidity from the market.
// 
// # Arguments
// * `market_id` - market ID
// * `width` - limit width of market
// * `fee_rate` - fee rate of market
// * `filled_limits` - list of limits that were fully fill
fn fill_limits(
    ref self: ContractState,
    market_id: felt252,
    width: u32,
    fee_rate: u16,
    filled_limits: Span<u32>,
) {
    let gas_before = testing::get_available_gas();
    let mut i = filled_limits.len();
    loop {
        if i == 0 {
            break;
        }
        // Checkpoint: gas used in full iteration
        let gas_before = testing::get_available_gas();
        
        // Get batch info.
        let limit = *filled_limits.at(i - 1);
        let nonce = self.limit_info.read((market_id, limit)).nonce;
        let batch_id = id::batch_id(market_id, limit, nonce);
        let mut batch = self.batches.read(batch_id);

        // Fill limit orders if batch exists.
        if batch.liquidity != 0 {
            // Remove liquidity from position.
            let (base_amount, quote_amount, base_fees, quote_fees) = self
                ._modify_position(
                    batch_id,
                    market_id,
                    limit,
                    limit + width,
                    I256Trait::new(batch.liquidity, true),
                    true
                );

            // Update batch info. If partial fills and unfills occured prior to the batch being fully
            // filled, the batch could have accrued swap fees in the opposite asset. Therefore, they
            // should be paid out to limit order placers. 
            batch.filled = true;
            batch.base_amount = base_amount.val;
            batch.quote_amount = quote_amount.val;
            self.batches.write(batch_id, batch);

            // Update limit info. Limit info is changed by `modify_position` so must be refetched here.
            let mut limit_info = self.limit_info.read((market_id, limit));
            limit_info.nonce += 1;
            self.limit_info.write((market_id, limit), limit_info);
        }
        i -= 1;
        'fill_limits itr'.print();
        (gas_before - testing::get_available_gas()).print(); 
        // Checkpoint End
    };
    'fill_limits (itr) [T]'.print();
    (gas_before - testing::get_available_gas()).print(); 
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
    // Checkpoint: gas used in reading state
    let mut gas_before = testing::get_available_gas();
    // Get limit and batch info.
    let partial_limit_info = self.limit_info.read((market_id, limit));
    let batch_id = id::batch_id(market_id, limit, partial_limit_info.nonce);
    let mut batch = self.batches.read(batch_id);
    'FPL read state 1'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // Checkpoint End

    // Return if batch does not exist.
    if batch.liquidity == 0 {
        return;
    }

    // Checkpoint: gas used in updating partial fill
    gas_before = testing::get_available_gas();
    // Otherwise, update for partial fill.
    // Fill
    if is_buy != batch.is_bid {
        if batch.is_bid {
            batch.quote_amount -= amount_out;
            batch.base_amount += amount_in;
        } else {
            batch.base_amount -= amount_out;
            batch.quote_amount += amount_in;
        }
    } // Unfill 
    else {
        if batch.is_bid {
            batch.quote_amount += amount_in;
            batch.base_amount -= amount_out;
        } else {
            batch.base_amount += amount_in;
            batch.quote_amount -= amount_out;
        }
    }

    // Commit changes.
    self.batches.write(batch_id, batch);
    'FPL update fill 2'.print();
    (gas_before - testing::get_available_gas()).print(); 
    // Checkpoint End
}
