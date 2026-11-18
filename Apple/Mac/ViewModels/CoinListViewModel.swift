import Foundation
import Combine

@MainActor
final class CoinListViewModel: ObservableObject {
    @Published var coins: [Coin] = []
    @Published var isLoading = false
    @Published private var exchangeRate: Double?
    private var alertRules: [String: WatchlistCoin] = [:]

    func usdExchangeRate(for currency: BaseCurrency) -> Double? {
        if currency == .usd { return 1 }
        return currency == priceDataCurrency ? exchangeRate : nil
    }

    private let catalog: CoinCatalog
    private let priceService: PriceServicing
    private let notifier: PriceAlertNotifying
    private var catalogCancellable: AnyCancellable?
    private var settingsViewModel: SettingsViewModel
    /// The poll request in flight; while `isLoading` is true, timer ticks do not start a new one.
    private var fetchCancellable: AnyCancellable?
    private var pollTimer: AnyCancellable?
    /// Display currency of the prices currently shown; when it differs from the settings, old prices are not merged (no wrong-currency values).
    private(set) var priceDataCurrency: BaseCurrency?

    init(
        settingsViewModel: SettingsViewModel,
        catalog: CoinCatalog,
        priceService: PriceServicing = PriceService(exchangeRateService: ExchangeRateService(cacheStore: .appGroup)),
        notifier: PriceAlertNotifying = NotificationService.shared
    ) {
        self.settingsViewModel = settingsViewModel
        self.catalog = catalog
        self.priceService = priceService
        self.notifier = notifier
        loadCoinMetadata()
        startPolling()
        // When the catalog changes (renamed symbols, new successors), rebuild the list and poll with the new symbols.
        catalogCancellable = catalog.$coins
            .dropFirst()
            .sink { [weak self] _ in self?.reloadAfterSettingsChange() }
    }

    /// Restarts polling: drops the request in flight (it may use old settings) and fetches with the current settings right away.
    func startPolling() {
        pollTimer?.cancel()
        cancelInFlightFetch()
        let interval = settingsViewModel.settings.pollingInterval
        pollTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    /// Timer tick: skipped while the previous poll is still running.
    /// Cancelling and restarting on every tick would interrupt failover when sources time out (5 s each), so later sources would never be reached.
    func refresh() {
        guard !isLoading else { return }
        // Coins without a market are left out (otherwise Binance rejects the whole batch every poll).
        let symbols = coins.filter { $0.status == .active }.map { $0.symbol }
        guard !symbols.isEmpty else { return }
        let currency = settingsViewModel.settings.baseCurrency

        isLoading = true
        fetchCancellable = priceService.fetchQuotes(symbols: symbols, currency: currency)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isLoading = false
                self?.fetchCancellable = nil
            }, receiveValue: { [weak self] snapshot in
                guard let self else { return }
                // The display currency changed while this request was in flight: these prices are in the old currency, drop them.
                guard currency == self.settingsViewModel.settings.baseCurrency else { return }
                self.updateCoins(snapshot: snapshot, currency: currency)
            })
    }

    private func cancelInFlightFetch() {
        fetchCancellable?.cancel()
        fetchCancellable = nil
        isLoading = false
    }

    private func updateCoins(snapshot: PriceSnapshot, currency: BaseCurrency) {
        let settings = settingsViewModel.settings
        let sameCurrency = priceDataCurrency == currency
        priceDataCurrency = currency
        if exchangeRate != snapshot.usdToTargetRate { exchangeRate = snapshot.usdToTargetRate }

        let rules = settings.priceChangeNotificationEnabled
            ? Dictionary(settings.watchlistCoins.map { ($0.coinId, $0) }, uniquingKeysWith: { first, _ in first })
            : [:]
        let updatedAt = Date()
        var next = coins
        for i in next.indices {
            let id = next[i].id
            if !sameCurrency {
                next[i].currentPrice = nil
                next[i].priceChange24hPercent = nil
                next[i].lastUpdated = nil
            }
            if !sameCurrency || rules[id] != alertRules[id] {
                next[i].referencePrice = nil
            }
            let symbol = next[i].symbol
            guard let price = snapshot.prices[symbol] else { continue }
            next[i].currentPrice = price
            next[i].priceChange24hPercent = snapshot.changes24h[symbol]
            next[i].lastUpdated = updatedAt
            guard let rule = rules[id], let priceUSD = snapshot.pricesUSD[symbol] else { continue }

            let alertPrice = rule.alertKind == .change ? price : priceUSD
            let reference = next[i].referencePrice
            let change = reference.map { (alertPrice - $0) / $0 * 100 } ?? 0
            if AlertEvaluator.shouldTriggerPriceAlert(
                newPrice: alertPrice, changeFromRef: change, watchlistCoin: rule, referencePrice: reference
            ) {
                notifier.sendPriceAlert(
                    coin: next[i], alertKind: rule.alertKind, threshold: rule.notificationThreshold,
                    changePercent: change, baseCurrency: currency, usdToTargetRate: snapshot.usdToTargetRate
                )
                next[i].referencePrice = alertPrice
            } else {
                AlertEvaluator.updateReferencePriceAfterNoTrigger(coin: &next[i], newPrice: alertPrice, watchlistCoin: rule)
            }
        }
        alertRules = rules
        if coins != next { coins = next }
    }

    /// Whether a metadata reload keeps price, change and reference price (they must be dropped after a currency switch).
    private func shouldPreserveLiveCoinStateWhenReloadingMetadata() -> Bool {
        guard let last = priceDataCurrency else { return true }
        return last == settingsViewModel.settings.baseCurrency
    }

    func loadCoinMetadata() {
        // Old coin ids become their successor first, so the list only ever shows the new coin.
        if let upgraded = catalog.settingsWithSuccessors(settingsViewModel.settings) {
            settingsViewModel.settings = upgraded
        }
        let settings = settingsViewModel.settings
        let oldById = Dictionary(coins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let preserveLive = shouldPreserveLiveCoinStateWhenReloadingMetadata()

        // Build coins in watchlist order to keep the user's ordering. The catalog keeps every id it has ever listed,
        // so missing metadata only happens with a broken catalog; such coins are skipped.
        let next: [Coin] = settings.watchlistCoins.compactMap { watchlistCoin in
            guard let meta = catalog.metadata(for: watchlistCoin.coinId) else { return nil }
            // A changed symbol (rename) means the old price no longer applies.
            let old = preserveLive ? oldById[meta.id].flatMap { $0.symbol == meta.symbol ? $0 : nil } : nil
            let live = meta.status == .active
            return Coin(
                id: meta.id,
                symbol: meta.symbol,
                name: meta.name,
                rank: meta.rank,
                logoAssetName: meta.logoAssetName,
                logoURL: meta.logoURL,
                status: meta.status,
                currentPrice: live ? old?.currentPrice : nil,
                priceChange24hPercent: live ? old?.priceChange24hPercent : nil,
                referencePrice: live ? old?.referencePrice : nil,
                lastUpdated: live ? old?.lastUpdated : nil
            )
        }

        coins = next
        syncDisplayedCoinIdWithWatchlist()
    }

    /// If the menu bar coin is no longer in the watchlist, fall back to the first coin so the picker and the menu bar agree.
    private func syncDisplayedCoinIdWithWatchlist() {
        let ids = settingsViewModel.settings.watchlistCoins.map(\.coinId)
        guard !ids.isEmpty else { return }
        if !ids.contains(settingsViewModel.settings.displayedCoinId) {
            settingsViewModel.settings.displayedCoinId = ids[0]
        }
    }

    func reloadAfterSettingsChange() {
        loadCoinMetadata()
        startPolling()
    }
}
