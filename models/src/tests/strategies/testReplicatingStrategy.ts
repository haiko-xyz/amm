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
  let askSpread = minSpread + askDelta
  let rawBidLimit = bidSpread > newLimit || currLimit < width ? 0 : Math.min(currLimit, newLimit - bidSpread)
  let rawAskLimit = Math.min(Math.max(newLimit + width + askSpread, currLimit + width), Number(maxLimit(width)))

  let bidLimit = rawBidLimit - (rawBidLimit % width)
  let askLimit = rawAskLimit - (rawAskLimit % width) + width

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
  let price = 1672.5
  const newLimit = Number(priceToLimit(price, width))
  const maxDelta = 200
  const minSpread = 10
  const range = 20000

  // Deposit initial.
  const { bid, ask } = getBidAsk(maxDelta, baseAmount, quoteAmount, price, width, currLimit, newLimit, minSpread, range)

  // Execute swap.
  const swapAmount = 500000
  const swapFeeRate = 0.003
  const isBuy = true
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

// testReplicatingStrategyDepositInitial()
testReplicatingStrategyUpdatePositions()
