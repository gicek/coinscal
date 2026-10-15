import AppIntents
import WidgetKit

// "Edit Widget" options (docs/WIDGET.md). Titles are String Catalog keys; option lists follow the
// system language because the system renders the edit panel.

enum WidgetCurrencyOption: String, AppEnum {
    case followApp
    case usd = "USD", cny = "CNY", krw = "KRW", hkd = "HKD", jpy = "JPY", twd = "TWD"
    case sgd = "SGD", myr = "MYR", aud = "AUD", cad = "CAD", eur = "EUR", gbp = "GBP"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.param.currency")
    static let caseDisplayRepresentations: [WidgetCurrencyOption: DisplayRepresentation] = [
        .followApp: DisplayRepresentation(title: "widget.currency.followApp"),
        .usd: "USD", .cny: "CNY", .krw: "KRW", .hkd: "HKD", .jpy: "JPY", .twd: "TWD",
        .sgd: "SGD", .myr: "MYR", .aud: "AUD", .cad: "CAD", .eur: "EUR", .gbp: "GBP",
    ]

    /// nil: follow the app's display currency.
    var baseCurrency: BaseCurrency? { BaseCurrency(rawValue: rawValue) }
}

enum WidgetCoinSourceOption: String, AppEnum {
    case watchlist
    case manual

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.param.source")
    static let caseDisplayRepresentations: [WidgetCoinSourceOption: DisplayRepresentation] = [
        .watchlist: DisplayRepresentation(title: "widget.source.watchlist"),
        .manual: DisplayRepresentation(title: "widget.source.manual"),
    ]

    var source: WidgetCoinSource { WidgetCoinSource(rawValue: rawValue) ?? .watchlist }
}

enum WidgetSortOption: String, AppEnum {
    case watchlist
    case changeDescending
    case changeAscending

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.param.sort")
    static let caseDisplayRepresentations: [WidgetSortOption: DisplayRepresentation] = [
        .watchlist: DisplayRepresentation(title: "widget.sort.watchlist"),
        .changeDescending: DisplayRepresentation(title: "widget.sort.changeDescending"),
        .changeAscending: DisplayRepresentation(title: "widget.sort.changeAscending"),
    ]

    var order: WidgetSortOrder { WidgetSortOrder(rawValue: rawValue) ?? .watchlist }
}

// MARK: - Coins

/// Coin for the price widget; includes "Follow Menu Bar Coin" (the default).
struct WidgetCoinEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.param.coin")
    static let defaultQuery = WidgetCoinQuery()

    let id: String
    let symbol: String
    let name: String

    static let followMenuBar = WidgetCoinEntity(id: WidgetContent.followMenuBarCoinID, symbol: "", name: "")

    var displayRepresentation: DisplayRepresentation {
        id == WidgetContent.followMenuBarCoinID
            ? DisplayRepresentation(title: "widget.coin.followMenuBar")
            : DisplayRepresentation(title: "\(symbol)", subtitle: "\(name)")
    }
}

/// Coin for the watchlist widget's manual selection.
struct WidgetListCoinEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.param.coin")
    static let defaultQuery = WidgetListCoinQuery()

    let id: String
    let symbol: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(symbol)", subtitle: "\(name)")
    }
}

/// Options come from the bundled catalog's listed (searchable) coins.
@MainActor
enum WidgetCoinOptions {
    static func listed() -> [CoinMetadata] { WidgetDataLoader.catalog.listed }

    static func metadata(_ ids: [String]) -> [CoinMetadata] {
        ids.compactMap { WidgetDataLoader.catalog.metadata(for: $0) }
    }

    static func matching(_ text: String) -> [CoinMetadata] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return listed() }
        return listed().filter { $0.symbol.lowercased().contains(query) || $0.name.lowercased().contains(query) }
    }
}

struct WidgetCoinQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetCoinEntity] {
        let coins = await MainActor.run { WidgetCoinOptions.metadata(identifiers).map(Self.entity) }
        return identifiers.contains(WidgetContent.followMenuBarCoinID) ? [.followMenuBar] + coins : coins
    }

    func entities(matching string: String) async throws -> [WidgetCoinEntity] {
        await MainActor.run { WidgetCoinOptions.matching(string).map(Self.entity) }
    }

    func suggestedEntities() async throws -> [WidgetCoinEntity] {
        [.followMenuBar] + (await MainActor.run { WidgetCoinOptions.listed().map(Self.entity) })
    }

    func defaultResult() async -> WidgetCoinEntity? { .followMenuBar }

    private static func entity(_ meta: CoinMetadata) -> WidgetCoinEntity {
        WidgetCoinEntity(id: meta.id, symbol: meta.symbol, name: meta.name)
    }
}

struct WidgetListCoinQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetListCoinEntity] {
        await MainActor.run { WidgetCoinOptions.metadata(identifiers).map(Self.entity) }
    }

    func entities(matching string: String) async throws -> [WidgetListCoinEntity] {
        await MainActor.run { WidgetCoinOptions.matching(string).map(Self.entity) }
    }

    func suggestedEntities() async throws -> [WidgetListCoinEntity] {
        await MainActor.run { WidgetCoinOptions.listed().map(Self.entity) }
    }

    private static func entity(_ meta: CoinMetadata) -> WidgetListCoinEntity {
        WidgetListCoinEntity(id: meta.id, symbol: meta.symbol, name: meta.name)
    }
}

// MARK: - Configurations

struct CoinPriceConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.price.name"
    static let description = IntentDescription("widget.price.description")

    @Parameter(title: "widget.param.coin")
    var coin: WidgetCoinEntity?

    @Parameter(title: "widget.param.currency", default: .followApp)
    var currency: WidgetCurrencyOption

    @Parameter(title: "widget.param.colorByChange", default: true)
    var colorByChange: Bool
}

struct WatchlistConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.list.name"
    static let description = IntentDescription("widget.list.description")

    @Parameter(title: "widget.param.source", default: .watchlist)
    var source: WidgetCoinSourceOption

    @Parameter(title: "widget.param.coins", size: [.systemMedium: 4, .systemLarge: 8])
    var coins: [WidgetListCoinEntity]?

    @Parameter(title: "widget.param.sort", default: .watchlist)
    var sort: WidgetSortOption

    @Parameter(title: "widget.param.currency", default: .followApp)
    var currency: WidgetCurrencyOption

    @Parameter(title: "widget.param.colorByChange", default: true)
    var colorByChange: Bool

    static var parameterSummary: some ParameterSummary {
        When(\WatchlistConfigurationIntent.$source, .equalTo, .manual) {
            Summary {
                \.$source
                \.$coins
                \.$sort
                \.$currency
                \.$colorByChange
            }
        } otherwise: {
            Summary {
                \.$source
                \.$sort
                \.$currency
                \.$colorByChange
            }
        }
    }
}
