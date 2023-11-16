import Decimal from "decimal.js"
import { PRECISION, ROUNDING } from "../../config"
import { computeSwapAmount, nextSqrtPriceAmountIn, nextSqrtPriceAmountOut } from "../../libraries/swap"
import { limitToSqrtPrice, offset, shiftLimit } from "../../math/priceMath"
import { MAX, MAX_WHOLE, OFFSET } from "../../constants"
import { calcFee } from "../../math/feeMath"

type SwapCase = {
  isBuy: boolean
  exactInput: boolean
  amount: number | string
  thresholdSqrtPrice?: number | string
}

// Swap cases.
const swapCases: SwapCase[] = [
  {
    isBuy: false,
    exactInput: true,
    amount: 1,
    thresholdSqrtPrice: undefined,
  },
  // {
  //   isBuy: true,
  //   exactInput: true,
  //   amount: 1,
  //   thresholdSqrtPrice: undefined,
  // },
  // {
  //   isBuy: false,
  //   exactInput: false,
  //   amount: 1,
  //   thresholdSqrtPrice: undefined,
  // },
  // {
  //   isBuy: true,
  //   exactInput: false,
  //   amount: 1,
  //   thresholdSqrtPrice: undefined,
  // },
  // {
  //   isBuy: false,
  //   exactInput: true,
  //   amount: 1,
  //   thresholdSqrtPrice: new Decimal(50).div(100).sqrt(),
  // },
  // {
  //   isBuy: true,
  //   exactInput: true,
  //   amount: 1,
  //   thresholdSqrtPrice: new Decimal(200).div(100).sqrt(),
  // },
  // {
  //   isBuy: false,
  //   exactInput: false,
  //   amount: 1,
  //   thresholdSqrtPrice: new Decimal(50).div(100).sqrt(),
  // },
  // {
  //   isBuy: true,
  //   exactInput: false,
  //   amount: 1,
  //   thresholdSqrtPrice: new Decimal(200).div(100).sqrt(),
  // },
  // {
  //   isBuy: false,
  //   exactInput: true,
  //   amount: "0.000000000000100000",
  //   thresholdSqrtPrice: undefined,
  // },
  // {
  //   isBuy: true,
  //   exactInput: true,
  //   amount: "0.000000000000100000",
  //   thresholdSqrtPrice: undefined,
  // },
  // {
  //   isBuy: false,
  //   exactInput: false,
  //   amount: "0.000000000000100000",
  //   thresholdSqrtPrice: undefined,
  // },
  // {
  //   isBuy: true,
  //   exactInput: false,
  //   amount: "0.000000000000100000",
  //   thresholdSqrtPrice: undefined,
  // },
  // {
  //   isBuy: true,
  //   exactInput: true,
  //   amount: "36185027886661312136973227830.95070105526743751716087489154079457884512865583",
  //   thresholdSqrtPrice: new Decimal(5).div(2).sqrt(),
  // },
  // {
  //   isBuy: false,
  //   exactInput: true,
  //   amount: "36185027886661312136973227830.95070105526743751716087489154079457884512865583",
  //   thresholdSqrtPrice: new Decimal(2).div(5).sqrt(),
  // },
  // {
  //   isBuy: true,
  //   exactInput: false,
  //   amount: "36185027886661312136973227830.95070105526743751716087489154079457884512865583",
  //   thresholdSqrtPrice: new Decimal(5).div(2).sqrt(),
  // },
  // {
  //   isBuy: false,
  //   exactInput: false,
  //   amount: "36185027886661312136973227830.95070105526743751716087489154079457884512865583",
  //   thresholdSqrtPrice: new Decimal(2).div(5).sqrt(),
  // },
]

const marketCases = [
  {
    swapFeeRate: 0.0005,
    width: 1,
    startLimit: OFFSET + 0,
    startLiquidity: "20000000000",
  },
  {
    swapFeeRate: 0.0025,
    width: 10,
    startLimit: shiftLimit(0, 10),
    startLiquidity: "20000000000",
  },
  {
    swapFeeRate: 0.01,
    width: 100,
    startLimit: shiftLimit(0, 100),
    startLiquidity: "20000000000",
  },
  {
    swapFeeRate: 0.0025,
    width: 10,
    startLimit: shiftLimit(230260, 10),
    startLiquidity: "200000000000",
  },
  {
    swapFeeRate: 0.0025,
    width: 10,
    startLimit: shiftLimit(-230260, 10),
    startLiquidity: "200000000000",
  },
]

const testMarketCase = () => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })

  let marketCounter = 1
  for (const { swapFeeRate, width, startLimit, startLiquidity } of marketCases) {
    let swapCounter = 1

    for (const { isBuy, exactInput, amount, thresholdSqrtPrice } of swapCases) {
      // Find price reached.
      const netAmount = new Decimal(amount).mul(1 - swapFeeRate)
      const nextSqrtPrice = exactInput
        ? nextSqrtPriceAmountIn(limitToSqrtPrice(startLimit, width), startLiquidity, netAmount, isBuy)
        : nextSqrtPriceAmountOut(limitToSqrtPrice(startLimit, width), startLiquidity, amount, isBuy)
      const cappedNextSqrtPrice = thresholdSqrtPrice
        ? isBuy
          ? Decimal.min(nextSqrtPrice, thresholdSqrtPrice)
          : Decimal.max(nextSqrtPrice, thresholdSqrtPrice)
        : nextSqrtPrice

      console.log({ startSqrtPrice: limitToSqrtPrice(startLimit, width), startLiquidity, netAmount })

      // Calculate swap amounts.
      const currSqrtPrice = limitToSqrtPrice(startLimit, width)
      const { amountIn, amountOut, fee } = computeSwapAmount(
        currSqrtPrice,
        cappedNextSqrtPrice,
        startLiquidity,
        amount,
        swapFeeRate,
        exactInput
      )
      const grossAmountIn = new Decimal(amountIn).add(fee)

      if (
        (thresholdSqrtPrice &&
          (isBuy
            ? new Decimal(thresholdSqrtPrice).lt(currSqrtPrice)
            : new Decimal(thresholdSqrtPrice).gt(currSqrtPrice))) ||
        String(amountIn).startsWith("-")
      ) {
        console.log(`Market ${marketCounter}: Case ${swapCounter} (skipped)`)
      } else {
        console.log(`Market ${marketCounter}: Case ${swapCounter}`)
      }
      console.log({
        amountIn: new Decimal(grossAmountIn).mul(1e18).toFixed(0, 1),
        amountOut: new Decimal(amountOut).mul(1e18).toFixed(0, 1),
        fee: new Decimal(fee).mul(1e18).toFixed(0, 1),
        cappedNextSqrtPrice,
      })
      swapCounter += 1
    }
    marketCounter += 1
  }
}

testMarketCase()
