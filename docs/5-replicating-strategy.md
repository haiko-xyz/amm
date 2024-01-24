# Replicating Strategy

This document describes the [Replicating Strategy](../strategies/src/strategies/replicating/replicating_strategy.cairo) for Haiko.

At a high level, the strategy seeks to replicate the actions of sophisticated market makers on external exchanges by placing up to two liquidity positions (bid and ask) around a reference oracle price.

## Objectives

The strategy is designed with three goals in mind:

1. Maximise net profitability, i.e. accrue swap fees that exceed the losses from rebalancing and portfolio skew
2. Minimise loss versus rebalancing and toxicity of fulfilled trades
3. Minimise portfolio imbalance, maintaining base and quote assets at 50/50 ratio.

## Implementation

To achieve this, the strategy places two liquidity positions (bid and ask) around a reference oracle price. These positions are based a number of parameters:

- `ref_price` - the reference oracle price
- `min_spread` - the minimum spread to deduct from `ref_price` for bids, and add to `ref_price` for asks
- `range` - the range of the bid and ask positions
- `max_delta` - the maximum additional spread, which is multipled by the portfolio imbalance factor (ranging -1 to 1) to get the inventory delta `inv_delta`

```
bid = [bid_lower, bid_upper]
bid_upper = ref_price - min_spread + inv_delta
bid_lower = bid_upper - range

ask = [ask_lower, ask_upper]
ask_lower = ref_price + min_spread + inv_delta
ask_upper = ask_lower + range
```

Note that:

- A minimum spread `min_spread` is added to the oracle price to account for delays in oracle updates and deviations in reported prices.
- The spread is dynamically adjusted via `max_delta` to offset portfolio imbalances in the strategy. For example, if the strategy is under-weighted in quote assets, a spread will be added to the bid position (reducing the bid price relative to the reference price) to discourage further increases in quote tokens.
- The positions are placed such that they never cross the spread. This means that the computed positions are always below the current price for bids, and above the current price for asks.

### LVR rebalancing rule

The positions in the strategy are rebalanced whenever a swap occur (specifically before the swap), to ensure they are always placed around the latest oracle price.

That is, unless a special condition is met - if the fees earned from a trade are expected to be greater than the loss incurred from fulfilling the trade at the best price (i.e. LVR < fees), then rebalancing does not happen.

This allows the strategy to update its positions at a minimally viable frequency while still remaining unexploitable by arbitrageurs.

## Other features

The strategy implements a number of other useful features.

### Multi-market support

Like the `MarketManager` contract, the strategy supports multiple markets to avoid the gas costs of deploying new strategies for each market. This works by registering each market with the strategy contract and storing the market's parameters in a mapping.

All strategy actions need to be called by passing in `market_id` as a parameter. Each market strategy can have a unique strategy owner, which is set at the time of market registration.

### Deposits / withdrawals

The strategy has the option to support deposits and withdrawals by third parties. These are accounted for with the `user_deposits` and `total_deposits` mappings. An ERC20 token is not used to track token deposits because this is not feasible with a singleton contract.

Strategies can also choose to disable deposits.

### Pausing / unpausing

The strategy can be paused and unpaused by the owner. When paused, the strategy will not place any new liquidity positions or collect any fees. This is useful for emergency situations or when the strategy needs to be upgraded.

### Oracle price guard

The strategy implements a price guard that prevents the oracle price from moving too far away from the reference price. This prevents both oracle price attacks, as well as attempts to manipulate the market price.

This is achieved by setting a maximum price delta `max_oracle_dev`, denominated in limits, which if exceeded will automatically collect all positions and pause the strategy.

### Variable strategy params

The key strategy params such as `min_spread` and `range` can be expressed either as fixed values (denominated in limits) or variable values expresseed as a function of market volatility. Variable limits are defined over the following parameters:

- `base` - the base value
- `default_vol` - the default volatility
- `vol` - the current volatility (vol / default_vol is the volatility factor)
- `muliplier` - the multiplier to apply to the volatility factor
- `is_min_base` - whether the value is bounded by `base` as a minimum

At the moment, variable limits are disabled because volatility feeds are not yet fully supported by Pragma.
