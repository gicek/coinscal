import Foundation

/// Watchlist management: search, recommendations, add/remove. All metadata comes from the injected `CoinCatalog`.
@MainActor
final class WatchlistViewModel: ObservableObject {
    @Published var searchText = ""

    private let catalog: CoinCatalog
    private(set) var recommendedSymbols: [String] = Constants.Defaults.recommendedCoinSymbols

    /// Recommendations show listed tradable coins only, in `recommendedCoins.json` order.
    var recommendedCoins: [CoinMetadata] {
        let listedBySymbol = Dictionary(catalog.listed.map { ($0.symbol, $0) }, uniquingKeysWith: { first, _ in first })
        return recommendedSymbols.compactMap { listedBySymbol[$0] }
    }

    /// What the add-coin panel lists: every listed coin in catalog order until a query is typed, then the matches.
    /// Searched synchronously (about 100 coins), so the list never lags the text.
    var addCoinResults: [CoinMetadata] {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty ? catalog.listed : search(searchText)
    }

    init(catalog: CoinCatalog, bundle: Bundle = .main) {
        self.catalog = catalog
        loadRecommendedSymbols(bundle: bundle)
    }

    private func loadRecommendedSymbols(bundle: Bundle) {
        guard let url = bundle.url(forResource: "recommendedCoins", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let symbols = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }

        let sanitized = symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }

        if !sanitized.isEmpty {
            recommendedSymbols = sanitized
        }
    }

    /// Searches listed coins by symbol or name, ordered by market cap rank.
    func search(_ query: String) -> [CoinMetadata] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return catalog.listed.filter {
            $0.symbol.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }

    func addCoin(_ metadata: CoinMetadata, to settings: inout AppSettings) {
        guard !settings.watchlistCoins.contains(where: { $0.coinId == metadata.id }) else { return }
        // New coins get the default "Change 2%" alert.
        settings.watchlistCoins.append(WatchlistCoin(
            coinId: metadata.id,
            alertKind: .change,
            notificationThreshold: Constants.Defaults.defaultNotificationThreshold
        ))
    }

    func removeCoin(_ coinId: String, from settings: inout AppSettings) {
        settings.watchlistCoins.removeAll { $0.coinId == coinId }
        if settings.displayedCoinId == coinId {
            settings.displayedCoinId = settings.watchlistCoins.first?.coinId ?? "bitcoin"
        }
    }

    func metadata(for coinId: String) -> CoinMetadata? {
        catalog.metadata(for: coinId)
    }
}
