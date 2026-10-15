import Foundation

/// Trading status of a catalog coin (docs/COIN_CATALOG.md).
enum CoinStatus: String, Codable, Sendable {
    /// At least one price source has a USDT spot pair.
    case active
    /// None of the price sources trades it; shown as "No market data".
    case delisted
    /// Superseded by another catalog coin (`migratedTo`); watchlist entries are swapped for it automatically
    /// (`CoinCatalog.settingsWithSuccessors`), so it is never shown.
    case migrated
}

/// Coin shown in the popover and menu bar: catalog metadata plus live market data.
struct Coin: Identifiable, Hashable {
    let id: String           // CoinGecko id, e.g. "bitcoin"
    let symbol: String       // current symbol, updated with the catalog after a rename, e.g. "BTC"
    let name: String
    let rank: Int?
    let logoAssetName: String?  // bundled logo asset
    let logoURL: String?        // remote logo
    var status: CoinStatus = .active

    var currentPrice: Double?
    var priceChange24hPercent: Double?  // e.g. 2.5 means +2.5%
    var referencePrice: Double?         // for threshold notification tracking
    var lastUpdated: Date?
}

/// One catalog entry. `id` is the CoinGecko id and identifies a watchlist coin; the symbol can change with a rename.
struct CoinMetadata: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let symbol: String
    let name: String
    let rank: Int?
    let logoURL: String?
    let status: CoinStatus
    /// Shown in search and recommendations (about the top 100); false entries only keep existing watchlists working.
    let listed: Bool
    let migratedTo: String?
    /// Bundled logo asset name (`coin-<id>`), filled in by the catalog when the asset exists; not part of the JSON.
    var logoAssetName: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, symbol, name, rank, logoURL, status, listed, migratedTo
    }
}
