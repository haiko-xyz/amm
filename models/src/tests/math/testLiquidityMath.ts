import { limitToSqrtPrice, shiftLimit } from "../../math/priceMath"
import { liquidityToBase } from "../../math/liquidityMath"
import Decimal from "decimal.js"
import { PRECISION, ROUNDING } from "../../config"

// Setup rng
import seedrandom from "seedrandom"
const rng = seedrandom("88888")

const generateValue = (max: Decimal.Value) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  return new Decimal(rng()).mul(max).div(1e28).toFixed()
}

const generateU256 = () => {
  const u256Max = new Decimal(2).pow(256)
  return generateValue(u256Max)
}

const generateLiquidityToBaseCase = () => {
  // Generate random liquidity amount and sqrt prices.
  const sqrtPrice1 = generateValue("2698233297579882119236696658671080366")
  const sqrtPrice2 = generateValue("2698233297579882119236696658671080366")
  const liquidity = generateU256()

  // Calculate base amount.
  const lowerSqrtPrice = Decimal.min(sqrtPrice1, sqrtPrice2)
  const upperSqrtPrice = Decimal.max(sqrtPrice1, sqrtPrice2)
  const base = liquidityToBase(lowerSqrtPrice, upperSqrtPrice, liquidity)

  // Convert to X28 amounts.
  const lowerSqrtPriceFmt = new Decimal(lowerSqrtPrice).mul(1e28).toDP(28, 1)

  return { liquidity, lowerSqrtPrice, upperSqrtPrice, base }
}

const testLiquidityToBaseFuzzCases = () => {
  for (let i = 0; i < 10; i++) {
    const { liquidity, lowerSqrtPrice, upperSqrtPrice, base } = generateLiquidityToBaseCase()
    console.log({ liquidity, lowerSqrtPrice, upperSqrtPrice, base })
  }
}

testLiquidityToBaseFuzzCases()
