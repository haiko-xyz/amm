import Decimal from "decimal.js"
import { PRECISION, ROUNDING } from "../config"
import { MAX_UNSCALED, MAX_NUM_LIMITS } from "../constants"

export const maxLiquidityPerLimit = (width: Decimal.Value) => {
  Decimal.set({ precision: PRECISION, rounding: ROUNDING })
  const maxNumLimits = new Decimal(MAX_NUM_LIMITS)
  const maxUnscaledBN = new Decimal(MAX_UNSCALED)
  return maxUnscaledBN.div(maxNumLimits.div(width).ceil())
}
