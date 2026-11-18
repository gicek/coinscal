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
    private static let priceService = PriceService(exchangeRateService: ExchangeRateService(cacheStore: .appGroup))

    static func content(
        ids: [String], currencyChoice: BaseCurrency?, colorByChange: Bool, sort: WidgetSortOrder,
        snapshot: WidgetSnapshot?, fetchTimeout: TimeInterval = WidgetContent.fetchTimeout
    ) async -> WidgetEntryContent {
        let now = Date()
        let changeBasis = snapshot?.priceChangeBasis ?? .rolling24h
        let currency = WidgetContent.currency(choice: currencyChoice, snapshot: snapshot)
        let metas = ids.compactMap { catalog.metadata(for: $0) }
        let tradable = metas.filter { $0.status == .active }

        let cached = snapshot.flatMap { $0.currency == currency ? $0 : nil }
        let tradableIDs = Set(tradable.map(\.id))
        let quotes: [String: WidgetSnapshot.Quote]
        if let fresh = WidgetContent.freshQuotes(snapshot: cached, ids: ids, tradable: tradableIDs, currency: currency, now: now) {
            quotes = fresh
        } else {
            let previous = cached?.quotes.filter { tradableIDs.contains($0.key) } ?? [:]
            let fetched = await fetch(tradable, currency: currency, changeBasis: changeBasis, timeout: fetchTimeout) ?? [:]
            quotes = previous.merging(fetched) { _, current in current }
        }
        let updatedAt = quotes.values.compactMap { $0.fetchedAt ?? cached?.writtenAt }.min()
        let displayedAt = Date()

        let rows = metas.map { meta in
            let quote = quotes[meta.id]
            let change = changeBasis.includes(quote?.fetchedAt, at: displayedAt) ? quote?.changePercent : nil
            return WidgetRow(
                id: meta.id, symbol: meta.symbol, name: meta.name, logoAssetName: meta.logoAssetName,
                hasMarket: meta.status == .active,
                price: quote?.price, changePercent: change, fetchedAt: quote?.fetchedAt
            )
        }
        let defaults = AppSettings()
        return WidgetEntryContent(
            rows: WidgetContent.sorted(rows, by: sort),
            currency: currency,
            updatedAt: updatedAt,
            language: snapshot?.language ?? defaults.language,
            colorByChange: colorByChange,
            upColorHex: snapshot?.upColorHex ?? defaults.resolvedUpColorHex,
            downColorHex: snapshot?.downColorHex ?? defaults.resolvedDownColorHex,
            changeBasis: changeBasis
        )
    }

    /// nil when every source failed or the request took longer than `timeout`.
    private static func fetch(
        _ coins: [CoinMetadata], currency: BaseCurrency, changeBasis: PriceChangeBasis, timeout: TimeInterval
    ) async -> [String: WidgetSnapshot.Quote]? {
        guard !coins.isEmpty else { return [:] }
        var cancellable: AnyCancellable?
        let result: PriceSnapshot? = await withCheckedContinuation { continuation in
            var resumed = false
            cancellable = priceService.fetchQuotes(
                symbols: coins.map(\.symbol), currency: currency,
                changeBasis: changeBasis, deadline: Date().addingTimeInterval(timeout)
            )
                .receive(on: DispatchQueue.main)
                // Finishes without a value on timeout, which resumes with nil below.
                .timeout(.seconds(timeout), scheduler: DispatchQueue.main)
                .sink(receiveCompletion: { _ in
                    if !resumed { resumed = true; continuation.resume(returning: nil) }
                }, receiveValue: { value in
                    if !resumed { resumed = true; continuation.resume(returning: value) }
                })
        }
        cancellable?.cancel()
        guard let result else { return nil }
        let fetchedAt = Date()
        let validWindow = changeBasis.dayStart(at: fetchedAt) == result.changeDayStart
        var quotes: [String: WidgetSnapshot.Quote] = [:]
        for coin in coins {
            guard let price = result.prices[coin.symbol] else { continue }
            quotes[coin.id] = WidgetSnapshot.Quote(
                price: price, changePercent: validWindow ? result.priceChanges[coin.symbol] : nil, fetchedAt: fetchedAt
            )
        }
        return quotes.isEmpty ? nil : quotes
    }

    /// Gallery preview: the user's coins and settings with real prices (the app's snapshot while fresh, otherwise one
    /// request limited to `WidgetContent.previewFetchTimeout`); the fixed samples when no price could be had.
    static func preview(ids: [String], sampleIDs: [String]) async -> WidgetEntryContent {
        let snapshot = WidgetSnapshotStore.appGroup.load()
        let content = await content(
            ids: ids, currencyChoice: nil, colorByChange: snapshot?.colorByChange ?? AppSettings().priceColorEnabled,
            sort: .watchlist, snapshot: snapshot, fetchTimeout: WidgetContent.previewFetchTimeout
        )
        return content.hasPrices ? content : sample(ids: sampleIDs)
    }

    /// Placeholder, and the preview's fallback: fixed sample prices, no network.
    static func sample(ids: [String]) -> WidgetEntryContent {
        let samples: [String: (Double, Double)] = [
            "bitcoin": (80_585, 2.31), "ethereum": (3_142.18, -1.27), "solana": (152.40, 4.86),
            "binancecoin": (598.20, 0.42), "ripple": (0.5821, -3.05), "dogecoin": (0.1284, 6.12),
            "cardano": (0.4412, -0.88), "tron": (0.1573, 1.04),
        ]
        let rows = ids.compactMap { catalog.metadata(for: $0) }.map { meta in
            WidgetRow(
                id: meta.id, symbol: meta.symbol, name: meta.name, logoAssetName: meta.logoAssetName, hasMarket: true,
                price: samples[meta.id]?.0, changePercent: samples[meta.id]?.1, fetchedAt: Date()
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

private func priceTimeline(startingWith entry: CoinscalWidgetEntry) -> Timeline<CoinscalWidgetEntry> {
    let regular = entry.date.addingTimeInterval(WidgetContent.refreshInterval)
    guard let start = entry.content.changeBasis.dayStart(at: entry.date) else {
        return Timeline(entries: [entry], policy: .after(regular))
    }
    let midnight = start.addingTimeInterval(86_400)
    // The view uses the entry's date to hide expired changes even if WidgetKit delays the next fetch.
    let rollover = CoinscalWidgetEntry(date: midnight, content: entry.content)
    return Timeline(entries: [entry, rollover], policy: .after(min(regular, midnight)))
}

struct CoinPriceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CoinscalWidgetEntry {
        CoinscalWidgetEntry(date: Date(), content: MainActor.assumeIsolated { WidgetDataLoader.sample(ids: ["bitcoin"]) })
    }

    func snapshot(for configuration: CoinPriceConfigurationIntent, in context: Context) async -> CoinscalWidgetEntry {
        if context.isPreview {
            let id = WidgetContent.priceCoinID(choice: nil, snapshot: WidgetSnapshotStore.appGroup.load())
            return CoinscalWidgetEntry(date: Date(), content: await WidgetDataLoader.preview(ids: [id], sampleIDs: ["bitcoin"]))
        }
        return await entry(for: configuration)
    }

    func timeline(for configuration: CoinPriceConfigurationIntent, in context: Context) async -> Timeline<CoinscalWidgetEntry> {
        let entry = await entry(for: configuration)
        return priceTimeline(startingWith: entry)
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
            let limit = Self.limit(context.family)
            let ids = WidgetContent.listCoinIDs(
                source: .watchlist, manual: [], snapshot: WidgetSnapshotStore.appGroup.load(), limit: limit
            )
            let sampleIDs = Array(WidgetDataLoader.sampleListIDs.prefix(limit))
            return CoinscalWidgetEntry(date: Date(), content: await WidgetDataLoader.preview(ids: ids, sampleIDs: sampleIDs))
        }
        return await entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: WatchlistConfigurationIntent, in context: Context) async -> Timeline<CoinscalWidgetEntry> {
        let entry = await entry(for: configuration, family: context.family)
        return priceTimeline(startingWith: entry)
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
