import Foundation

/// Where the watchlist widget takes its coins from.
enum WidgetCoinSource: String, Sendable {
    case watchlist
    case manual
}

enum WidgetSortOrder: String, Sendable {
    case watchlist
    case changeDescending
    case changeAscending
}

/// One coin as the widget shows it.
struct WidgetRow: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let name: String
    let logoAssetName: String?
    /// False for coins no price source trades: shown as "No market data".
    let hasMarket: Bool
    var price: Double?
    var change24hPercent: Double?
}

/// Everything a widget view needs; built by the extension's timeline provider.
struct WidgetEntryContent: Equatable, Sendable {
    var rows: [WidgetRow]
    var currency: BaseCurrency
    /// When the prices were obtained; nil means no prices yet (app never ran and the widget could not fetch).
    var updatedAt: Date?
    var language: AppLanguage
    var colorByChange: Bool
    var upColorHex: String
    var downColorHex: String

    var hasPrices: Bool { updatedAt != nil && rows.contains { $0.price != nil } }

    func isStale(at now: Date) -> Bool {
        guard let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) > WidgetContent.staleAfter
    }
}

/// Pure widget rules (docs/WIDGET.md), shared by the app (tests) and the extension.
enum WidgetContent {
    /// Coin entity id meaning "follow the menu bar coin" (the price widget's default).
    static let followMenuBarCoinID = "follow-menu-bar"
    /// Snapshot younger than this is used without a network request.
    static let snapshotFreshFor: TimeInterval = 15 * 60
    /// Prices older than this are marked as outdated.
    static let staleAfter: TimeInterval = 30 * 60
    /// Next timeline reload the widget asks for; the system may stretch it.
    static let refreshInterval: TimeInterval = 15 * 60
    static let mediumRowLimit = 4
    static let largeRowLimit = 8

    static func priceCoinID(choice: String?, snapshot: WidgetSnapshot?) -> String {
        if let choice, choice != followMenuBarCoinID { return choice }
        return snapshot?.displayedCoinId ?? AppSettings().displayedCoinId
    }

    /// Watchlist source uses the app's watchlist (defaults before the app has run); manual falls back to it when empty.
    static func listCoinIDs(source: WidgetCoinSource, manual: [String], snapshot: WidgetSnapshot?, limit: Int) -> [String] {
        let watchlist = snapshot?.watchlist ?? AppSettings().watchlistCoins.map(\.coinId)
        let ids = source == .manual && !manual.isEmpty ? manual : watchlist
        var seen = Set<String>()
        return Array(ids.filter { seen.insert($0).inserted }.prefix(limit))
    }

    /// nil choice means "follow the app".
    static func currency(choice: BaseCurrency?, snapshot: WidgetSnapshot?) -> BaseCurrency {
        choice ?? snapshot?.currency ?? AppSettings().baseCurrency
    }

    /// Snapshot quotes usable without a request: fresh, in the wanted currency, and covering every coin with a market.
    static func freshQuotes(
        snapshot: WidgetSnapshot?, ids: [String], tradable: Set<String>, currency: BaseCurrency, now: Date
    ) -> [String: WidgetSnapshot.Quote]? {
        guard let snapshot, snapshot.currency == currency,
              now.timeIntervalSince(snapshot.writtenAt) < snapshotFreshFor,
              ids.filter(tradable.contains).allSatisfy({ snapshot.quotes[$0] != nil }) else { return nil }
        return snapshot.quotes
    }

    /// Sorting by change keeps coins without a change at the end, in their original order.
    static func sorted(_ rows: [WidgetRow], by order: WidgetSortOrder) -> [WidgetRow] {
        guard order != .watchlist else { return rows }
        let withChange = rows.filter { $0.change24hPercent != nil }
        let without = rows.filter { $0.change24hPercent == nil }
        let sorted = withChange.enumerated().sorted { a, b in
            let x = a.element.change24hPercent!, y = b.element.change24hPercent!
            if x == y { return a.offset < b.offset }
            return order == .changeDescending ? x > y : x < y
        }.map(\.element)
        return sorted + without
    }
}

extension AppSettings {
    /// Up color after applying the color scheme.
    var resolvedUpColorHex: String {
        switch colorScheme {
        case .greenUpRedDown: return Constants.Defaults.upColorHex
        case .redUpGreenDown: return Constants.Defaults.downColorHex
        case .custom: return customUpColorHex
        }
    }

    /// Down color after applying the color scheme.
    var resolvedDownColorHex: String {
        switch colorScheme {
        case .greenUpRedDown: return Constants.Defaults.downColorHex
        case .redUpGreenDown: return Constants.Defaults.upColorHex
        case .custom: return customDownColorHex
        }
    }
}
