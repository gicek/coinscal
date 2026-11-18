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

    @Test func formatsMidpointsAndKeepsTinyPositivePricesVisible() {
        #expect(PriceFormatter.formatShort(100.5) == "100")
        #expect(PriceFormatter.formatShort(0.000012345) == "1.23e-5")
        #expect(PriceFormatter.format(0.00000012345, currency: .usd) == "$1.23e-7")
    }

    @Test func percentHasExplicitSign() {
        #expect(PriceFormatter.formatPercent(2.5) == "+2.50%")
        #expect(PriceFormatter.formatPercent(-1.25) == "-1.25%")
        #expect(PriceFormatter.formatPercent(0) == "+0.00%")
    }

    @Test func alertInputPreservesDecimalPrecisionAndParsesGrouping() {
        #expect(PriceFormatter.formatAlertAmount(66_300.4) == "66300.4")
        #expect(PriceFormatter.formatAlertAmount(0.51) == "0.51")
        #expect(PriceFormatter.parseAlertAmount("1,000.25") == 1_000.25)
        let tiny = 1.25868e-13
        #expect(PriceFormatter.parseAlertAmount(PriceFormatter.formatAlertAmount(tiny)) == tiny)
        #expect(PriceFormatter.parseAlertAmount("1,00.25") == nil)
        #expect(PriceFormatter.parseAlertAmount("1e309") == nil)
    }

    @Test func usdConversionRoundTripsAndIgnoresInvalidRate() {
        #expect(PriceFormatter.alertDisplayAmount(fromUsd: 100, usdToTargetRate: 7) == 700)
        #expect(PriceFormatter.alertUsdAmount(fromDisplay: 700, usdToTargetRate: 7) == 100)
        #expect(PriceFormatter.alertDisplayAmount(fromUsd: 100, usdToTargetRate: 0) == 100)
        #expect(PriceFormatter.alertUsdAmount(fromDisplay: 100, usdToTargetRate: -1) == 100)
    }
}
