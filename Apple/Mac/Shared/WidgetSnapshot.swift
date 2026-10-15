import Foundation

/// What the app hands to the widget extension through the App Group container (docs/WIDGET.md).
/// Written after every poll; the widget uses it while fresh and fetches prices itself otherwise.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Quote: Codable, Equatable, Sendable {
        /// In `WidgetSnapshot.currency`.
        var price: Double
        var change24hPercent: Double?
    }

    var writtenAt: Date
    var language: AppLanguage
    var currency: BaseCurrency
    var colorByChange: Bool
    /// Up / down colors with the color scheme already applied.
    var upColorHex: String
    var downColorHex: String
    var displayedCoinId: String
    /// Watchlist coin ids in the user's order.
    var watchlist: [String]
    /// Coin id → latest quote; coins without a market are absent.
    var quotes: [String: Quote]
}

/// Reads and writes the snapshot file. A nil directory (no App Group, e.g. an unsigned build) makes both no-ops;
/// tests pass a temporary directory instead of the real container.
struct WidgetSnapshotStore: Sendable {
    static let fileName = "widget-snapshot.json"
    /// Info.plist key holding the App Group id (`$(TeamIdentifierPrefix)com.gicek.coinscal`), set in both targets.
    static let appGroupInfoKey = "CoinscalAppGroup"

    let directory: URL?

    /// The shared App Group container of the app and the widget extension.
    static var appGroup: WidgetSnapshotStore {
        let id = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String
        let directory = id.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        return WidgetSnapshotStore(directory: directory)
    }

    private var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    /// nil when missing or unreadable (e.g. written by a newer version); the widget then fetches by itself.
    func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        guard let url = fileURL, let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
