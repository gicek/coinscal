import Testing
@testable import Coinscal

@MainActor
@Suite struct WatchlistViewModelTests {
    private let vm = WatchlistViewModel(catalog: makeTestCatalog())

    private func settings(_ coins: [WatchlistCoin], displayed: String = "bitcoin") -> AppSettings {
        var settings = AppSettings()
        settings.watchlistCoins = coins
        settings.displayedCoinId = displayed
        return settings
    }

    @Test func searchAndRecommendationsUseListedCoinsOnly() {
        #expect(vm.search("ren").map(\.id) == ["render-token"])
        #expect(vm.search("pol").isEmpty, "unlisted coins are not searchable")
        #expect(vm.search("xmr").isEmpty)
        #expect(vm.recommendedCoins.map(\.symbol) == ["BTC", "ETH"], "unlisted coins in the recommendations are skipped")
    }

    @Test func addCoinResultsListAllListedCoinsUntilAQueryIsTyped() {
        let browse = vm.addCoinResults
        #expect(browse.allSatisfy { $0.listed }, "the add-coin panel browses listed coins only")
        #expect(browse.map(\.id).contains("render-token"))
        #expect(!browse.map(\.id).contains("polygon-ecosystem-token"))

        vm.searchText = "  ren "
        #expect(vm.addCoinResults.map(\.id) == ["render-token"], "results follow the text without a debounce")
        vm.searchText = "   "
        #expect(vm.addCoinResults.map(\.id) == browse.map(\.id), "a blank query browses again")
    }
}
