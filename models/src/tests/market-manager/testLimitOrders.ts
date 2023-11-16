import Decimal from "decimal.js"
import { OFFSET } from "../../constants"
import { MarketManager } from "../../contracts/marketManager"
import { computeSwapAmount, nextSqrtPriceAmountIn } from "../../libraries/swap"
import { limitToSqrtPrice } from "../../math/priceMath"
import { calcFee, netToGross } from "../../math/feeMath"
import { PRECISION, ROUNDING } from "../../config"
import { liquidityToBase, liquidityToQuote } from "../../math/liquidityMath"

const before = () => {
  const width = 1
  const currLimit = OFFSET - 0
  const swapFeeRate = 0.003
  const protocolShare = 0.002
  const marketManager = new MarketManager(width, currLimit, swapFeeRate, protocolShare)
  return marketManager
}

const testCreateMultipleBidOrders = () => {
  const marketManager = before()

  // Create first limit order.
  const { baseAmount: baseAmount1, quoteAmount: quoteAmount1 } = marketManager.modifyPosition(
    OFFSET - 1000,
    OFFSET - 999,
    "1"
  )
  console.log({
    baseAmount: new Decimal(baseAmount1).mul(1e18).toFixed(0, 1),
    quoteAmount: new Decimal(quoteAmount1).mul(1e28).toFixed(0, 1),
  })

  // Create second limit order.
  const { baseAmount: baseAmount2, quoteAmount: quoteAmount2 } = marketManager.modifyPosition(
    OFFSET - 1000,
    OFFSET - 999,
    "2"
  )
  console.log({
    baseAmount: new Decimal(baseAmount2).mul(1e28).toFixed(0, 1),
    quoteAmount: new Decimal(quoteAmount2).mul(1e28).toFixed(0, 1),
  })
}
const testCreateMultipleAskOrders = () => {
  const marketManager = before()

  // Create first limit order.
  const { baseAmount: baseAmount1, quoteAmount: quoteAmount1 } = marketManager.modifyPosition(
    OFFSET + 1000,
    OFFSET + 1001,
    "1"
  )
  console.log({
    baseAmount: new Decimal(baseAmount1).mul(1e28).toFixed(0, 1),
    quoteAmount: new Decimal(quoteAmount1).mul(1e28).toFixed(0, 1),
  })

  // Create second limit order.
  const { baseAmount: baseAmount2, quoteAmount: quoteAmount2 } = marketManager.modifyPosition(
    OFFSET + 1000,
    OFFSET + 1001,
    "2"
  )
  console.log({
    baseAmount: new Decimal(baseAmount2).mul(1e28).toFixed(0, 1),
    quoteAmount: new Decimal(quoteAmount2).mul(1e28).toFixed(0, 1),
  })
}

const testSwapFullyFillsBidLimitOrders = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const { amountIn, amountOut, fee } = computeSwapAmount(
    limitToSqrtPrice(OFFSET - 999, 1),
    limitToSqrtPrice(OFFSET - 1000, 1),
    "1500000",
    "10",
    0.003,
    true
  )
  const protocolShare = 0.002
  const protocolFee = calcFee(fee, protocolShare)
  const grossAmountIn = new Decimal(amountIn).add(fee).sub(protocolFee)

  console.log({
    amountIn: new Decimal(grossAmountIn).mul(1e28).toFixed(0, 1),
    amountOut: new Decimal(amountOut).mul(1e28).toFixed(0, 1),
    fee: new Decimal(fee).mul(1e28).toFixed(0, 1),
  })
}

const testSwapFullyFillsAskLimitOrders = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const { amountIn, amountOut, fee } = computeSwapAmount(
    limitToSqrtPrice(OFFSET + 1000, 1),
    limitToSqrtPrice(OFFSET + 1001, 1),
    "1500000",
    "10",
    0.003,
    true
  )
  const protocolShare = 0.002
  const protocolFee = calcFee(fee, protocolShare)
  const grossAmountIn = new Decimal(amountIn).add(fee).sub(protocolFee)

  console.log({
    amountIn: new Decimal(grossAmountIn).mul(1e28).toFixed(0, 1),
    amountOut: new Decimal(amountOut).mul(1e28).toFixed(0, 1),
    fee: new Decimal(fee).mul(1e28).toFixed(0, 1),
  })
}

const testCreateAndCollectUnfilledBidOrder = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const amountIn = liquidityToQuote(limitToSqrtPrice(OFFSET - 1000, 1), limitToSqrtPrice(OFFSET - 999, 1), "1000000")

  console.log({
    amountIn: new Decimal(amountIn).mul(1e28).toFixed(0, 1),
  })
}
const testCreateAndCollectUnfilledAskOrder = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const amountIn = liquidityToBase(limitToSqrtPrice(OFFSET + 1000, 1), limitToSqrtPrice(OFFSET + 1001, 1), "1000000")

  console.log({
    amountIn: new Decimal(amountIn).mul(1e28).toFixed(0, 1),
  })
}

const testCreateAndCollectFullyFilledBidOrder = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const { amountIn, amountOut, fee } = computeSwapAmount(
    limitToSqrtPrice(OFFSET - 999, 1),
    limitToSqrtPrice(OFFSET - 1000, 1),
    "1000000",
    "10",
    0.003,
    true
  )
  const protocolShare = 0.002
  const protocolFee = calcFee(fee, protocolShare)
  const grossAmountIn = new Decimal(amountIn).add(fee).sub(protocolFee)

  console.log({
    amountIn: new Decimal(grossAmountIn).mul(1e28).toFixed(0, 1),
    amountOut: new Decimal(amountOut).mul(1e28).toFixed(0, 1),
    fee: new Decimal(fee).mul(1e28).toFixed(0, 1),
  })
}

const testCreateAndCollectFullyFilledAskOrder = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const { amountIn, amountOut, fee } = computeSwapAmount(
    limitToSqrtPrice(OFFSET + 1000, 1),
    limitToSqrtPrice(OFFSET + 1001, 1),
    "1000000",
    "10",
    0.003,
    true
  )
  const protocolShare = 0.002
  const protocolFee = calcFee(fee, protocolShare)
  const grossAmountIn = new Decimal(amountIn).add(fee).sub(protocolFee)

  console.log({
    amountIn: new Decimal(grossAmountIn).mul(1e28).toFixed(0, 1),
    amountOut: new Decimal(amountOut).mul(1e28).toFixed(0, 1),
    fee: new Decimal(fee).mul(1e28).toFixed(0, 1),
  })
}

const testCreateAndCollectPartiallyFilledBidOrder = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })

  // Order amount.
  const quoteAmount = liquidityToQuote(limitToSqrtPrice(OFFSET - 1000, 1), limitToSqrtPrice(OFFSET - 999, 1), "1500000")

  // Find price reached.
  const netAmount = new Decimal(6).mul(1 - 0.003)
  const nextSqrtPrice = nextSqrtPriceAmountIn(limitToSqrtPrice(OFFSET - 999, 1), "500000", netAmount, false)

  const { amountIn, amountOut, fee } = computeSwapAmount(
    limitToSqrtPrice(OFFSET - 999, 1),
    nextSqrtPrice,
    "1500000",
    "6",
    0.003,
    true
  )
  const protocolShare = 0.002
  const protocolFee = calcFee(fee, protocolShare)
  const grossAmountIn = new Decimal(amountIn).add(fee).sub(protocolFee)

  console.log({
    quoteAmount: new Decimal(quoteAmount).mul(1e28).mul(2).div(3).toFixed(0, 1),
    amountIn: new Decimal(grossAmountIn).mul(1e28).mul(2).div(3).toFixed(0, 1),
    amountOut: new Decimal(amountOut).mul(1e28).mul(2).div(3).toFixed(0, 1),
    fee: new Decimal(fee).mul(1e28).mul(2).div(3).toFixed(0, 1),
  })
}

const testCreateAndCollectPartiallyFilledAskOrder = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })

  // Order amount.
  const baseAmount = liquidityToBase(limitToSqrtPrice(OFFSET + 1000, 1), limitToSqrtPrice(OFFSET + 1001, 1), "1500000")

  // Find price reached.
  const netAmount = new Decimal(6).mul(1 - 0.003)
  const nextSqrtPrice = nextSqrtPriceAmountIn(limitToSqrtPrice(OFFSET + 1000, 1), "1500000", netAmount, true)

  const { amountIn, amountOut, fee } = computeSwapAmount(
    limitToSqrtPrice(OFFSET + 1000, 1),
    nextSqrtPrice,
    "1500000",
    "6",
    0.003,
    true
  )
  const protocolShare = 0.002
  const protocolFee = calcFee(fee, protocolShare)
  const grossAmountIn = new Decimal(amountIn).add(fee).sub(protocolFee)

  console.log({
    baseAmount: new Decimal(baseAmount).mul(1e28).mul(2).div(3).toFixed(0, 1),
    amountIn: new Decimal(grossAmountIn).mul(1e28).mul(2).div(3).toFixed(0, 1),
    amountOut: new Decimal(amountOut).mul(1e28).mul(2).div(3).toFixed(0, 1),
    fee: new Decimal(fee).mul(1e28).mul(2).div(3).toFixed(0, 1),
  })
}

const testPartiallyFilledBidCorrectlyUnfills = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })

  // Order amount.
  const quoteAmount = liquidityToQuote(limitToSqrtPrice(OFFSET - 1000, 1), limitToSqrtPrice(OFFSET - 999, 1), "1500000")

  // Find price reached after swap 1 (sell)
  let netAmount = new Decimal(6).mul(1 - 0.003)
  const nextSqrtPrice = nextSqrtPriceAmountIn(limitToSqrtPrice(OFFSET - 999, 1), "1500000", netAmount, false)

  const { amountIn, amountOut, fee } = computeSwapAmount(
    limitToSqrtPrice(OFFSET - 999, 1),
    nextSqrtPrice,
    "1500000",
    "6",
    0.003,
    true
  )
  const protocolShare = 0.002
  const protocolFee = calcFee(fee, protocolShare)
  const grossAmountIn = new Decimal(amountIn).add(fee).sub(protocolFee)

  console.log("Swap 1 (sell)")
  console.log({
    quoteAmount: new Decimal(quoteAmount).mul(1e28).toFixed(0, 1),
    amountIn: new Decimal(grossAmountIn).mul(1e28).toFixed(0, 1),
    amountOut: new Decimal(amountOut).mul(1e28).toFixed(0, 1),
    fee: new Decimal(fee).mul(1e28).toFixed(0, 1),
  })

  // Find price reached after swap 2 (buy)
  netAmount = new Decimal(4).mul(1 - 0.003)
  const nextSqrtPrice2 = nextSqrtPriceAmountIn(nextSqrtPrice, "1500000", netAmount, true)

  const {
    amountIn: amountIn2,
    amountOut: amountOut2,
    fee: fee2,
  } = computeSwapAmount(nextSqrtPrice, nextSqrtPrice2, "1500000", "4", 0.003, true)

  const protocolFee2 = calcFee(fee2, protocolShare)
  const grossAmountIn2 = new Decimal(amountIn2).add(fee2).sub(protocolFee2)

  console.log("Swap 2 (buy)")
  console.log({
    amountIn: new Decimal(grossAmountIn2).mul(1e28).toFixed(0, 1),
    amountOut: new Decimal(amountOut2).mul(1e28).toFixed(0, 1),
    fee: new Decimal(fee2).mul(1e28).toFixed(0, 1),
  })
}

const testPartiallyFilledAskCorrectlyUnfills = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })

  // Order amount.
  const baseAmount = liquidityToBase(limitToSqrtPrice(OFFSET + 1000, 1), limitToSqrtPrice(OFFSET + 1001, 1), "1500000")

  // Find price reached after swap 1 (buy)
  let netAmount = new Decimal(6).mul(1 - 0.003)
  const nextSqrtPrice = nextSqrtPriceAmountIn(limitToSqrtPrice(OFFSET + 1000, 1), "1500000", netAmount, true)

  const { amountIn, amountOut, fee } = computeSwapAmount(
    limitToSqrtPrice(OFFSET + 1000, 1),
    nextSqrtPrice,
    "1500000",
    "6",
    0.003,
    true
  )
  const protocolShare = 0.002
  const protocolFee = calcFee(fee, protocolShare)
  const grossAmountIn = new Decimal(amountIn).add(fee).sub(protocolFee)

  console.log("Swap 1 (buy)")
  console.log({
    baseAmount: new Decimal(baseAmount).mul(1e28).toFixed(0, 1),
    amountIn: new Decimal(grossAmountIn).mul(1e28).toFixed(0, 1),
    amountOut: new Decimal(amountOut).mul(1e28).toFixed(0, 1),
    fee: new Decimal(fee).mul(1e28).toFixed(0, 1),
  })

  // Find price reached after swap 2 (sell)
  netAmount = new Decimal(4).mul(1 - 0.003)
  const nextSqrtPrice2 = nextSqrtPriceAmountIn(nextSqrtPrice, "1500000", netAmount, false)

  const {
    amountIn: amountIn2,
    amountOut: amountOut2,
    fee: fee2,
  } = computeSwapAmount(nextSqrtPrice, nextSqrtPrice2, "1500000", "4", 0.003, true)

  const protocolFee2 = calcFee(fee2, protocolShare)
  const grossAmountIn2 = new Decimal(amountIn2).add(fee2).sub(protocolFee2)

  console.log("Swap 2 (sell)")
  console.log({
    amountIn: new Decimal(grossAmountIn2).mul(1e28).toFixed(0, 1),
    amountOut: new Decimal(amountOut2).mul(1e28).toFixed(0, 1),
    fee: new Decimal(fee2).mul(1e28).toFixed(0, 1),
  })
}

const testLimitOrdersMiscActions = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })

  // Swap 1: sell to fill both bid orders at -900 and partially fill one at -1000.
  // Swap leg 1a: swap from -900 to -899
  const {
    amountIn: amountIn1a,
    amountOut: amountOut1a,
    fee: fee1a,
  } = computeSwapAmount(
    limitToSqrtPrice(OFFSET - 899, 1),
    limitToSqrtPrice(OFFSET - 900, 1),
    "150000",
    "1",
    0.003,
    true
  )
  const grossAmountIn1a = new Decimal(amountIn1a).add(fee1a)
  const protocolFee1a = calcFee(fee1a, 0.002)
  const grossAmountInLessPFee1a = grossAmountIn1a.sub(protocolFee1a)

  // Swap leg 1b: swap from -999 to -1000
  const netAmount = new Decimal(1).sub(grossAmountIn1a).mul(1 - 0.003)
  const nextSqrtPrice1b = nextSqrtPriceAmountIn(limitToSqrtPrice(OFFSET - 999, 1), "200000", netAmount, false)

  const {
    amountIn: amountIn1b,
    amountOut: amountOut1b,
    fee: fee1b,
  } = computeSwapAmount(
    limitToSqrtPrice(OFFSET - 999, 1),
    nextSqrtPrice1b,
    "200000",
    new Decimal(1).sub(grossAmountIn1a),
    0.003,
    true
  )

  console.log({ amountIn1b, amountOut1b, fee1b })

  const protocolFee1b = calcFee(fee1b, 0.002)
  const grossAmountIn1b = new Decimal(amountIn1b).add(fee1b)
  const grossAmountInLessPFee1b = grossAmountIn1b.sub(protocolFee1b)

  const grossAmountIn1 = new Decimal(grossAmountIn1a).add(grossAmountIn1b)
  const amountOut1 = new Decimal(amountOut1a).add(amountOut1b)
  const fee1 = new Decimal(fee1a).add(fee1b)
  const baseFeeFactor = new Decimal(fee1a)
    .sub(protocolFee1a)
    .div(150000)
    .add(new Decimal(fee1b).sub(protocolFee1b).div(200000))

  const batchNeg1000Quote = liquidityToQuote(
    limitToSqrtPrice(OFFSET - 1000, 1),
    limitToSqrtPrice(OFFSET - 999, 1),
    "200000"
  ).sub(amountOut1b)

  console.log({
    amountIn: new Decimal(grossAmountIn1).mul(1e28).toFixed(0, 1),
    amountOut: new Decimal(amountOut1).mul(1e28).toFixed(0, 1),
    fee: new Decimal(fee1).mul(1e28).toFixed(0, 1),
    baseCollect1a: grossAmountInLessPFee1a.mul(1e28).mul(1).div(3).toFixed(0, 1),
    currSqrtPrice1b: nextSqrtPrice1b.mul(1e28).toFixed(0, 1),
    baseFeeFactor: baseFeeFactor.mul(1e28).toFixed(0, 1),
    batchNeg900Base: grossAmountInLessPFee1a.mul(1e28).mul(2).div(3).toFixed(0, 1),
    batchNeg1000Quote: batchNeg1000Quote.mul(1e28).toFixed(0, 1),
    batchNeg1000Base: grossAmountInLessPFee1b.mul(1e28).toFixed(0, 1),
  })
}

// testCreateMultipleBidOrders()
// testCreateMultipleAskOrders()
// testSwapFullyFillsBidLimitOrders()
// testSwapFullyFillsAskLimitOrders()
// testCreateAndCollectUnfilledBidOrder()
// testCreateAndCollectUnfilledAskOrder()
// testCreateAndCollectFullyFilledBidOrder()
// testCreateAndCollectFullyFilledAskOrder()
// testCreateAndCollectPartiallyFilledBidOrder()
// testCreateAndCollectPartiallyFilledAskOrder()
// testPartiallyFilledBidCorrectlyUnfills()
// testPartiallyFilledAskCorrectlyUnfills()
testLimitOrdersMiscActions()
