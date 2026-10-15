import Foundation
import Combine
import OSLog
import WidgetKit

/// Hands prices and display settings to the widgets (docs/WIDGET.md). The snapshot is written after every update;
/// WidgetKit is asked to reload at most every 5 minutes, sooner when a price moves more than 1% or a setting the
/// widgets show changes. The system may merge reloads further (it budgets them per widget).
@MainActor
final class WidgetSnapshotWriter {
    static let reloadInterval: TimeInterval = 5 * 60
    static let significantMovePercent = 1.0
    private static let logger = Logger(subsystem: "com.gicek.coinscal", category: "Widget")

    private let store: WidgetSnapshotStore
    private let reloadWidgets: () -> Void
    private let now: () -> Date
    /// Snapshot as of the last reload request, to compare against.
    private var lastReload: (at: Date, snapshot: WidgetSnapshot)?
    private var cancellable: AnyCancellable?

    init(
        store: WidgetSnapshotStore = .appGroup,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.reloadWidgets = reloadWidgets
        self.now = now
    }

    func bind(coinListVM: CoinListViewModel, settingsVM: SettingsViewModel) {
        cancellable = Publishers.CombineLatest(coinListVM.$coins, settingsVM.$settings)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] coins, settings in
                self?.write(coins: coins, settings: settings)
            }
    }

    func write(coins: [Coin], settings: AppSettings) {
        let snapshot = Self.makeSnapshot(coins: coins, settings: settings, at: now())
        do {
            try store.save(snapshot)
        } catch {
            Self.logger.error("Widget snapshot not written: \(error.localizedDescription, privacy: .public)")
            return
        }
        if Self.needsReload(previous: lastReload?.snapshot, lastReloadAt: lastReload?.at, next: snapshot) {
            reloadWidgets()
            lastReload = (snapshot.writtenAt, snapshot)
        }
    }

    static func makeSnapshot(coins: [Coin], settings: AppSettings, at date: Date) -> WidgetSnapshot {
        var quotes: [String: WidgetSnapshot.Quote] = [:]
        for coin in coins where coin.status == .active {
            guard let price = coin.currentPrice else { continue }
            quotes[coin.id] = WidgetSnapshot.Quote(price: price, change24hPercent: coin.priceChange24hPercent)
        }
        return WidgetSnapshot(
            writtenAt: date,
            language: settings.language,
            currency: settings.baseCurrency,
            colorByChange: settings.priceColorEnabled,
            upColorHex: settings.resolvedUpColorHex,
            downColorHex: settings.resolvedDownColorHex,
            displayedCoinId: settings.displayedCoinId,
            watchlist: settings.watchlistCoins.map(\.coinId),
            quotes: quotes
        )
    }

    static func needsReload(previous: WidgetSnapshot?, lastReloadAt: Date?, next: WidgetSnapshot) -> Bool {
        guard let previous, let lastReloadAt else { return true }
        if next.writtenAt.timeIntervalSince(lastReloadAt) >= reloadInterval { return true }
        if previous.language != next.language || previous.currency != next.currency
            || previous.colorByChange != next.colorByChange
            || previous.upColorHex != next.upColorHex || previous.downColorHex != next.downColorHex
            || previous.displayedCoinId != next.displayedCoinId || previous.watchlist != next.watchlist {
            return true
        }
        for (id, quote) in next.quotes {
            guard let old = previous.quotes[id] else { return true }
            if old.price > 0, abs(quote.price - old.price) / old.price * 100 > significantMovePercent { return true }
        }
        return false
    }
}
