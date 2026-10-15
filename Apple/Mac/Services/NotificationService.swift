import Foundation
import OSLog
import UserNotifications

/// Injection point for price alerts; tests inject a recording double instead of sending real notifications.
@MainActor
protocol PriceAlertNotifying {
    func sendPriceAlert(
        coin: Coin,
        alertKind: CoinAlertKind,
        threshold: Double,
        changePercent: Double,
        baseCurrency: BaseCurrency,
        usdToTargetRate: Double
    )
}

@MainActor
final class NotificationService: PriceAlertNotifying {
    static let shared = NotificationService()
    private nonisolated static let logger = Logger(subsystem: "com.gicek.coinscal", category: "Notifications")

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                Self.logger.error("Notification permission error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func sendPriceAlert(
        coin: Coin,
        alertKind: CoinAlertKind,
        threshold: Double,
        changePercent: Double,
        baseCurrency: BaseCurrency,
        usdToTargetRate: Double
    ) {
        let content = UNMutableNotificationContent()
        content.title = String(format: loc("notification.priceAlert.title"), coin.name)

        let priceText = coin.currentPrice.map { PriceFormatter.formatShort($0) } ?? "--"

        switch alertKind {
        case .notSet:
            content.subtitle = String(format: loc("notification.priceAlert.notSet"), coin.symbol, priceText)
        case .change:
            let direction = changePercent >= 0 ? loc("notification.direction.up") : loc("notification.direction.down")
            let formattedChange = String(format: "%.2f%%", abs(changePercent))
            content.subtitle = String(format: loc("notification.priceAlert.change"), coin.symbol, direction, formattedChange, priceText)
        case .above, .below:
            let thresholdDisplay = PriceFormatter.alertDisplayAmount(fromUsd: threshold, usdToTargetRate: usdToTargetRate)
            let thresholdText = PriceFormatter.format(thresholdDisplay, currency: baseCurrency)
            let key = alertKind == .above ? "notification.priceAlert.above" : "notification.priceAlert.below"
            content.subtitle = String(format: loc(key), coin.symbol, thresholdText, priceText)
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "price-alert-\(coin.id)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Failed to deliver notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
