import Decimal from "decimal.js"

export const nextSqrtPriceAmountIn = (
  currSqrtPrice: Decimal.Value,
  liquidity: Decimal.Value,
  amountIn: Decimal.Value,
  isBuy: boolean
) => {
  Decimal.set({ precision: 76, rounding: 1 })
  const currSqrtPriceBN = new Decimal(currSqrtPrice)
  const liquidityBN = new Decimal(liquidity)
  const amountInBN = new Decimal(amountIn)
  const nextSqrtPrice = isBuy
    ? currSqrtPriceBN.add(amountInBN.div(liquidityBN))
    : liquidityBN.mul(currSqrtPriceBN).div(liquidityBN.add(amountInBN.mul(currSqrtPriceBN)))
  return nextSqrtPrice
}

export const nextSqrtPriceAmountOut = (
  currSqrtPrice: Decimal.Value,
  liquidity: Decimal.Value,
  amountOut: Decimal.Value,
  isBuy: boolean
) => {
  Decimal.set({ precision: 76, rounding: 1 })
  const currSqrtPriceBN = new Decimal(currSqrtPrice)
  const liquidityBN = new Decimal(liquidity)
  const amountOutBN = new Decimal(amountOut)
  const nextSqrtPrice = isBuy
    ? liquidityBN.mul(currSqrtPriceBN).div(liquidityBN.sub(amountOutBN.mul(currSqrtPriceBN)))
    : currSqrtPriceBN.sub(amountOutBN.div(liquidityBN))
  return nextSqrtPrice
}
