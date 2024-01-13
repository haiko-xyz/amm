import Decimal from "decimal.js"
import { PRECISION, ROUNDING } from "../../config"
import {
  limitToSqrtPrice,
  maxLimit,
  offset,
  priceToLimit,
  shiftLimit,
  sqrtPriceToLimit,
  unshiftLimit,
} from "../../math/priceMath"
import { baseToLiquidity, liquidityToQuote, quoteToLiquidity } from "../../math/liquidityMath"
import { computeSwapAmount, nextSqrtPriceAmountIn } from "../../libraries/swap"
import { calcFee } from "../../math/feeMath"
import { LOG_2_100001 } from "../../constants"

type Position = {
  lowerLimit: number
  upperLimit: number
  liquidity: Decimal.Value
}

// Helper functions.

const getBidAsk = (
  maxDelta: number,
  baseAmount: Decimal.Value,
  quoteAmount: Decimal.Value,
  price: number,
  width: number,
  currLimit: number,
  newLimit: number,
  minSpread: number,
  range: number
): { bid: Position; ask: Position } => {
  const { bidSpread, askSpread } = deltaSpread(maxDelta, baseAmount, quoteAmount, price)
  const { bidLimit: bidUpper, askLimit: askLower } = calcBidAsk(
    currLimit,
    newLimit,
    Number(bidSpread),
    Number(askSpread),
    minSpread,
    width
  )
  const bidLower = bidUpper - range
  const askUpper = askLower + range

  const quoteLiquidity = quoteToLiquidity(
    limitToSqrtPrice(bidLower, width),
    limitToSqrtPrice(bidUpper, width),
    quoteAmount
  )
  const baseLiquidity = baseToLiquidity(
    limitToSqrtPrice(askLower, width),
    limitToSqrtPrice(askUpper, width),
    baseAmount
  )
  const bid = {
    lowerLimit: bidLower,
    upperLimit: bidUpper,
    liquidity: quoteLiquidity,
  }
  const ask = {
    lowerLimit: askLower,
    upperLimit: askUpper,
    liquidity: baseLiquidity,
  }
  return { bid, ask }
}

const calcBidAsk = (
  currLimit: number,
  newLimit: number,
  bidDelta: number,
  askDelta: number,
  minSpread: number,
  width: number
) => {
  let bidSpread = minSpread + bidDelta
  let askSpread = minSpread + width + askDelta
  let rawBidLimit = bidSpread > newLimit || currLimit < width ? 0 : Math.min(currLimit, newLimit - bidSpread)
  let rawAskLimit = Math.min(Math.max(newLimit + askSpread, currLimit + width), Number(maxLimit(width)))

  let bidLimit = rawBidLimit - (rawBidLimit % width)
  let askLimit = rawAskLimit + (rawAskLimit % width === 0 ? 0 : width - (rawAskLimit % width))

  return { bidLimit, askLimit }
}

const deltaSpread = (maxDelta: number, baseAmount: Decimal.Value, quoteAmount: Decimal.Value, price: number) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const baseAmountInQuote = new Decimal(baseAmount).mul(price)
  const isBidDelta = baseAmountInQuote.lt(quoteAmount)
  const imbalancePct = new Decimal(quoteAmount)
    .sub(baseAmountInQuote)
    .div(new Decimal(quoteAmount).add(baseAmountInQuote))
    .abs()
  const spread = new Decimal(maxDelta).mul(imbalancePct)
  const bidSpread = isBidDelta ? spread : new Decimal(0)
  const askSpread = isBidDelta ? new Decimal(0) : spread
  return { bidSpread, askSpread }
}

const rebalanceConditionMet = (currLimit: number, newLimit: number, isBuy: boolean, swapFeeRate: number) => {
  let thresholdLimits = Decimal.log2(1 + swapFeeRate)
    .div(LOG_2_100001)
    .round()
    .toNumber()
  const rebalance = isBuy ? newLimit - currLimit > thresholdLimits : currLimit - newLimit > thresholdLimits
  console.log({ currLimit, newLimit, thresholdLimits, rebalance })
  return rebalance
}

// Tests

const testReplicatingStrategyDepositInitial = () => {
  const baseAmount = "1000000"
  const quoteAmount = "1112520000"
  const width = 10
  const currLimit = Number(shiftLimit(741930, width))
  const price = 1668.78
  const newLimit = Number(priceToLimit(price, width))
  const maxDelta = 200
  const minSpread = 10
  const range = 20000

  const { bidSpread, askSpread } = deltaSpread(maxDelta, baseAmount, quoteAmount, price)
  const { bidLimit: bidUpper, askLimit: askLower } = calcBidAsk(
    currLimit,
    newLimit,
    Number(bidSpread),
    Number(askSpread),
    minSpread,
    width
  )
  const bidLower = bidUpper - range
  const askUpper = askLower + range

  const quoteLiquidity = quoteToLiquidity(
    limitToSqrtPrice(bidLower, width),
    limitToSqrtPrice(bidUpper, width),
    quoteAmount
  )
  const baseLiquidity = baseToLiquidity(
    limitToSqrtPrice(askLower, width),
    limitToSqrtPrice(askUpper, width),
    baseAmount
  )

  console.log({
    currLimit,
    bidLower: unshiftLimit(bidLower, width),
    bidUpper: unshiftLimit(bidUpper, width),
    askLower: unshiftLimit(askLower, width),
    askUpper: unshiftLimit(askUpper, width),
    baseLiquidity: new Decimal(baseLiquidity).mul(1e18).toFixed(0, 1),
    quoteLiquidity: new Decimal(quoteLiquidity).mul(1e18).toFixed(0, 1),
  })
}

const testReplicatingStrategyUpdatePositions = () => {
  const baseAmount = "1000000"
  const quoteAmount = "1112520000"
  const width = 10
  let currLimit = Number(shiftLimit(741930, width))
  const startLimit = currLimit
  let price = 1680
  let newLimit = Number(priceToLimit(price, width))
  const maxDelta = 200
  const minSpread = 10
  const range = 20000

  // Rebalancing condition.
  if (rebalanceConditionMet(currLimit, newLimit, true, 0.003)) {
    console.log("Rebalancing")
    price = 1680
    newLimit = Number(priceToLimit(price, width))
  }

  // Deposit initial.
  const isBuy = true
  const swapFeeRate = 0.003
  const { bid, ask } = getBidAsk(maxDelta, baseAmount, quoteAmount, price, width, currLimit, newLimit, minSpread, range)

  // Execute swap.
  const swapAmount = 500000
  const netAmount = new Decimal(swapAmount).mul(1 - swapFeeRate)
  const nextSqrtPrice = nextSqrtPriceAmountIn(limitToSqrtPrice(ask.lowerLimit, width), ask.liquidity, netAmount, isBuy)
  currLimit = Number(sqrtPriceToLimit(nextSqrtPrice, width))

  console.log({
    startLimit,
    bidLower: unshiftLimit(bid.lowerLimit, width),
    bidUpper: unshiftLimit(bid.upperLimit, width),
    bidLiquidity: new Decimal(bid.liquidity).mul(1e18).toFixed(0, 1),
    askLower: unshiftLimit(ask.lowerLimit, width),
    askUpper: unshiftLimit(ask.upperLimit, width),
    askLiquidity: new Decimal(ask.liquidity).mul(1e18).toFixed(0, 1),
    nextSqrtPrice: new Decimal(nextSqrtPrice).mul(1e28).toFixed(0, 1),
    endLimit: unshiftLimit(currLimit, width),
  })
}

const testReplicatingStrategyMultipleSwaps = () => {
  const baseAmount = "1000000"
  const quoteAmount = "1112520000"
  const width = 10
  const currLimit = Number(shiftLimit(741930, width))
  const startLimit = currLimit
  let price = 1667
  let newLimit = Number(priceToLimit(price, width))
  let oraclePrice = 1632.775
  let oracleLimit = Number(priceToLimit(oraclePrice, width))
  const maxDelta = 200
  const minSpread = 10
  const range = 20000

  // Check rebalancing condition.
  let isBuy = true
  const swapFeeRate = 0.003
  if (rebalanceConditionMet(currLimit, oracleLimit, isBuy, swapFeeRate)) {
    price = 1632.775
    newLimit = Number(priceToLimit(price, width))
  }

  // Deposit initial.
  const { bid, ask } = getBidAsk(maxDelta, baseAmount, quoteAmount, price, width, currLimit, newLimit, minSpread, range)

  // Execute swap 1.
  const swapAmount = 100
  const netAmount = new Decimal(swapAmount).mul(1 - swapFeeRate)
  const nextSqrtPrice1 = nextSqrtPriceAmountIn(limitToSqrtPrice(ask.lowerLimit, width), ask.liquidity, netAmount, isBuy)
  const nextLimit1 = Number(sqrtPriceToLimit(nextSqrtPrice1, width))
  console.log("After swap 1")
  console.log({
    bidLower: unshiftLimit(bid.lowerLimit, width),
    bidUpper: unshiftLimit(bid.upperLimit, width),
    bidLiquidity: new Decimal(bid.liquidity).mul(1e18).toFixed(0, 1),
    askLower: unshiftLimit(ask.lowerLimit, width),
    askUpper: unshiftLimit(ask.upperLimit, width),
    askLiquidity: new Decimal(ask.liquidity).mul(1e18).toFixed(0, 1),
    nextSqrtPrice1: new Decimal(nextSqrtPrice1).mul(1e28).toFixed(0, 1),
    nextLimit1: unshiftLimit(nextLimit1, width),
  })
  const { amountIn, amountOut, fee } = computeSwapAmount(
    limitToSqrtPrice(ask.lowerLimit, width),
    nextSqrtPrice1,
    ask.liquidity,
    swapAmount,
    swapFeeRate,
    true
  )
  console.log({
    amountIn: new Decimal(amountIn).mul(1e18).toFixed(0, 1),
    amountOut: new Decimal(amountOut).mul(1e18).toFixed(0, 1),
    fee: new Decimal(fee).mul(1e18).toFixed(0, 1),
  })
  const baseAmount2 = new Decimal(baseAmount).sub(amountOut)
  const quoteAmount2 = new Decimal(quoteAmount).add(amountIn).add(fee)

  // Check rebalancing condition.
  isBuy = false
  if (rebalanceConditionMet(currLimit, oracleLimit, isBuy, swapFeeRate)) {
    price = 1632.775
    newLimit = Number(priceToLimit(price, width))
  }

  // Execute swap 2.
  const { bid: bid2, ask: ask2 } = getBidAsk(
    maxDelta,
    baseAmount2,
    quoteAmount2,
    price,
    width,
    nextLimit1,
    newLimit,
    minSpread,
    range
  )
  const nextSqrtPrice2 = nextSqrtPriceAmountIn(
    limitToSqrtPrice(bid2.upperLimit, width),
    bid2.liquidity,
    netAmount,
    isBuy
  )
  const endLimit = Number(sqrtPriceToLimit(nextSqrtPrice2, width))

  console.log("After swap 2")
  console.log({
    startLimit,
    baseAmount2: new Decimal(baseAmount2).mul(1e18).toFixed(0, 1),
    quoteAmount2: new Decimal(quoteAmount2).mul(1e18).toFixed(0, 1),
    bidLower: unshiftLimit(bid2.lowerLimit, width),
    bidUpper: unshiftLimit(bid2.upperLimit, width),
    bidLiquidity: new Decimal(bid2.liquidity).mul(1e18).toFixed(0, 1),
    askLower: unshiftLimit(ask2.lowerLimit, width),
    askUpper: unshiftLimit(ask2.upperLimit, width),
    askLiquidity: new Decimal(ask2.liquidity).mul(1e18).toFixed(0, 1),
    endSqrtPrice: new Decimal(nextSqrtPrice2).mul(1e28).toFixed(0, 1),
    endLimit: unshiftLimit(endLimit, width),
  })
}

const testReplicatingStrategyDeposit = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })

  const baseAmount = "1000000"
  const quoteAmount = "1112520000"
  const width = 10
  const currLimit = Number(shiftLimit(741930, width))
  const price = 1668.78
  const newLimit = Number(priceToLimit(price, width))
  const maxDelta = 200
  const minSpread = 10
  const range = 20000

  const { bidSpread, askSpread } = deltaSpread(maxDelta, baseAmount, quoteAmount, price)
  const { bidLimit: bidUpper, askLimit: askLower } = calcBidAsk(
    currLimit,
    newLimit,
    Number(bidSpread),
    Number(askSpread),
    minSpread,
    width
  )
  const bidLower = bidUpper - range
  const askUpper = askLower + range

  const bidSharesInit = quoteToLiquidity(
    limitToSqrtPrice(bidLower, width),
    limitToSqrtPrice(bidUpper, width),
    quoteAmount
  )
  const askSharesInit = baseToLiquidity(
    limitToSqrtPrice(askLower, width),
    limitToSqrtPrice(askUpper, width),
    baseAmount
  )

  const baseDeposit = "500"
  const quoteDeposit = new Decimal(baseDeposit).mul(quoteAmount).div(baseAmount)
  const bidSharesNew = new Decimal(bidSharesInit).mul(quoteDeposit).div(quoteAmount)
  const askSharesNew = new Decimal(askSharesInit).mul(baseDeposit).div(baseAmount)

  console.log({
    bidSharesInit: new Decimal(bidSharesInit).mul(1e18).toFixed(0, 1),
    askSharesInit: new Decimal(askSharesInit).mul(1e18).toFixed(0, 1),
    baseDeposit: new Decimal(baseDeposit).mul(1e18).toFixed(0, 1),
    quoteDeposit: new Decimal(quoteDeposit).mul(1e18).toFixed(0, 1),
    bidSharesNew: new Decimal(bidSharesNew).mul(1e18).toFixed(0, 1),
    askSharesNew: new Decimal(askSharesNew).mul(1e18).toFixed(0, 1),
  })
}

const testReplicatingStrategyWithdraw = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })

  const baseAmount = "1000000"
  const quoteAmount = "1112520000"
  const width = 10
  const currLimit = Number(shiftLimit(741930, width))
  const price = 1668.78
  const newLimit = Number(priceToLimit(price, width))
  const maxDelta = 200
  const minSpread = 10
  const range = 20000

  const { bidSpread, askSpread } = deltaSpread(maxDelta, baseAmount, quoteAmount, price)
  const { bidLimit: bidUpper, askLimit: askLower } = calcBidAsk(
    currLimit,
    newLimit,
    Number(bidSpread),
    Number(askSpread),
    minSpread,
    width
  )
  const bidLower = bidUpper - range
  const askUpper = askLower + range
  const bidLiquidity = quoteToLiquidity(
    limitToSqrtPrice(bidLower, width),
    limitToSqrtPrice(bidUpper, width),
    quoteAmount
  )
  const askLiquidity = baseToLiquidity(limitToSqrtPrice(askLower, width), limitToSqrtPrice(askUpper, width), baseAmount)
  const shares = bidLiquidity.add(askLiquidity)

  // Calculate next price.
  const swapAmount = 5000
  const swapFeeRate = 0.003
  let isBuy = false
  const netAmount = new Decimal(swapAmount).mul(1 - swapFeeRate)
  const nextSqrtPrice = nextSqrtPriceAmountIn(limitToSqrtPrice(bidUpper, width), bidLiquidity, netAmount, isBuy)

  // Calculate swap amounts.
  const { amountIn, amountOut, fee } = computeSwapAmount(
    limitToSqrtPrice(bidUpper, width),
    nextSqrtPrice,
    bidLiquidity,
    swapAmount,
    swapFeeRate,
    true
  )
  const baseAmountEnd = new Decimal(baseAmount).add(amountIn)
  const quoteAmountEnd = new Decimal(quoteAmount).sub(amountOut)

  const sharesWithdraw = new Decimal(bidLiquidity).add(askLiquidity).div(2)
  const baseWithdraw = new Decimal(sharesWithdraw).mul(baseAmountEnd).div(shares)
  const quoteWithdraw = new Decimal(sharesWithdraw).mul(quoteAmountEnd).div(shares)

  // The remaining share of collected fees will be leftover as reserves.
  const baseReserves = new Decimal(fee).div(2)

  console.log({
    bidSharesInit: new Decimal(bidLiquidity).mul(1e18).toFixed(0, 1),
    askSharesInit: new Decimal(askLiquidity).mul(1e18).toFixed(0, 1),
    amountIn: new Decimal(amountIn).mul(1e18).toFixed(0, 1),
    amountOut: new Decimal(amountOut).mul(1e18).toFixed(0, 1),
    fee: new Decimal(fee).mul(1e18).toFixed(0, 1),
    baseWithdraw: new Decimal(baseWithdraw).mul(1e18).toFixed(0, 1),
    quoteWithdraw: new Decimal(quoteWithdraw).mul(1e18).toFixed(0, 1),
    baseReserves: new Decimal(baseReserves).mul(1e18).toFixed(0, 1),
  })
}

// testReplicatingStrategyDepositInitial()
// testReplicatingStrategyUpdatePositions()
// testReplicatingStrategyMultipleSwaps()
// testReplicatingStrategyDeposit()
testReplicatingStrategyWithdraw()
