import Decimal from "decimal.js"
import { PRECISION, ROUNDING } from "../config"
import { MAX, MAX_NUM_LIMITS } from "../constants"

export const maxLiquidityPerLimit = (width: Decimal.Value) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const maxNumLimits = new Decimal(MAX_NUM_LIMITS)
  const maxBN = new Decimal(MAX)
  return maxBN.div(maxNumLimits.div(width).toDP(0, 0))
}
