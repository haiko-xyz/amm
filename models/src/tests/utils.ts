import Decimal from "decimal.js"

export const round = (x: Decimal.Value, roundUp: boolean = false) => {
  return new Decimal(x).toDP(0, roundUp ? 0 : 1).toFixed()
}
