import Testing
@testable import Coinscal

@Suite struct AlertEvaluatorTests {
    private func coin(_ kind: CoinAlertKind, _ threshold: Double) -> WatchlistCoin {
        WatchlistCoin(coinId: "bitcoin", alertKind: kind, notificationThreshold: threshold)
    }

    private func triggers(
        _ kind: CoinAlertKind,
        threshold: Double,
        newPrice: Double = 100,
        changeFromRef: Double = 0,
        referencePrice: Double? = nil,
        rate: Double = 1
    ) -> Bool {
        AlertEvaluator.shouldTriggerPriceAlert(
            newPrice: newPrice,
            changeFromRef: changeFromRef,
            watchlistCoin: coin(kind, threshold),
            referencePrice: referencePrice,
            usdToTargetRate: rate
        )
    }

    @Test func changeTriggersAtThresholdInEitherDirection() {
        #expect(triggers(.change, threshold: 2, changeFromRef: 2))
        #expect(triggers(.change, threshold: 2, changeFromRef: -2.5))
        #expect(!triggers(.change, threshold: 2, changeFromRef: 1.99))
    }

    @Test func notSetNeverTriggers() {
        #expect(!triggers(.notSet, threshold: 0, changeFromRef: 50))
    }

    @Test func aboveComparesInDisplayCurrencyAndOnlyOnCrossing() {
        // Threshold 100 USD at rate 7 → 700 in the display currency.
        #expect(triggers(.above, threshold: 100, newPrice: 710, referencePrice: 690, rate: 7))
        #expect(!triggers(.above, threshold: 100, newPrice: 710, referencePrice: 705, rate: 7), "already above: no repeat alert")
        #expect(!triggers(.above, threshold: 100, newPrice: 710, referencePrice: nil, rate: 7), "no reference price: a crossing cannot be known")
        #expect(!triggers(.above, threshold: 100, newPrice: 690, referencePrice: 600, rate: 7))
    }

    @Test func belowOnlyOnCrossing() {
        #expect(triggers(.below, threshold: 100, newPrice: 95, referencePrice: 105))
        #expect(!triggers(.below, threshold: 100, newPrice: 95, referencePrice: 98))
        #expect(!triggers(.below, threshold: 100, newPrice: 105, referencePrice: 110))
        #expect(!triggers(.below, threshold: 100, newPrice: 95, referencePrice: nil))
    }

    @Test func referencePriceFollowsPriceWhileOnFarSideOfAboveThreshold() {
        var c = Coin(id: "bitcoin", symbol: "BTC", name: "Bitcoin", rank: 1, logoAssetName: nil, logoURL: nil, referencePrice: 90)
        AlertEvaluator.updateReferencePriceAfterNoTrigger(coin: &c, newPrice: 95, watchlistCoin: coin(.above, 100), usdToTargetRate: 1)
        #expect(c.referencePrice == 95)
        AlertEvaluator.updateReferencePriceAfterNoTrigger(coin: &c, newPrice: 120, watchlistCoin: coin(.above, 100), usdToTargetRate: 1)
        #expect(c.referencePrice == 95, "stops following once past the threshold, so a later re-crossing still alerts")
    }

    @Test func changeKeepsFirstReferencePrice() {
        var c = Coin(id: "bitcoin", symbol: "BTC", name: "Bitcoin", rank: 1, logoAssetName: nil, logoURL: nil, referencePrice: 100)
        AlertEvaluator.updateReferencePriceAfterNoTrigger(coin: &c, newPrice: 101, watchlistCoin: coin(.change, 2), usdToTargetRate: 1)
        #expect(c.referencePrice == 100)
    }

    @Test func clampsThresholdPerKind() {
        #expect(AlertEvaluator.clampAlertThreshold(0.1, kind: .change) == 0.5)
        #expect(AlertEvaluator.clampAlertThreshold(500, kind: .change) == 200)
        #expect(AlertEvaluator.clampAlertThreshold(-5, kind: .above) == 1)
        #expect(AlertEvaluator.clampAlertThreshold(65_000, kind: .below) == 65_000)
        #expect(AlertEvaluator.clampAlertThreshold(-1, kind: .notSet) == 0)
    }
}
