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

    private static func formattedPrice(_ price: Double, with formatter: NumberFormatter) -> String {
        let formatted = formatter.string(from: NSNumber(value: price)) ?? String(price)
        let roundsToZero = price > 0 && price <= pow(10, -Double(formatter.maximumFractionDigits)) / 2
        guard roundsToZero else { return formatted }
        let parts = String(format: "%.2e", price).split(separator: "e")
        guard parts.count == 2, let exponent = Int(parts[1]) else { return formatted }
        return "\(parts[0])e\(exponent)"
    }

    /// Formats a price; with `includeCurrencySymbol` false only the grouped number is returned (where the currency is implied).
    static func format(_ price: Double, currency: BaseCurrency, includeCurrencySymbol: Bool = true) -> String {
        let formatter = makeFormatter()
        formatter.minimumFractionDigits = price < 1 ? 4 : (price < 100 ? 2 : 0)
        formatter.maximumFractionDigits = price < 1 ? 6 : (price < 100 ? 2 : 0)
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.usesGroupingSeparator = true
        let formatted = formattedPrice(price, with: formatter)
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
        return formattedPrice(price, with: formatter)
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

    /// Preserve decimal places in the editable amount. Very small positive amounts use exponent notation.
    static func formatAlertAmount(_ amount: Double) -> String {
        let formatter = makeFormatter()
        formatter.maximumFractionDigits = 12
        formatter.usesGroupingSeparator = false
        let text = formatter.string(from: NSNumber(value: amount)) ?? String(amount)
        return amount > 0 && text == "0" ? String(amount) : text
    }

    static func parseAlertAmount(_ input: String) -> Double? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.wholeMatch(of: /(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?|\.[0-9]+/) != nil,
              let result = Double(text.replacingOccurrences(of: ",", with: "")),
              result.isFinite else { return nil }
        return result
    }
}
