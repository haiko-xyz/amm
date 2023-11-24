import Decimal from "decimal.js"
import { PRECISION, ROUNDING } from "../config"
import { MAX_NUM_LIMITS, MAX_SCALED } from "../constants"

export const maxLiquidityPerLimit = (width: Decimal.Value) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const maxNumLimits = new Decimal(MAX_NUM_LIMITS)
  const max = new Decimal(MAX_SCALED)
  return max.div(maxNumLimits.div(width).ceil())
}
