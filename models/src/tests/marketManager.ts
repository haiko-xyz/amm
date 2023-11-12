import Decimal from "decimal.js"
import { addDelta, liquidityToAmounts, liquidityToBase, liquidityToQuote } from "../math/liquidityMath"
import { getFeeInside } from "../math/feeMath"
import { limitToSqrtPrice } from "../math/priceMath"
import { nextSqrtPriceAmountIn, nextSqrtPriceAmountOut } from "../libraries/swap"

type Position = {
  lowerLimit: number
  upperLimit: number
  liquidity: Decimal.Value
  baseFeeFactorLast: Decimal.Value
  quoteFeeFactorLast: Decimal.Value
}

type LimitInfo = {
  liquidity: Decimal.Value
  liquidityDelta: Decimal.Value
  baseFeeFactor: Decimal.Value
  quoteFeeFactor: Decimal.Value
  initialised: boolean
}

class MarketManager {
  width: Decimal.Value
  liquidity: Decimal.Value
  currLimit: number
  currSqrtPrice: Decimal.Value
  swapFeeRate: number
  protocolShare: Decimal.Value
  baseFeeFactor: Decimal.Value
  quoteFeeFactor: Decimal.Value
  positions: Map<string, Position>
  limitInfos: Map<number, LimitInfo>
  bitmap: Map<number, boolean>

  constructor() {
    this.width = 0
    this.liquidity = "0"
    this.currLimit = 0
    this.currSqrtPrice = "0"
    this.swapFeeRate = 0
    this.protocolShare = 0
    this.baseFeeFactor = "0"
    this.quoteFeeFactor = "0"
    this.positions = new Map()
    this.limitInfos = new Map()
    this.bitmap = new Map()
  }

  modifyPosition(
    lowerLimit: number,
    upperLimit: number,
    liquidityDelta: Decimal.Value
  ): { baseAmount: Decimal.Value; quoteAmount: Decimal.Value; baseFees: Decimal.Value; quoteFees: Decimal.Value } {
    // Create or update limit infos
    let lowerLimitInfo = this.limitInfos.get(lowerLimit)
    let upperLimitInfo = this.limitInfos.get(upperLimit)
    if (!lowerLimitInfo) {
      lowerLimitInfo = this.emptyLimitInfo()
    } else {
      lowerLimitInfo.liquidity = addDelta(lowerLimitInfo.liquidity, liquidityDelta)
      lowerLimitInfo.liquidityDelta = addDelta(lowerLimitInfo.liquidityDelta, liquidityDelta)
    }
    this.limitInfos.set(lowerLimit, lowerLimitInfo)
    if (!upperLimitInfo) {
      upperLimitInfo = this.emptyLimitInfo()
    } else {
      upperLimitInfo.liquidity = addDelta(upperLimitInfo.liquidity, liquidityDelta)
      upperLimitInfo.liquidityDelta = addDelta(upperLimitInfo.liquidityDelta, new Decimal(liquidityDelta).mul(-1))
    }

    // Create or update position
    const id = this.positionId(this.currLimit, lowerLimit, upperLimit)
    let position = this.positions.get(id)
    let baseFees = "0"
    let quoteFees = "0"
    if (!position) {
      position = {
        lowerLimit,
        upperLimit,
        liquidity: liquidityDelta,
        baseFeeFactorLast: 0,
        quoteFeeFactorLast: 0,
      }
    } else {
      position.liquidity = addDelta(position.liquidity, liquidityDelta)
      const { baseFeeFactor, quoteFeeFactor } = getFeeInside(
        lowerLimitInfo.baseFeeFactor,
        lowerLimitInfo.quoteFeeFactor,
        upperLimitInfo.baseFeeFactor,
        upperLimitInfo.quoteFeeFactor,
        lowerLimit,
        upperLimit,
        this.currLimit,
        this.baseFeeFactor,
        this.quoteFeeFactor
      )
      position.baseFeeFactorLast = baseFeeFactor
      position.quoteFeeFactorLast = quoteFeeFactor
      baseFees = new Decimal(baseFeeFactor).sub(position.baseFeeFactorLast).mul(position.liquidity).toFixed()
      quoteFees = new Decimal(quoteFeeFactor).sub(position.quoteFeeFactorLast).mul(position.liquidity).toFixed()
    }
    this.positions.set(id, position)

    // Update bitmap.
    this.bitmap.set(lowerLimit, lowerLimitInfo.liquidity === 0)
    this.bitmap.set(upperLimit, upperLimitInfo.liquidity === 0)

    // Update global liquidity if needed
    if (lowerLimit <= this.currLimit && this.currLimit < upperLimit) {
      this.liquidity = addDelta(this.liquidity, liquidityDelta)
    }

    // Calculate amounts.
    const { baseAmount, quoteAmount } = liquidityToAmounts(
      this.currLimit,
      this.currSqrtPrice,
      liquidityDelta,
      lowerLimit,
      upperLimit,
      this.width
    )

    // Return amounts and fees.
    return { baseAmount, quoteAmount, baseFees, quoteFees }
  }

  swap(isBuy: boolean, amount: Decimal.Value, exactInput: boolean, thresholdSqrtPrice?: Decimal.Value) {
    while (true) {
      const targetLimit = this.nextLimit(this.currLimit, isBuy)
      if (targetLimit === undefined) {
        break
      }

      const uncappedTargetSqrtPrice = limitToSqrtPrice(targetLimit, this.width)
      const targetSqrtPrice = thresholdSqrtPrice
        ? isBuy
          ? Decimal.min(uncappedTargetSqrtPrice, thresholdSqrtPrice)
          : Decimal.max(uncappedTargetSqrtPrice, thresholdSqrtPrice)
        : uncappedTargetSqrtPrice

      let amountIn, amountOut, fees, nextSqrtPrice
      if (exactInput) {
        const amountRemainingLessFee = new Decimal(1).sub(this.swapFeeRate).mul(amount)
        amountIn = isBuy
          ? liquidityToQuote(this.currSqrtPrice, targetSqrtPrice, this.liquidity)
          : liquidityToBase(targetSqrtPrice, this.currSqrtPrice, this.liquidity)
        nextSqrtPrice = amountRemainingLessFee.gte(amountIn)
          ? targetSqrtPrice
          : nextSqrtPriceAmountIn(this.currSqrtPrice, this.liquidity, amountRemainingLessFee, isBuy)
      } else {
        amountOut = isBuy
          ? liquidityToBase(this.currSqrtPrice, targetSqrtPrice, this.liquidity)
          : liquidityToQuote(targetSqrtPrice, this.currSqrtPrice, this.liquidity)
        nextSqrtPrice = new Decimal(amount).gte(amountOut)
          ? targetSqrtPrice
          : nextSqrtPriceAmountOut(this.currSqrtPrice, this.liquidity, amount, isBuy)
      }

      const max = targetSqrtPrice === nextSqrtPrice

      if (isBuy) {
        if (!max || !exactInput) {
          amountIn = liquidityToQuote(this.currSqrtPrice, nextSqrtPrice, this.liquidity)
        }
        if (!max || exactInput) {
          amountOut = liquidityToBase(this.currSqrtPrice, nextSqrtPrice, this.liquidity)
        }
      } else {
        if (!max || !exactInput) {
          amountIn = liquidityToBase(nextSqrtPrice, this.currSqrtPrice, this.liquidity)
        }
        if (!max || exactInput) {
          amountOut = liquidityToQuote(nextSqrtPrice, this.currSqrtPrice, this.liquidity)
        }
      }
    }
  }

  nextLimit(startLimit: number, isBuy: boolean) {
    let limit = startLimit
    while (true) {
      if (isBuy) {
        limit++
      } else {
        limit--
      }
      if (this.bitmap.get(limit) === true) {
        return limit
      }
    }
  }

  positionId(marketId: Decimal.Value, lowerLimit: Decimal.Value, upperLimit: Decimal.Value): string {
    return `${marketId}-${lowerLimit}-${upperLimit}`
  }

  emptyLimitInfo(): LimitInfo {
    return {
      liquidity: 0,
      liquidityDelta: 0,
      baseFeeFactor: 0,
      quoteFeeFactor: 0,
      initialised: false,
    }
  }
}
