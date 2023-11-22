// Core lib imports.
use traits::Into;
use amm::types::core::Position;
use amm::types::i256::I256Trait;
use amm::libraries::constants::ONE;

// Local imports.
use amm::libraries::math::math;
use amm::libraries::constants::MAX_FEE_RATE;
use amm::types::core::{LimitInfo, MarketState};

////////////////////////////////
// FUNCTIONS
////////////////////////////////

// Calculates fee, rounding up.
//
// # Arguments
// `amount` - The amount on which the fee is applied
// `fee_rate` - The fee rate denominated in basis points
//
// # Returns
// * `fee` - The fee amount
fn calc_fee(amount: u256, fee_rate: u16,) -> u256 {
    assert(fee_rate <= MAX_FEE_RATE, 'FeeRateOverflow');
    math::mul_div(amount, fee_rate.into(), MAX_FEE_RATE.into(), true)
}

// Calculate amount net of fees to fee.
//
// # Arguments
// * `net_amount` - Amount net of fees
// * `fee_rate` - Fee rate denominated in basis points
//
// # Returns
// * `fee` - Fee amount
fn net_to_fee(net_amount: u256, fee_rate: u16,) -> u256 {
    assert(fee_rate <= MAX_FEE_RATE, 'FeeRateOverflow');
    math::mul_div(net_amount, fee_rate.into(), MAX_FEE_RATE.into() - fee_rate.into(), false)
}

// Calculate amount net of fees to gross amount.
//
// # Arguments
// * `net_amount` - Amount net of fees
// * `fee_rate` - Fee rate denominated in basis points
//
// # Returns
// * `fee` - Fee amount
fn net_to_gross(net_amount: u256, fee_rate: u16,) -> u256 {
    assert(fee_rate <= MAX_FEE_RATE, 'FeeRateOverflow');
    math::mul_div(net_amount, MAX_FEE_RATE.into(), MAX_FEE_RATE.into() - fee_rate.into(), false)
}

// Converts amount net of fees to amount gross of fees.
// Rounds down as fees are calculated rounding up.
//
// # Arguments
// * `net_amount` - Amount net of fees
// * `fee_rate` - Fee rate denominated in basis points
//
// # Returns
// * `gross_amount` - Amount gross of fees
fn gross_to_net(gross_amount: u256, fee_rate: u16) -> u256 {
    assert(fee_rate <= MAX_FEE_RATE, 'FeeRateOverflow');
    math::mul_div(gross_amount, (MAX_FEE_RATE - fee_rate).into(), MAX_FEE_RATE.into(), false)
}

// Calculates fees accumulated inside a position.
// Formula: global fees - fees below lower limit - fees above upper limit
//
// # Arguments
// * `lower_limit_info` - lower limit info struct
// * `upper_limit_info` - upper limit info struct
// * `lower_limit` - lower limit
// * `upper_limit` - upper limit
// * `position` - liquidity position
// * `curr_limit` - current limit
// * `global_base_fee_factor` - global base fees per unit liquidity
// * `global_quote_fee_factor` - global quote fees per unit liquidity
//
// # Returns
// * `base_fees` - base fees accrued inside position
// * `quote_fees` - quote fees accrued inside position
// * `base_fee_factor` - new position base fee factor after update
// * `quote_fee_factor` - new position quote fee factor after update
fn get_fee_inside(
    position: Position,
    lower_limit_info: LimitInfo,
    upper_limit_info: LimitInfo,
    lower_limit: u32,
    upper_limit: u32,
    curr_limit: u32,
    base_fee_factor: u256,
    quote_fee_factor: u256,
) -> (u256, u256, u256, u256) {
    // Note: includes various asserts for u256_overflow debugging purposes - can likely remove later.
    // Calculate fees accrued below current limit.
    let base_fees_below = if curr_limit >= lower_limit {
        lower_limit_info.base_fee_factor
    } else {
        assert(base_fee_factor >= lower_limit_info.base_fee_factor, 'GetFeeInsideBaseBelow');
        base_fee_factor - lower_limit_info.base_fee_factor
    };
    let quote_fees_below = if curr_limit >= lower_limit {
        lower_limit_info.quote_fee_factor
    } else {
        assert(quote_fee_factor >= lower_limit_info.quote_fee_factor, 'GetFeeInsideQuoteBelow');
        quote_fee_factor - lower_limit_info.quote_fee_factor
    };

    // Calculate fees accrued above current limit.
    let base_fees_above = if curr_limit < upper_limit {
        upper_limit_info.base_fee_factor
    } else {
        assert(base_fee_factor >= upper_limit_info.base_fee_factor, 'GetFeeInsideBaseAbove');
        base_fee_factor - upper_limit_info.base_fee_factor
    };
    let quote_fees_above = if curr_limit < upper_limit {
        upper_limit_info.quote_fee_factor
    } else {
        assert(base_fee_factor >= upper_limit_info.base_fee_factor, 'GetFeeInsideQuoteAbove');
        quote_fee_factor - upper_limit_info.quote_fee_factor
    };

    // Calculate fee factors inside position.
    assert(base_fee_factor >= base_fees_below + base_fees_above, 'GetFeeInsideBaseInside');
    assert(quote_fee_factor >= quote_fees_below + quote_fees_above, 'GetFeeInsideQuoteInside');
    let base_fee_factor_inside = base_fee_factor - base_fees_below - base_fees_above;
    let quote_fee_factor_inside = quote_fee_factor - quote_fees_below - quote_fees_above;

    // Calculate accrued fees.
    let base_diff = I256Trait::new(base_fee_factor_inside, false)
        - I256Trait::new(position.base_fee_factor_last, false);
    let quote_diff = I256Trait::new(quote_fee_factor_inside, false)
        - I256Trait::new(position.quote_fee_factor_last, false);
    let base_fees = math::mul_div(base_diff.val, position.liquidity, ONE, false);
    let quote_fees = math::mul_div(quote_diff.val, position.liquidity, ONE, false);

    // Return accrued fes and fee factors.
    (base_fees, quote_fees, base_fee_factor_inside, quote_fee_factor_inside)
}
