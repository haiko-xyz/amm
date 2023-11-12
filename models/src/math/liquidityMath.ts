import { Decimal } from "decimal.js"
import { limitToSqrtPrice } from "./priceMath"
import { PRECISION, ROUNDING } from "../config"

export const addDelta = (liquidity: Decimal.Value, delta: Decimal.Value) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const liquidityDec = new Decimal(liquidity)
  return liquidityDec.add(delta).toFixed()
}

export const liquidityToQuote = (
  lowerSqrtPrice: Decimal.Value,
  upperSqrtPrice: Decimal.Value,
  liquidityDelta: Decimal.Value
) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const upperSqrtPriceDec = new Decimal(upperSqrtPrice)
  const liquidityDeltaDec = new Decimal(liquidityDelta)
  return liquidityDeltaDec.mul(upperSqrtPriceDec.sub(lowerSqrtPrice))
}

export const liquidityToBase = (
  lowerSqrtPrice: Decimal.Value,
  upperSqrtPrice: Decimal.Value,
  liquidityDelta: Decimal.Value
) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const upperSqrtPriceDec = new Decimal(upperSqrtPrice)
  const liquidityDeltaDec = new Decimal(liquidityDelta)
  return liquidityDeltaDec.mul(upperSqrtPriceDec.sub(lowerSqrtPrice)).div(upperSqrtPriceDec.mul(lowerSqrtPrice))
}

export const quoteToLiquidity = (
  lowerSqrtPrice: Decimal.Value,
  upperSqrtPrice: Decimal.Value,
  quoteAmount: Decimal.Value
) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const upperSqrtPriceDec = new Decimal(upperSqrtPrice)
  const quoteAmountDec = new Decimal(quoteAmount)
  return quoteAmountDec.div(upperSqrtPriceDec.sub(lowerSqrtPrice))
}

export const baseToLiquidity = (
  lowerSqrtPrice: Decimal.Value,
  upperSqrtPrice: Decimal.Value,
  baseAmount: Decimal.Value
) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const lowerSqrtPriceBN = new Decimal(lowerSqrtPrice)
  const upperSqrtPriceBN = new Decimal(upperSqrtPrice)
  const baseAmountDec = new Decimal(baseAmount)
  const liquidity = baseAmountDec
    .mul(upperSqrtPriceBN.mul(lowerSqrtPriceBN))
    .div(upperSqrtPriceBN.sub(lowerSqrtPriceBN))
  return liquidity
}

export type TokenAmounts = {
  baseAmount: string
  quoteAmount: string
}

export const liquidityToAmounts = (
  currLimit: Decimal.Value,
  currSqrtPrice: Decimal.Value,
  liquidityDelta: Decimal.Value,
  lowerLimit: Decimal.Value,
  upperLimit: Decimal.Value,
  width: Decimal.Value
): TokenAmounts => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  let upperLimitDec = new Decimal(upperLimit)
  let lowerLimitDec = new Decimal(lowerLimit)

  if (upperLimitDec.lte(currLimit)) {
    return {
      baseAmount: "0",
      quoteAmount: liquidityToQuote(
        limitToSqrtPrice(lowerLimit, width),
        limitToSqrtPrice(upperLimit, width),
        liquidityDelta
      ).toFixed(),
    }
  } else if (lowerLimitDec.lte(currLimit)) {
    return {
      baseAmount: liquidityToBase(currSqrtPrice, limitToSqrtPrice(upperLimit, width), liquidityDelta).toFixed(),
      quoteAmount: liquidityToQuote(limitToSqrtPrice(lowerLimit, width), currSqrtPrice, liquidityDelta).toFixed(),
    }
  } else {
    return {
      baseAmount: liquidityToBase(
        limitToSqrtPrice(lowerLimit, width),
        limitToSqrtPrice(upperLimit, width),
        liquidityDelta
      ).toFixed(),
      quoteAmount: "0",
    }
  }
}
