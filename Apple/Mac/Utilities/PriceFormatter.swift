import Foundation

/// Numbers always use the POSIX locale (`.` decimal, `,` grouping). Grouping is a hard-coded `,`, so following
/// the system locale would give `1,234,56` in locales such as German that also use `,` as the decimal separator;
/// threshold fields also parse back with `.`.
enum PriceFormatter {
    private static func makeFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        return formatter
    }

    /// Formats a price; with `includeCurrencySymbol` false only the grouped number is returned (where the currency is implied).
    static func format(_ price: Double, currency: BaseCurrency, includeCurrencySymbol: Bool = true) -> String {
        let formatter = makeFormatter()
        formatter.minimumFractionDigits = price < 1 ? 4 : (price < 100 ? 2 : 0)
        formatter.maximumFractionDigits = price < 1 ? 6 : (price < 100 ? 2 : 0)
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.usesGroupingSeparator = true
        let formatted = formatter.string(from: NSNumber(value: price)) ?? "\(price)"
        if includeCurrencySymbol {
            return "\(currency.symbol)\(formatted)"
        }
        return formatted
    }

    static func formatShort(_ price: Double) -> String {
        let formatter = makeFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = price < 1 ? 4 : (price < 100 ? 2 : 0)
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: price)) ?? "\(price)"
    }

    static func formatPercent(_ percent: Double) -> String {
        let sign = percent >= 0 ? "+" : ""
        return String(format: "\(sign)%.2f%%", percent)
    }

    /// Above/Below: `notificationThreshold` is USD; `usdToTargetRate` converts USD to the display currency (as in `PriceService`).
    static func alertDisplayAmount(fromUsd usd: Double, usdToTargetRate: Double) -> Double {
        guard usdToTargetRate > 0 else { return usd }
        return usd * usdToTargetRate
    }

    static func alertUsdAmount(fromDisplay display: Double, usdToTargetRate: Double) -> Double {
        guard usdToTargetRate > 0 else { return display }
        return display / usdToTargetRate
    }

    /// Above/Below threshold display: decimals follow the reference price (usually the current price), not the threshold itself.
    static func formatAlertPriceThreshold(referencePrice: Double?, threshold: Double) -> String {
        let ruleSource: Double
        if let ref = referencePrice, ref > 0 {
            ruleSource = ref
        } else {
            ruleSource = threshold
        }
        let formatter = makeFormatter()
        formatter.minimumFractionDigits = ruleSource < 1 ? 4 : (ruleSource < 100 ? 2 : 0)
        formatter.maximumFractionDigits = ruleSource < 1 ? 6 : (ruleSource < 100 ? 2 : 0)
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: threshold)) ?? "\(threshold)"
    }
}
