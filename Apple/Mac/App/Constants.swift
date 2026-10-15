import Foundation
import CoreGraphics

enum Constants {
    enum API {
        /// Timeout per price request; failover to another source must fit within one poll interval.
        static let requestTimeout: TimeInterval = 5

        /// Price sources (public, key-free, fine for frequent polling), tried in declaration order.
        static let binanceBaseURL = "https://api.binance.com/api/v3"
        static let binanceVisionBaseURL = "https://data-api.binance.vision/api/v3"
        static let okxTickersURL = "https://www.okx.com/api/v5/market/tickers?instType=SPOT"
        static let bybitTickersURL = "https://api.bybit.com/v5/market/tickers?category=spot"

        /// FX rate sources (public, key-free, updated daily), tried in declaration order.
        static let erApiRatesURL = "https://open.er-api.com/v6/latest/USD"
        static let jsDelivrRatesURL = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json"
        static let currencyApiPagesRatesURL = "https://latest.currency-api.pages.dev/v1/currencies/usd.min.json"

        /// Rates change daily; cache them for an hour instead of refetching every 10 s poll.
        static let exchangeRateCacheTTL: TimeInterval = 3600
    }

    enum Defaults {
        static let pollingInterval: TimeInterval = 10
        static let defaultNotificationThreshold: Double = 2.0  // 2%
        static let recommendedCoinSymbols = ["BTC", "ETH", "BNB", "SOL", "XRP", "ADA", "DOGE", "AVAX", "DOT", "POL"]
        static let upColorHex = "#2CBD84"
        static let downColorHex = "#F6465D"
    }

    enum Popover {
        static let width: CGFloat = 320
        static let rowHeight: CGFloat = 52
        static let headerHeight: CGFloat = 38
        static let footerHeight: CGFloat = 52
        /// The list area is sized for at least 4 rows and at most 8; more coins scroll.
        static let minVisibleRows = 4
        static let maxVisibleRows = 8

        static func height(forCoinCount count: Int) -> CGFloat {
            let rows = min(max(count, minVisibleRows), maxVisibleRows)
            return headerHeight + CGFloat(rows) * rowHeight + footerHeight
        }
    }

    /// Contact details shown on the About page.
    enum Contact {
        static let email = "kk@gicek.com"
        static let emailURL = URL(string: "mailto:kk@gicek.com")!
        static let xHandle = "coinscal"
        static let xURL = URL(string: "https://x.com/coinscal")!
    }

    enum Window {
        static let settingsMaxSize = CGSize(width: 800, height: 500)
        static let settingsMinSize = CGSize(width: 600, height: 420)
        /// Size on first open; afterwards the autosaved frame wins.
        static let settingsDefaultSize = CGSize(width: 786, height: 500)
        static let settingsSidebarIdealWidth: CGFloat = 190

        /// Content padding shared by the settings panes.
        static let settingsContentPadding: CGFloat = 24
    }

    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
}
