import Foundation
import Testing
@testable import Coinscal

@MainActor
@Suite struct CoinCatalogTests {
    /// A valid catalog exactly at the listed-count minimum; each case changes one thing.
    private func validCoins() -> [CoinMetadata] {
        [catalogCoin("bitcoin", "BTC", rank: 1), catalogCoin("ethereum", "ETH", rank: 2)]
            + (3...CoinCatalog.listedRange.lowerBound).map { catalogCoin("coin-\($0)", "C\($0)", rank: $0) }
    }

    private func problems(_ coins: [CoinMetadata], schema: Int = CoinCatalog.schemaVersion) -> [String] {
        CoinCatalog.validate(schemaVersion: schema, coins: coins)
    }

    /// The bundled snapshot must pass the client validation (mirrors the Python validation in make test-mac).
    @Test func bundledCatalogIsValid() throws {
        let url = try #require(Bundle.main.url(forResource: "coins", withExtension: "json"))
        let coins = try CoinCatalog.decodeValidated(Data(contentsOf: url))
        #expect(coins.filter(\.listed).count >= CoinCatalog.listedRange.lowerBound)
        let catalog = CoinCatalog.bundled()
        #expect(catalog.metadata(for: "bitcoin")?.logoAssetName == "coin-bitcoin", "bundled logo is preferred")
    }

    @Test func acceptsValidCatalog() {
        #expect(problems(validCoins()).isEmpty)
    }

    @Test func rejectsUnsafeOrInconsistentCatalogs() {
        #expect(!problems(validCoins(), schema: 2).isEmpty, "unknown schema")
        #expect(!problems(validCoins().filter { $0.id != "bitcoin" }).isEmpty, "missing bitcoin")
        #expect(!problems(Array(validCoins().dropLast())).isEmpty, "too few listed coins")
        #expect(!problems(validCoins() + [catalogCoin("evil", "EVIL", logoURL: "https://tracker.example/x.png")]).isEmpty, "logo host not allowed")
        #expect(!problems(validCoins() + [catalogCoin("btc-copy", "BTC", listed: false)]).isEmpty, "duplicate tradable symbol would mix up prices")
        #expect(!problems(validCoins() + [catalogCoin("old", "OLD", status: .delisted)]).isEmpty, "a delisted coin cannot be listed")
        #expect(!problems(validCoins() + [catalogCoin("bad id", "BAD", listed: false)]).isEmpty, "invalid id characters")
        #expect(!problems(validCoins() + [catalogCoin("migrated", "OLD", status: .migrated, listed: false, migratedTo: "nowhere")]).isEmpty, "migration target missing")
        let deadTarget = [catalogCoin("dead", "DEAD", status: .delisted, listed: false),
                          catalogCoin("migrated", "OLD", status: .migrated, listed: false, migratedTo: "dead")]
        #expect(!problems(validCoins() + deadTarget).isEmpty, "migration target not tradable")
    }

    @Test func sortsByRankAndExposesOnlyListedForSearch() {
        let catalog = makeTestCatalog()
        #expect(catalog.coins.first?.id == "bitcoin")
        #expect(catalog.coins.last?.rank == nil, "unranked coins sort last")
        #expect(catalog.listed.map(\.id) == ["bitcoin", "ethereum", "render-token"])
        #expect(catalog.metadata(for: "monero")?.status == .delisted, "unlisted entries are still found by id")
    }

    // MARK: Old coin ids are swapped for their successor

    private func settings(_ coins: [WatchlistCoin], displayed: String = "bitcoin") -> AppSettings {
        var settings = AppSettings()
        settings.watchlistCoins = coins
        settings.displayedCoinId = displayed
        return settings
    }

    @Test func successorKeepsPositionAndChangeAlert() throws {
        let s = try #require(makeTestCatalog().settingsWithSuccessors(settings([
            WatchlistCoin(coinId: "bitcoin", alertKind: .change, notificationThreshold: 2),
            WatchlistCoin(coinId: "matic-network", alertKind: .change, notificationThreshold: 5),
            WatchlistCoin(coinId: "ethereum", alertKind: .change, notificationThreshold: 2),
        ], displayed: "matic-network")))
        #expect(s.watchlistCoins.map(\.coinId) == ["bitcoin", "polygon-ecosystem-token", "ethereum"])
        #expect(s.watchlistCoins[1].alertKind == .change)
        #expect(s.watchlistCoins[1].notificationThreshold == 5)
        #expect(s.displayedCoinId == "polygon-ecosystem-token", "the menu bar coin follows")
    }

    /// Above/Below thresholds are prices of the old coin and not comparable with the new one.
    @Test func successorResetsPriceLevelAlert() throws {
        let s = try #require(makeTestCatalog().settingsWithSuccessors(
            settings([WatchlistCoin(coinId: "matic-network", alertKind: .above, notificationThreshold: 0.9)])))
        #expect(s.watchlistCoins[0].alertKind == .change)
        #expect(s.watchlistCoins[0].notificationThreshold == Constants.Defaults.defaultNotificationThreshold)
    }

    @Test func successorAlreadyAddedOnlyRemovesOld() throws {
        let s = try #require(makeTestCatalog().settingsWithSuccessors(settings([
            WatchlistCoin(coinId: "polygon-ecosystem-token", alertKind: .below, notificationThreshold: 0.2),
            WatchlistCoin(coinId: "matic-network", alertKind: .change, notificationThreshold: 2),
        ])))
        #expect(s.watchlistCoins.map(\.coinId) == ["polygon-ecosystem-token"])
        #expect(s.watchlistCoins[0].alertKind == .below, "settings of the already-added new coin are kept")
    }

    @Test func noSuccessorMeansNoChange() {
        let catalog = makeTestCatalog()
        #expect(catalog.settingsWithSuccessors(settings([WatchlistCoin(coinId: "monero"), WatchlistCoin(coinId: "bitcoin")])) == nil)
    }
}
