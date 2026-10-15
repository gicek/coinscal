import AppKit
import Combine
import OSLog

/// Coin catalog: the single metadata source for the watchlist, search, recommendations and the context menu (docs/COIN_CATALOG.md).
/// Currently reads the bundled `coins.json` snapshot only; remote updates are phase 3 of the plan.
@MainActor
final class CoinCatalog: ObservableObject {
    nonisolated static let schemaVersion = 1
    nonisolated static let logoHosts: Set<String> = ["coin-images.coingecko.com", "assets.coingecko.com"]
    nonisolated static let listedRange = 50...150
    private static let logger = Logger(subsystem: "com.gicek.coinscal", category: "CoinCatalog")

    /// Sorted by market cap rank (unranked last).
    @Published private(set) var coins: [CoinMetadata] = []
    private var byID: [String: CoinMetadata] = [:]

    init(coins: [CoinMetadata]) {
        apply(coins)
    }

    /// Bundled snapshot. Missing or invalid means a packaging error: log a fault and fall back to an empty catalog (`CoinCatalogTests` guards this).
    static func bundled(bundle: Bundle = .main) -> CoinCatalog {
        do {
            guard let url = bundle.url(forResource: "coins", withExtension: "json") else {
                throw CatalogError.invalid(["coins.json missing from bundle"])
            }
            return CoinCatalog(coins: try decodeValidated(Data(contentsOf: url)))
        } catch {
            logger.fault("Bundled coin catalog unusable: \(String(describing: error), privacy: .public)")
            return CoinCatalog(coins: [])
        }
    }

    /// Search and recommendations only use listed tradable coins.
    var listed: [CoinMetadata] { coins.filter(\.listed) }

    func metadata(for id: String) -> CoinMetadata? { byID[id] }

    /// Swaps old coin ids in the watchlist for their successor (`migratedTo`), so only the new coin is ever shown.
    /// Change and Off alerts carry over; Above/Below thresholds are prices of the old coin and not comparable, so they
    /// reset to the default Change 2%. If the new coin is already in the watchlist, the old entry is dropped.
    /// Returns nil when nothing changes.
    func settingsWithSuccessors(_ settings: AppSettings) -> AppSettings? {
        var result = settings
        var changed = false
        for old in settings.watchlistCoins {
            guard let meta = metadata(for: old.coinId), meta.status == .migrated,
                  let newID = meta.migratedTo, metadata(for: newID)?.status == .active,
                  let index = result.watchlistCoins.firstIndex(where: { $0.coinId == old.coinId }) else { continue }
            if result.watchlistCoins.contains(where: { $0.coinId == newID }) {
                result.watchlistCoins.remove(at: index)
            } else {
                let keepsAlert = old.alertKind == .change || old.alertKind == .notSet
                result.watchlistCoins[index] = WatchlistCoin(
                    coinId: newID,
                    alertKind: keepsAlert ? old.alertKind : .change,
                    notificationThreshold: keepsAlert ? old.notificationThreshold : Constants.Defaults.defaultNotificationThreshold
                )
            }
            if result.displayedCoinId == old.coinId {
                result.displayedCoinId = newID
            }
            changed = true
        }
        return changed ? result : nil
    }

    private func apply(_ newCoins: [CoinMetadata]) {
        let resolved = newCoins.map { coin -> CoinMetadata in
            var coin = coin
            let assetName = "coin-\(coin.id)"
            coin.logoAssetName = NSImage(named: assetName) != nil ? assetName : nil
            return coin
        }
        coins = resolved.sorted { ($0.rank ?? .max, $0.id) < ($1.rank ?? .max, $1.id) }
        byID = Dictionary(coins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Decoding and validation (same rules as scripts/catalog/generate_catalog.py validate; change both together)

    enum CatalogError: Error {
        case invalid([String])
    }

    private struct File: Decodable {
        let schemaVersion: Int
        let coins: [CoinMetadata]
    }

    nonisolated static func decodeValidated(_ data: Data) throws -> [CoinMetadata] {
        let file = try JSONDecoder().decode(File.self, from: data)
        let problems = validate(schemaVersion: file.schemaVersion, coins: file.coins)
        guard problems.isEmpty else { throw CatalogError.invalid(problems) }
        return file.coins
    }

    nonisolated static func validate(schemaVersion: Int, coins: [CoinMetadata]) -> [String] {
        guard schemaVersion == Self.schemaVersion else { return ["schemaVersion \(schemaVersion)"] }
        var problems: [String] = []
        let byID = Dictionary(coins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if byID.count != coins.count { problems.append("duplicate id") }

        let listedCount = coins.filter(\.listed).count
        if !listedRange.contains(listedCount) { problems.append("listed count \(listedCount)") }
        for required in ["bitcoin", "ethereum"] where !(byID[required].map { $0.listed && $0.status == .active } ?? false) {
            problems.append("missing tradable \(required)")
        }
        let activeSymbols = coins.filter { $0.status == .active }.map(\.symbol)
        if Set(activeSymbols).count != activeSymbols.count { problems.append("duplicate active symbol") }

        for coin in coins {
            if coin.id.wholeMatch(of: #/[a-z0-9][a-z0-9-]{0,79}/#) == nil { problems.append("\(coin.id): id") }
            if coin.symbol.wholeMatch(of: #/[A-Z0-9]{1,15}/#) == nil { problems.append("\(coin.id): symbol") }
            if coin.name.isEmpty || coin.name.count > 60 { problems.append("\(coin.id): name") }
            if let rank = coin.rank, rank <= 0 { problems.append("\(coin.id): rank") }
            if let logo = coin.logoURL, URL(string: logo).flatMap(\.host).map({ logoHosts.contains($0) }) != true {
                problems.append("\(coin.id): logo host")
            }
            if coin.listed && coin.status != .active { problems.append("\(coin.id): listed but not active") }
            if coin.status == .migrated {
                guard let target = coin.migratedTo.flatMap({ byID[$0] }) else {
                    problems.append("\(coin.id): migratedTo missing")
                    continue
                }
                if target.status != .active { problems.append("\(coin.id): migration target not active") }
            }
        }
        return problems
    }
}
