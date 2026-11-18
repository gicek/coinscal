import Foundation

enum AlertEvaluator {

    /// Whether a price alert should fire.
    /// Above/Below receive USD prices and fire once when the price crosses the threshold; without a reference price only the reference is set.
    static func shouldTriggerPriceAlert(
        newPrice: Double,
        changeFromRef: Double,
        watchlistCoin: WatchlistCoin,
        referencePrice: Double?
    ) -> Bool {
        let tUsd = watchlistCoin.notificationThreshold
        switch watchlistCoin.alertKind {
        case .notSet:
            return false
        case .change:
            return abs(changeFromRef) >= tUsd
        case .above:
            // Fire only when crossing from below to above; with no reference price (just launched or currency switched) a crossing cannot be known.
            guard newPrice >= tUsd, let ref = referencePrice else { return false }
            return ref < tUsd
        case .below:
            guard newPrice <= tUsd, let ref = referencePrice else { return false }
            return ref > tUsd
        }
    }

    /// Updates the reference price when no alert fired.
    static func updateReferencePriceAfterNoTrigger(
        coin: inout Coin,
        newPrice: Double,
        watchlistCoin: WatchlistCoin
    ) {
        let tUsd = watchlistCoin.notificationThreshold
        switch watchlistCoin.alertKind {
        case .notSet, .change:
            if coin.referencePrice == nil {
                coin.referencePrice = newPrice
            }
        case .above:
            if newPrice < tUsd || coin.referencePrice == nil {
                coin.referencePrice = newPrice
            }
        case .below:
            if newPrice > tUsd || coin.referencePrice == nil {
                coin.referencePrice = newPrice
            }
        }
    }

    /// Change: 0.5…200; Above/Below: USD threshold > 0; Off is not validated (stored as 0).
    static func clampAlertThreshold(_ v: Double, kind: CoinAlertKind) -> Double {
        switch kind {
        case .notSet:
            return max(0, v)
        case .change:
            return min(200, max(0.5, v))
        case .above, .below:
            if v > 0 { return min(v, 1e15) }
            return 1.0
        }
    }
}
