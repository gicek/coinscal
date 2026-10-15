import Testing
@testable import Coinscal

@MainActor
@Suite struct CoinListViewModelTests {
    private let settingsVM: SettingsViewModel
    private let prices = FakePriceService()
    private let notifier = SpyNotifier()
    private let vm: CoinListViewModel

    init() {
        var settings = AppSettings()
        settings.baseCurrency = .usd
        settings.priceChangeNotificationEnabled = true
        settings.watchlistCoins = [WatchlistCoin(coinId: "bitcoin", alertKind: .change, notificationThreshold: 2)]
        settingsVM = SettingsViewModel(store: InMemorySettingsStore(settings))
        vm = CoinListViewModel(settingsViewModel: settingsVM, catalog: makeTestCatalog(), priceService: prices, notifier: notifier)
    }

    private var btc: Coin? { vm.coins.first { $0.id == "bitcoin" } }

    @Test func fetchesImmediatelyOnStart() {
        #expect(prices.requests.count == 1)
        #expect(prices.requests[0].symbols == ["BTC"])
        #expect(vm.isLoading)
    }

    /// Regression: a tick must not cancel and restart an unfinished poll, or failover never reaches later sources when they time out.
    @Test func pollTickSkipsWhileRequestInFlight() async {
        vm.refresh()
        #expect(prices.requests.count == 1)

        prices.requests[0].respond(["BTC": 100])
        await drainMainQueue()
        #expect(!vm.isLoading)
        #expect(btc?.currentPrice == 100)

        vm.refresh()
        #expect(prices.requests.count == 2)
    }

    @Test func restartingPollingReplacesInFlightRequest() {
        vm.startPolling()
        #expect(prices.requests.count == 2)
    }

    /// Regression: results requested in the previous display currency must be dropped.
    @Test func dropsSnapshotFetchedInPreviousCurrency() async {
        settingsVM.settings.baseCurrency = .cny
        prices.requests[0].respond(["BTC": 100])
        await drainMainQueue()
        #expect(btc?.currentPrice == nil)
    }

    /// Regression: reference prices reset on a currency switch, otherwise the USD→CNY rate looks like a price move and fires an alert.
    @Test func currencySwitchDoesNotFireBogusChangeAlert() async {
        prices.requests[0].respond(["BTC": 100])
        await drainMainQueue()
        #expect(btc?.referencePrice == 100)

        settingsVM.settings.baseCurrency = .cny
        vm.refresh()
        prices.requests[1].respond(["BTC": 720], rate: 7.2)
        await drainMainQueue()
        #expect(btc?.currentPrice == 720)
        #expect(notifier.calls.isEmpty)

        vm.refresh()
        prices.requests[2].respond(["BTC": 740], rate: 7.2)
        await drainMainQueue()
        #expect(notifier.calls.map(\.coinId) == ["bitcoin"], "a 2.8% move within one currency still alerts")
    }

    @Test func noAlertWhenNotificationsDisabled() async {
        settingsVM.settings.priceChangeNotificationEnabled = false
        prices.requests[0].respond(["BTC": 100])
        await drainMainQueue()
        vm.refresh()
        prices.requests[1].respond(["BTC": 150])
        await drainMainQueue()
        #expect(notifier.calls.isEmpty)
    }

    /// Regression: a price already above the threshold at launch must not alert on every launch; only a new crossing alerts.
    @Test func aboveAlertFiresOnlyOnCrossingNotOnLaunch() async {
        var settings = AppSettings()
        settings.priceChangeNotificationEnabled = true
        settings.watchlistCoins = [WatchlistCoin(coinId: "bitcoin", alertKind: .above, notificationThreshold: 100)]
        let prices = FakePriceService()
        let notifier = SpyNotifier()
        let vm = CoinListViewModel(
            settingsViewModel: SettingsViewModel(store: InMemorySettingsStore(settings)),
            catalog: makeTestCatalog(),
            priceService: prices,
            notifier: notifier
        )

        prices.requests[0].respond(["BTC": 120])
        await drainMainQueue()
        #expect(notifier.calls.isEmpty, "already above the threshold at launch")

        vm.refresh()
        prices.requests[1].respond(["BTC": 95])
        await drainMainQueue()
        vm.refresh()
        prices.requests[2].respond(["BTC": 101])
        await drainMainQueue()
        #expect(notifier.calls.map(\.alertKind) == [.above], "crossed again after dipping below")

        vm.refresh()
        prices.requests[3].respond(["BTC": 130])
        await drainMainQueue()
        #expect(notifier.calls.count == 1, "staying above does not alert again")
    }

    /// Delisted coins stay in the list but are not requested; an old coin id is shown and polled as its successor.
    @Test func inactiveCoinsShownButNotRequested() {
        var settings = AppSettings()
        settings.watchlistCoins = ["bitcoin", "monero", "matic-network"].map { WatchlistCoin(coinId: $0, alertKind: .change, notificationThreshold: 2) }
        let store = InMemorySettingsStore(settings)
        let prices = FakePriceService()
        let vm = CoinListViewModel(
            settingsViewModel: SettingsViewModel(store: store),
            catalog: makeTestCatalog(),
            priceService: prices,
            notifier: SpyNotifier()
        )
        #expect(vm.coins.map(\.id) == ["bitcoin", "monero", "polygon-ecosystem-token"])
        #expect(vm.coins.map(\.symbol) == ["BTC", "XMR", "POL"])
        #expect(vm.coins.map(\.status) == [.active, .delisted, .active])
        #expect(store.stored?.watchlistCoins.map(\.coinId) == ["bitcoin", "monero", "polygon-ecosystem-token"], "the swap is saved")
        #expect(prices.requests.map(\.symbols) == [["BTC", "POL"]])
    }
}
