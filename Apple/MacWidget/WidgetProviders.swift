import Combine
import Foundation
import WidgetKit

struct CoinscalWidgetEntry: TimelineEntry {
    let date: Date
    let content: WidgetEntryContent
}

/// Builds widget content: the app's snapshot while fresh, otherwise prices fetched here (the app may not be running).
/// The price service lives as long as the extension process, so its failover state carries over between reloads.
@MainActor
enum WidgetDataLoader {
    static let catalog = CoinCatalog.bundled()
    private static let priceService = PriceService(exchangeRateService: ExchangeRateService())

    static func content(
        ids: [String], currencyChoice: BaseCurrency?, colorByChange: Bool, sort: WidgetSortOrder,
        snapshot: WidgetSnapshot?
    ) async -> WidgetEntryContent {
        let now = Date()
        let currency = WidgetContent.currency(choice: currencyChoice, snapshot: snapshot)
        let metas = ids.compactMap { catalog.metadata(for: $0) }
        let tradable = metas.filter { $0.status == .active }

        var quotes: [String: WidgetSnapshot.Quote] = [:]
        var updatedAt: Date?
        if let fresh = WidgetContent.freshQuotes(
            snapshot: snapshot, ids: ids, tradable: Set(tradable.map(\.id)), currency: currency, now: now
        ) {
            quotes = fresh
            updatedAt = snapshot?.writtenAt
        } else if let fetched = await fetch(tradable, currency: currency) {
            quotes = fetched
            updatedAt = now
        } else if let snapshot, snapshot.currency == currency {
            // Offline: keep showing the last prices, marked as outdated by their time.
            quotes = snapshot.quotes
            updatedAt = snapshot.writtenAt
        }

        let rows = metas.map { meta in
            WidgetRow(
                id: meta.id, symbol: meta.symbol, name: meta.name, logoAssetName: meta.logoAssetName,
                hasMarket: meta.status == .active,
                price: quotes[meta.id]?.price, change24hPercent: quotes[meta.id]?.change24hPercent
            )
        }
        let defaults = AppSettings()
        return WidgetEntryContent(
            rows: WidgetContent.sorted(rows, by: sort),
            currency: currency,
            updatedAt: quotes.isEmpty ? nil : updatedAt,
            language: snapshot?.language ?? defaults.language,
            colorByChange: colorByChange,
            upColorHex: snapshot?.upColorHex ?? defaults.resolvedUpColorHex,
            downColorHex: snapshot?.downColorHex ?? defaults.resolvedDownColorHex
        )
    }

    /// nil when every source failed.
    private static func fetch(_ coins: [CoinMetadata], currency: BaseCurrency) async -> [String: WidgetSnapshot.Quote]? {
        guard !coins.isEmpty else { return [:] }
        var cancellable: AnyCancellable?
        let result: PriceSnapshot? = await withCheckedContinuation { continuation in
            var resumed = false
            cancellable = priceService.fetchQuotes(symbols: coins.map(\.symbol), currency: currency)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in
                    if !resumed { resumed = true; continuation.resume(returning: nil) }
                }, receiveValue: { value in
                    if !resumed { resumed = true; continuation.resume(returning: value) }
                })
        }
        cancellable?.cancel()
        guard let result else { return nil }
        var quotes: [String: WidgetSnapshot.Quote] = [:]
        for coin in coins {
            guard let price = result.prices[coin.symbol] else { continue }
            quotes[coin.id] = WidgetSnapshot.Quote(price: price, change24hPercent: result.changes24h[coin.symbol])
        }
        return quotes.isEmpty ? nil : quotes
    }

    /// Gallery preview and placeholder: fixed sample prices, no network.
    static func sample(ids: [String]) -> WidgetEntryContent {
        let samples: [String: (Double, Double)] = [
            "bitcoin": (80_585, 2.31), "ethereum": (3_142.18, -1.27), "solana": (152.40, 4.86),
            "binancecoin": (598.20, 0.42), "ripple": (0.5821, -3.05), "dogecoin": (0.1284, 6.12),
            "cardano": (0.4412, -0.88), "tron": (0.1573, 1.04),
        ]
        let rows = ids.compactMap { catalog.metadata(for: $0) }.map { meta in
            WidgetRow(
                id: meta.id, symbol: meta.symbol, name: meta.name, logoAssetName: meta.logoAssetName, hasMarket: true,
                price: samples[meta.id]?.0, change24hPercent: samples[meta.id]?.1
            )
        }
        let defaults = AppSettings()
        return WidgetEntryContent(
            rows: rows, currency: .usd, updatedAt: Date(), language: defaults.language, colorByChange: true,
            upColorHex: defaults.resolvedUpColorHex, downColorHex: defaults.resolvedDownColorHex
        )
    }

    nonisolated static let sampleListIDs = ["bitcoin", "ethereum", "solana", "binancecoin", "ripple", "dogecoin", "cardano", "tron"]
}

private func nextReload(after entry: CoinscalWidgetEntry) -> Date {
    entry.date.addingTimeInterval(WidgetContent.refreshInterval)
}

struct CoinPriceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CoinscalWidgetEntry {
        CoinscalWidgetEntry(date: Date(), content: MainActor.assumeIsolated { WidgetDataLoader.sample(ids: ["bitcoin"]) })
    }

    func snapshot(for configuration: CoinPriceConfigurationIntent, in context: Context) async -> CoinscalWidgetEntry {
        if context.isPreview {
            return CoinscalWidgetEntry(date: Date(), content: await WidgetDataLoader.sample(ids: ["bitcoin"]))
        }
        return await entry(for: configuration)
    }

    func timeline(for configuration: CoinPriceConfigurationIntent, in context: Context) async -> Timeline<CoinscalWidgetEntry> {
        let entry = await entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(nextReload(after: entry)))
    }

    private func entry(for configuration: CoinPriceConfigurationIntent) async -> CoinscalWidgetEntry {
        let snapshot = WidgetSnapshotStore.appGroup.load()
        let id = WidgetContent.priceCoinID(choice: configuration.coin?.id, snapshot: snapshot)
        let content = await WidgetDataLoader.content(
            ids: [id], currencyChoice: configuration.currency.baseCurrency,
            colorByChange: configuration.colorByChange, sort: .watchlist, snapshot: snapshot
        )
        return CoinscalWidgetEntry(date: Date(), content: content)
    }
}

struct WatchlistProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CoinscalWidgetEntry {
        let ids = Array(WidgetDataLoader.sampleListIDs.prefix(Self.limit(context.family)))
        return CoinscalWidgetEntry(date: Date(), content: MainActor.assumeIsolated { WidgetDataLoader.sample(ids: ids) })
    }

    func snapshot(for configuration: WatchlistConfigurationIntent, in context: Context) async -> CoinscalWidgetEntry {
        if context.isPreview {
            let ids = Array(WidgetDataLoader.sampleListIDs.prefix(Self.limit(context.family)))
            return CoinscalWidgetEntry(date: Date(), content: await WidgetDataLoader.sample(ids: ids))
        }
        return await entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: WatchlistConfigurationIntent, in context: Context) async -> Timeline<CoinscalWidgetEntry> {
        let entry = await entry(for: configuration, family: context.family)
        return Timeline(entries: [entry], policy: .after(nextReload(after: entry)))
    }

    private func entry(for configuration: WatchlistConfigurationIntent, family: WidgetFamily) async -> CoinscalWidgetEntry {
        let snapshot = WidgetSnapshotStore.appGroup.load()
        let ids = WidgetContent.listCoinIDs(
            source: configuration.source.source, manual: (configuration.coins ?? []).map(\.id),
            snapshot: snapshot, limit: Self.limit(family)
        )
        let content = await WidgetDataLoader.content(
            ids: ids, currencyChoice: configuration.currency.baseCurrency,
            colorByChange: configuration.colorByChange, sort: configuration.sort.order, snapshot: snapshot
        )
        return CoinscalWidgetEntry(date: Date(), content: content)
    }

    static func limit(_ family: WidgetFamily) -> Int {
        family == .systemLarge ? WidgetContent.largeRowLimit : WidgetContent.mediumRowLimit
    }
}
