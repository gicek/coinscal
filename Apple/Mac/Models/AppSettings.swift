import Foundation

struct AppSettings: Codable {
    /// Off by default: no login item is registered before the user opts in.
    var launchAtLogin: Bool = false
    var language: AppLanguage = .system
    var baseCurrency: BaseCurrency = .usd
    var priceColorEnabled: Bool = true
    var colorScheme: PriceColorScheme = .greenUpRedDown
    var customUpColorHex: String = Constants.Defaults.upColorHex
    var customDownColorHex: String = Constants.Defaults.downColorHex
    var priceChangeNotificationEnabled: Bool = true
    var pollingInterval: TimeInterval = Constants.Defaults.pollingInterval
    var showMenuBarBackground: Bool = false
    var menuBarContent: MenuBarContent = .price
    /// Desktop overlay (docs/DESKTOP_OVERLAY.md): a click-through price panel on the desktop.
    var desktopOverlayEnabled: Bool = false
    /// Medium by default: first-time users see the top of their watchlist (2026-10-15).
    var desktopOverlaySize: DesktopOverlaySize = .medium
    /// Opacity of the frosted background (0...1); the text stays opaque.
    var desktopOverlayBackgroundOpacity: Double = 1
    /// Window origin in global screen coordinates (any display); nil means the main display's default corner.
    /// Clamped onto the display it overlaps most when applied.
    var desktopOverlayOrigin: DesktopOverlayOrigin? = nil
    var displayedCoinId: String = "bitcoin"
    var watchlistCoins: [WatchlistCoin] = [
        WatchlistCoin(coinId: "bitcoin", alertKind: .change, notificationThreshold: Constants.Defaults.defaultNotificationThreshold),
        WatchlistCoin(coinId: "ethereum", alertKind: .change, notificationThreshold: Constants.Defaults.defaultNotificationThreshold),
    ]

    enum CodingKeys: String, CodingKey {
        case launchAtLogin, language, baseCurrency, priceColorEnabled, colorScheme
        case customUpColorHex, customDownColorHex
        case priceChangeNotificationEnabled, pollingInterval
        case showMenuBarBackground, menuBarContent, displayedCoinId
        case desktopOverlayEnabled, desktopOverlaySize, desktopOverlayBackgroundOpacity, desktopOverlayOrigin
        case watchlistCoins = "addedCoins"
    }

    init() {}

    /// Decodes field by field: a missing field (older data) or an unknown enum value (data from a newer version)
    /// falls back for that field only. Failing the whole decode would reset the watchlist and overwrite it on the next save.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        launchAtLogin = value(.launchAtLogin, d.launchAtLogin)
        language = value(.language, d.language)
        baseCurrency = value(.baseCurrency, d.baseCurrency)
        priceColorEnabled = value(.priceColorEnabled, d.priceColorEnabled)
        colorScheme = value(.colorScheme, d.colorScheme)
        customUpColorHex = value(.customUpColorHex, d.customUpColorHex)
        customDownColorHex = value(.customDownColorHex, d.customDownColorHex)
        priceChangeNotificationEnabled = value(.priceChangeNotificationEnabled, d.priceChangeNotificationEnabled)
        pollingInterval = value(.pollingInterval, d.pollingInterval)
        showMenuBarBackground = value(.showMenuBarBackground, d.showMenuBarBackground)
        menuBarContent = value(.menuBarContent, d.menuBarContent)
        desktopOverlayEnabled = value(.desktopOverlayEnabled, d.desktopOverlayEnabled)
        desktopOverlaySize = value(.desktopOverlaySize, d.desktopOverlaySize)
        desktopOverlayBackgroundOpacity = min(max(value(.desktopOverlayBackgroundOpacity, d.desktopOverlayBackgroundOpacity), 0), 1)
        desktopOverlayOrigin = value(.desktopOverlayOrigin, d.desktopOverlayOrigin)
        displayedCoinId = value(.displayedCoinId, d.displayedCoinId)
        if c.contains(.watchlistCoins) {
            // A broken entry drops only that entry.
            let items = (try? c.decode([LossyDecodable<WatchlistCoin>].self, forKey: .watchlistCoins)) ?? []
            watchlistCoins = items.compactMap(\.value)
        }
    }
}

/// Decodes to nil instead of throwing, for element-wise tolerant array decoding.
private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Price alert condition: above a price, below a price, or a % move from the reference price.
enum CoinAlertKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case above
    case below
    case change
    case notSet

    var id: String { rawValue }

    @MainActor
    var menuTitle: String {
        switch self {
        case .above:  return loc("alertKind.above")
        case .below:  return loc("alertKind.below")
        case .change: return loc("alertKind.change")
        case .notSet: return loc("alertKind.notSet")
        }
    }
}

struct WatchlistCoin: Codable, Identifiable, Hashable {
    let coinId: String
    var alertKind: CoinAlertKind
    /// Meaning depends on alertKind: Above/Below is a price threshold in **USD**; Change is a percentage.
    var notificationThreshold: Double
    var id: String { coinId }

    enum CodingKeys: String, CodingKey {
        case coinId
        case alertKind
        case notificationThreshold
    }

    init(coinId: String, alertKind: CoinAlertKind = .notSet, notificationThreshold: Double = 0) {
        self.coinId = coinId
        self.alertKind = alertKind
        self.notificationThreshold = notificationThreshold
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coinId = try c.decode(String.self, forKey: .coinId)
        alertKind = (try? c.decodeIfPresent(CoinAlertKind.self, forKey: .alertKind)) ?? .change
        notificationThreshold = (try? c.decodeIfPresent(Double.self, forKey: .notificationThreshold))
            ?? Constants.Defaults.defaultNotificationThreshold
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(coinId, forKey: .coinId)
        try c.encode(alertKind, forKey: .alertKind)
        try c.encode(notificationThreshold, forKey: .notificationThreshold)
    }

    static func == (lhs: WatchlistCoin, rhs: WatchlistCoin) -> Bool { lhs.coinId == rhs.coinId }
    func hash(into hasher: inout Hasher) { hasher.combine(coinId) }
}

enum BaseCurrency: String, Codable, CaseIterable, Identifiable {
    case usd = "USD"
    case cny = "CNY"
    case krw = "KRW"
    case hkd = "HKD"
    case jpy = "JPY"
    case twd = "TWD"
    case sgd = "SGD"
    case myr = "MYR"
    case aud = "AUD"
    case cad = "CAD"
    case eur = "EUR"
    case gbp = "GBP"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .usd, .cad, .aud, .sgd: return "$"
        case .cny, .jpy: return "¥"
        case .krw: return "₩"
        case .hkd: return "HK$"
        case .twd: return "NT$"
        case .myr: return "RM"
        case .eur: return "€"
        case .gbp: return "£"
        }
    }

    @MainActor
    var displayName: String {
        switch self {
        case .usd: return "USD"
        case .cny: return "CNY"
        case .krw: return "KRW"
        case .hkd: return "HKD"
        case .jpy: return "JPY"
        case .twd: return "TWD"
        case .sgd: return "SGD"
        case .myr: return "MYR"
        case .aud: return "AUD"
        case .cad: return "CAD"
        case .eur: return "EUR"
        case .gbp: return "GBP"
        }
    }
}

/// What the menu bar item shows: the selected coin's price, or the app icon only.
enum MenuBarContent: String, Codable, CaseIterable, Identifiable {
    case price
    case icon

    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .price: return loc("menubarContent.price")
        case .icon:  return loc("menubarContent.icon")
        }
    }
}

/// Desktop overlay size, matching the widget sizes: small shows the menu bar coin, medium / large the first 4 / 8
/// watchlist coins.
enum DesktopOverlaySize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .small:  return loc("desktop.size.small")
        case .medium: return loc("desktop.size.medium")
        case .large:  return loc("desktop.size.large")
        }
    }
}

struct DesktopOverlayOrigin: Codable, Equatable {
    var x: Double
    var y: Double
}

enum PriceColorScheme: String, Codable, CaseIterable, Identifiable {
    case greenUpRedDown = "greenUpRedDown"
    case redUpGreenDown = "redUpGreenDown"
    case custom = "custom"
    var id: String { rawValue }
    @MainActor
    var displayName: String {
        switch self {
        case .greenUpRedDown: return loc("colorScheme.greenUpRedDown")
        case .redUpGreenDown: return loc("colorScheme.redUpGreenDown")
        case .custom:         return loc("colorScheme.custom")
        }
    }
}
