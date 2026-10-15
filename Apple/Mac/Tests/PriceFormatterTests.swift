import Testing
@testable import Coinscal

@Suite struct PriceFormatterTests {
    @Test func decimalsDependOnMagnitude() {
        #expect(PriceFormatter.format(65_000.12, currency: .usd) == "$65,000")
        #expect(PriceFormatter.format(1.5, currency: .usd) == "$1.50")
        #expect(PriceFormatter.format(0.5, currency: .usd) == "$0.5000")
        #expect(PriceFormatter.format(0.1234567, currency: .usd) == "$0.123457")
    }

    @Test func currencySymbolCanBeOmitted() {
        #expect(PriceFormatter.format(1234.4, currency: .hkd) == "HK$1,234")
        #expect(PriceFormatter.format(1234.4, currency: .hkd, includeCurrencySymbol: false) == "1,234")
    }

    /// Regression: number formatting ignores the system locale; the decimal point is always `.`, never clashing with the `,` grouping.
    @Test func usesPosixSeparators() {
        #expect(PriceFormatter.formatShort(12.25) == "12.25")
        #expect(PriceFormatter.formatShort(1234.4) == "1,234")
    }

    @Test func percentHasExplicitSign() {
        #expect(PriceFormatter.formatPercent(2.5) == "+2.50%")
        #expect(PriceFormatter.formatPercent(-1.25) == "-1.25%")
        #expect(PriceFormatter.formatPercent(0) == "+0.00%")
    }

    @Test func alertThresholdUsesReferencePriceDecimalsWithoutGrouping() {
        #expect(PriceFormatter.formatAlertPriceThreshold(referencePrice: 65_000, threshold: 66_300.4) == "66300")
        #expect(PriceFormatter.formatAlertPriceThreshold(referencePrice: 0.5, threshold: 0.51) == "0.5100")
        #expect(PriceFormatter.formatAlertPriceThreshold(referencePrice: nil, threshold: 12.5) == "12.50")
    }

    @Test func usdConversionRoundTripsAndIgnoresInvalidRate() {
        #expect(PriceFormatter.alertDisplayAmount(fromUsd: 100, usdToTargetRate: 7) == 700)
        #expect(PriceFormatter.alertUsdAmount(fromDisplay: 700, usdToTargetRate: 7) == 100)
        #expect(PriceFormatter.alertDisplayAmount(fromUsd: 100, usdToTargetRate: 0) == 100)
        #expect(PriceFormatter.alertUsdAmount(fromDisplay: 100, usdToTargetRate: -1) == 100)
    }
}
