import Foundation
import Combine
import OSLog
import WidgetKit

/// Hands prices and display settings to the desktop and Notification Center widgets (docs/WIDGET.md). It has nothing
/// to do with the menu bar or the desktop ticker, which follow the app's own polling.
///
/// - The widgets refresh on their own timeline (`WidgetContent.refreshInterval`); the app never asks for periodic or
///   price-driven reloads. Those counted against the system's daily reload budget, and once it ran out the widgets
///   stopped updating until it recovered.
/// - While widgets are placed, the snapshot is written after every update, so a widget reload uses current prices
///   without a request. A reload is requested only when a setting the widgets show changes.
/// - With no widget placed, only those settings are written (a widget added later shows the right coins, currency,
///   and language at once and fetches its own prices); nothing is reloaded.
@MainActor
final class WidgetSnapshotWriter {
    /// How long a "widgets placed" answer from WidgetKit is reused before asking again.
    static let installedCheckInterval: TimeInterval = 5 * 60
    private static let logger = Logger(subsystem: "com.gicek.coinscal", category: "Widget")

    /// Reports whether any desktop or Notification Center widget is placed.
    typealias InstalledCheck = (@escaping @MainActor (Bool) -> Void) -> Void

    private let store: WidgetSnapshotStore
    private let reloadWidgets: () -> Void
    private let checkInstalled: InstalledCheck
    private let now: () -> Date
    /// The last snapshot saved to the store.
    private var lastSaved: WidgetSnapshot?
    /// The newest snapshot, saved or not, so it can be written as soon as a widget appears.
    private var latest: WidgetSnapshot?
    /// nil until WidgetKit has answered.
    private var widgetsInstalled: Bool?
    private var installedCheckedAt: Date?
    private var isCheckingInstalled = false
    private var cancellable: AnyCancellable?

    init(
        store: WidgetSnapshotStore = .appGroup,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        checkInstalled: @escaping InstalledCheck = WidgetSnapshotWriter.systemInstalledCheck,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.reloadWidgets = reloadWidgets
        self.checkInstalled = checkInstalled
        self.now = now
    }

    /// Asks WidgetKit for the placed widgets. An error counts as placed, so the widgets keep current data.
    nonisolated static func systemInstalledCheck(_ completion: @escaping @MainActor (Bool) -> Void) {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let installed = (try? result.get()).map { !$0.isEmpty } ?? true
            Task { @MainActor in completion(installed) }
        }
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
        latest = snapshot
        refreshInstalledIfNeeded()
        apply(Self.plan(previous: lastSaved, next: snapshot, widgetsInstalled: widgetsInstalled), snapshot)
    }

    private func apply(_ plan: Plan, _ snapshot: WidgetSnapshot) {
        guard plan.save else { return }
        do {
            try store.save(snapshot)
        } catch {
            Self.logger.error("Widget snapshot not written: \(error.localizedDescription, privacy: .public)")
            return
        }
        lastSaved = snapshot
        if plan.reload { reloadWidgets() }
    }

    private func refreshInstalledIfNeeded() {
        guard !isCheckingInstalled else { return }
        if let installedCheckedAt, now().timeIntervalSince(installedCheckedAt) < Self.installedCheckInterval { return }
        isCheckingInstalled = true
        checkInstalled { [weak self] installed in
            guard let self else { return }
            self.isCheckingInstalled = false
            self.installedCheckedAt = self.now()
            let appeared = installed && self.widgetsInstalled != true
            self.widgetsInstalled = installed
            // A widget was just added (or the app just launched): hand it the latest prices. The system already
            // loaded the new widget's timeline, so no reload is requested.
            if appeared, let latest = self.latest, latest != self.lastSaved {
                self.apply(Plan(save: true, reload: false), latest)
            }
        }
    }

    struct Plan: Equatable {
        var save: Bool
        var reload: Bool
    }

    /// Prices are written only while widgets are placed; widget-visible settings always are. A reload is requested
    /// only for a settings change while widgets are known to be placed (not for the first write after launch).
    static func plan(previous: WidgetSnapshot?, next: WidgetSnapshot, widgetsInstalled: Bool?) -> Plan {
        guard let previous else { return Plan(save: true, reload: false) }
        let settingsChanged = visibleSettingsChanged(previous, next)
        return Plan(save: settingsChanged || widgetsInstalled == true, reload: settingsChanged && widgetsInstalled == true)
    }

    static func visibleSettingsChanged(_ a: WidgetSnapshot, _ b: WidgetSnapshot) -> Bool {
        a.language != b.language || a.currency != b.currency || a.colorByChange != b.colorByChange
            || a.upColorHex != b.upColorHex || a.downColorHex != b.downColorHex
            || a.displayedCoinId != b.displayedCoinId || a.watchlist != b.watchlist
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
}
