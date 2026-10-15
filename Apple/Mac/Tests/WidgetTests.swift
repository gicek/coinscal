import Foundation
import Testing
@testable import Coinscal

/// Widget rules (docs/WIDGET.md). The snapshot store only ever uses a temporary directory, never the App Group.
@MainActor
@Suite struct WidgetTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        writtenAgo: TimeInterval = 60, currency: BaseCurrency = .usd, displayed: String = "ethereum",
        watchlist: [String] = ["bitcoin", "ethereum", "solana"],
        quotes: [String: WidgetSnapshot.Quote] = ["bitcoin": .init(price: 80_000, change24hPercent: 2)]
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            writtenAt: now.addingTimeInterval(-writtenAgo), language: .zhHans, currency: currency, colorByChange: true,
            upColorHex: "#2CBD84", downColorHex: "#F6465D", displayedCoinId: displayed, watchlist: watchlist, quotes: quotes
        )
    }

    private func row(_ id: String, change: Double?) -> WidgetRow {
        WidgetRow(id: id, symbol: id.uppercased(), name: id, logoAssetName: nil, hasMarket: true, price: 1, change24hPercent: change)
    }

    // MARK: Coin choice

    @Test func priceCoinFollowsMenuBarByDefault() {
        #expect(WidgetContent.priceCoinID(choice: nil, snapshot: snapshot()) == "ethereum")
        #expect(WidgetContent.priceCoinID(choice: WidgetContent.followMenuBarCoinID, snapshot: snapshot()) == "ethereum")
        #expect(WidgetContent.priceCoinID(choice: "solana", snapshot: snapshot()) == "solana")
        #expect(WidgetContent.priceCoinID(choice: nil, snapshot: nil) == AppSettings().displayedCoinId, "before the app has run")
    }

    @Test func listUsesWatchlistOrderUpToTheLimit() {
        #expect(WidgetContent.listCoinIDs(source: .watchlist, manual: [], snapshot: snapshot(), limit: 2) == ["bitcoin", "ethereum"])
        #expect(WidgetContent.listCoinIDs(source: .watchlist, manual: ["solana"], snapshot: snapshot(), limit: 4)
                == ["bitcoin", "ethereum", "solana"], "manual coins are ignored for the watchlist source")
        #expect(WidgetContent.listCoinIDs(source: .watchlist, manual: [], snapshot: nil, limit: 4)
                == AppSettings().watchlistCoins.map(\.coinId))
    }

    @Test func manualListDropsDuplicatesAndFallsBackWhenEmpty() {
        #expect(WidgetContent.listCoinIDs(source: .manual, manual: ["solana", "bitcoin", "solana"], snapshot: snapshot(), limit: 4)
                == ["solana", "bitcoin"])
        #expect(WidgetContent.listCoinIDs(source: .manual, manual: [], snapshot: snapshot(), limit: 4)
                == ["bitcoin", "ethereum", "solana"])
    }

    @Test func currencyFollowsAppUnlessChosen() {
        #expect(WidgetContent.currency(choice: nil, snapshot: snapshot(currency: .cny)) == .cny)
        #expect(WidgetContent.currency(choice: .eur, snapshot: snapshot(currency: .cny)) == .eur)
        #expect(WidgetContent.currency(choice: nil, snapshot: nil) == AppSettings().baseCurrency)
    }

    // MARK: Snapshot freshness

    @Test func freshSnapshotIsUsedWithoutFetching() {
        let quotes = WidgetContent.freshQuotes(snapshot: snapshot(), ids: ["bitcoin", "monero"], tradable: ["bitcoin"], currency: .usd, now: now)
        #expect(quotes?["bitcoin"]?.price == 80_000, "coins without a market need no quote")
    }

    @Test func snapshotNotUsableTriggersFetch() {
        let tradable: Set<String> = ["bitcoin"]
        #expect(WidgetContent.freshQuotes(snapshot: snapshot(writtenAgo: 16 * 60), ids: ["bitcoin"], tradable: tradable, currency: .usd, now: now) == nil,
                "older than 15 minutes")
        #expect(WidgetContent.freshQuotes(snapshot: snapshot(), ids: ["bitcoin"], tradable: tradable, currency: .eur, now: now) == nil,
                "other currency")
        #expect(WidgetContent.freshQuotes(snapshot: snapshot(), ids: ["bitcoin", "ethereum"], tradable: ["bitcoin", "ethereum"], currency: .usd, now: now) == nil,
                "a tradable coin is missing")
        #expect(WidgetContent.freshQuotes(snapshot: nil, ids: ["bitcoin"], tradable: tradable, currency: .usd, now: now) == nil)
    }

    @Test func pricesOlderThan30MinutesAreStale() {
        var content = WidgetEntryContent(rows: [], currency: .usd, updatedAt: now.addingTimeInterval(-29 * 60), language: .en,
                                         colorByChange: true, upColorHex: "", downColorHex: "")
        #expect(!content.isStale(at: now))
        content.updatedAt = now.addingTimeInterval(-31 * 60)
        #expect(content.isStale(at: now))
        content.updatedAt = nil
        #expect(!content.isStale(at: now), "no prices is the empty state, not outdated")
    }

    // MARK: Sorting

    @Test func sortByChangeKeepsCoinsWithoutChangeLast() {
        let rows = [row("a", change: 1), row("b", change: nil), row("c", change: 5), row("d", change: -2), row("e", change: 1)]
        #expect(WidgetContent.sorted(rows, by: .watchlist).map(\.id) == ["a", "b", "c", "d", "e"])
        #expect(WidgetContent.sorted(rows, by: .changeDescending).map(\.id) == ["c", "a", "e", "d", "b"])
        #expect(WidgetContent.sorted(rows, by: .changeAscending).map(\.id) == ["d", "a", "e", "c", "b"])
    }

    // MARK: Store

    @Test func storeRoundTripsAndToleratesBadFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WidgetSnapshotStore(directory: dir)
        #expect(store.load() == nil)
        try store.save(snapshot())
        #expect(store.load() == snapshot())
        try Data("{".utf8).write(to: dir.appendingPathComponent(WidgetSnapshotStore.fileName))
        #expect(store.load() == nil, "unreadable file: the widget fetches by itself")

        let noGroup = WidgetSnapshotStore(directory: nil)
        try noGroup.save(snapshot())
        #expect(noGroup.load() == nil, "unsigned build without App Group: no-op")
    }

    // MARK: Writer

    @Test func snapshotHoldsActivePricesAndResolvedColors() {
        var settings = AppSettings()
        settings.colorScheme = .redUpGreenDown
        settings.watchlistCoins = ["bitcoin", "ethereum", "monero"].map { WatchlistCoin(coinId: $0) }
        let coins = [
            Coin(id: "bitcoin", symbol: "BTC", name: "Bitcoin", rank: 1, logoAssetName: nil, logoURL: nil,
                 currentPrice: 80_000, priceChange24hPercent: 1.5),
            Coin(id: "ethereum", symbol: "ETH", name: "Ethereum", rank: 2, logoAssetName: nil, logoURL: nil),
            Coin(id: "monero", symbol: "XMR", name: "Monero", rank: nil, logoAssetName: nil, logoURL: nil, status: .delisted, currentPrice: 1),
        ]
        let s = WidgetSnapshotWriter.makeSnapshot(coins: coins, settings: settings, at: now)
        #expect(Array(s.quotes.keys) == ["bitcoin"], "unpriced and delisted coins are left out")
        #expect(s.watchlist == ["bitcoin", "ethereum", "monero"])
        #expect(s.upColorHex == Constants.Defaults.downColorHex, "red up, green down")
        #expect(s.downColorHex == Constants.Defaults.upColorHex)
    }

    @Test func reloadIsThrottledUnlessSomethingVisibleChanges() {
        let base = snapshot(writtenAgo: 0)
        let reloadedAt = now
        func later(_ seconds: TimeInterval, _ change: (inout WidgetSnapshot) -> Void = { _ in }) -> WidgetSnapshot {
            var next = base
            next.writtenAt = now.addingTimeInterval(seconds)
            change(&next)
            return next
        }
        #expect(WidgetSnapshotWriter.needsReload(previous: nil, lastReloadAt: nil, next: base), "first write")
        #expect(!WidgetSnapshotWriter.needsReload(previous: base, lastReloadAt: reloadedAt, next: later(60)))
        #expect(WidgetSnapshotWriter.needsReload(previous: base, lastReloadAt: reloadedAt, next: later(5 * 60)), "5 minutes passed")
        #expect(!WidgetSnapshotWriter.needsReload(previous: base, lastReloadAt: reloadedAt,
                                                  next: later(60) { $0.quotes["bitcoin"]?.price = 80_700 }), "0.875% move")
        #expect(WidgetSnapshotWriter.needsReload(previous: base, lastReloadAt: reloadedAt,
                                                 next: later(60) { $0.quotes["bitcoin"]?.price = 81_000 }), "1.25% move")
        #expect(WidgetSnapshotWriter.needsReload(previous: base, lastReloadAt: reloadedAt, next: later(60) { $0.currency = .cny }))
        #expect(WidgetSnapshotWriter.needsReload(previous: base, lastReloadAt: reloadedAt, next: later(60) { $0.displayedCoinId = "solana" }))
        #expect(WidgetSnapshotWriter.needsReload(previous: base, lastReloadAt: reloadedAt, next: later(60) { $0.language = .en }))
    }

    @Test func writerSavesEveryTimeButReloadsOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var reloads = 0
        var clock = now
        let writer = WidgetSnapshotWriter(store: WidgetSnapshotStore(directory: dir), reloadWidgets: { reloads += 1 }, now: { clock })
        writer.write(coins: [], settings: AppSettings())
        clock = clock.addingTimeInterval(30)
        writer.write(coins: [], settings: AppSettings())
        #expect(reloads == 1)
        #expect(WidgetSnapshotStore(directory: dir).load()?.writtenAt == clock, "the snapshot itself is always current")
    }

    // MARK: Localization

    /// The edit panel and gallery read their texts by key from the String Catalog; every key used by widget code must
    /// be translated (the i18n guard only checks `Text("…")` calls).
    @Test func widgetKeysAreTranslated() throws {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONSerialization.jsonObject(
            with: Data(contentsOf: apple.appendingPathComponent("Mac/Resources/Localizable.xcstrings"))
        ) as? [String: Any]
        let strings = catalog?["strings"] as? [String: [String: Any]] ?? [:]
        let dirs = ["MacWidget", "Mac/Shared"].map { apple.appendingPathComponent($0) }
        var keys = Set<String>()
        for dir in dirs {
            for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for match in text.matches(of: #/"(widget\.[A-Za-z.]+|coin\.status\.[A-Za-z]+)"/#) { keys.insert(String(match.1)) }
            }
        }
        #expect(keys.count > 15, "scanned the widget sources")
        for key in keys.sorted() {
            let localizations = strings[key]?["localizations"] as? [String: Any]
            for lang in ["en", "zh-Hans", "zh-Hant"] {
                #expect(localizations?[lang] != nil, "\(key) missing \(lang)")
            }
        }
    }
}
