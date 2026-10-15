import Foundation
import Testing
@testable import Coinscal

@Suite struct AppSettingsCodingTests {
    private func decode(_ string: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: json(string))
    }

    /// Regression: missing fields in older data fall back individually; the watchlist must not be reset.
    @Test func missingFieldsFallBackIndividually() throws {
        let settings = try decode(#"{"baseCurrency":"CNY","addedCoins":[{"coinId":"solana"}]}"#)
        #expect(settings.baseCurrency == .cny)
        #expect(settings.watchlistCoins.map(\.coinId) == ["solana"])
        #expect(settings.watchlistCoins[0].alertKind == .change)
        #expect(settings.watchlistCoins[0].notificationThreshold == Constants.Defaults.defaultNotificationThreshold)
        #expect(settings.pollingInterval == Constants.Defaults.pollingInterval)
        #expect(settings.launchAtLogin == AppSettings().launchAtLogin)
    }

    /// Regression: an unknown enum value (data written by a newer version) only affects that field.
    @Test func unknownEnumValuesFallBack() throws {
        let settings = try decode("""
        {"baseCurrency":"XYZ","language":"fr","colorScheme":"rainbow",
         "addedCoins":[{"coinId":"bitcoin","alertKind":"someday"},42,{"coinId":"ethereum","alertKind":"above","notificationThreshold":5000}]}
        """)
        #expect(settings.baseCurrency == .usd)
        #expect(settings.language == .system)
        #expect(settings.colorScheme == .greenUpRedDown)
        #expect(settings.watchlistCoins.map(\.coinId) == ["bitcoin", "ethereum"], "a broken entry is dropped on its own")
        #expect(settings.watchlistCoins[0].alertKind == .change)
        #expect(settings.watchlistCoins[1].alertKind == .above)
        #expect(settings.watchlistCoins[1].notificationThreshold == 5000)
    }

    /// Open at Login defaults to off, so first launch registers no login item.
    @Test func launchAtLoginDefaultsOff() throws {
        #expect(AppSettings().launchAtLogin == false)
        #expect(try decode("{}").launchAtLogin == false)
        #expect(try decode(#"{"launchAtLogin":true}"#).launchAtLogin, "a saved choice is kept")
    }

    /// Menu bar content defaults to the price; older data without the field and unknown values fall back to it.
    @Test func menuBarContentDefaultsToPrice() throws {
        #expect(AppSettings().menuBarContent == .price)
        #expect(try decode("{}").menuBarContent == .price)
        #expect(try decode(#"{"menuBarContent":"marquee"}"#).menuBarContent == .price)
        #expect(try decode(#"{"menuBarContent":"icon"}"#).menuBarContent == .icon)

        var settings = AppSettings()
        settings.menuBarContent = .icon
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.menuBarContent == .icon)
    }

    @Test func absentWatchlistKeepsDefaultCoins() throws {
        let settings = try decode("{}")
        #expect(settings.watchlistCoins.map(\.coinId) == AppSettings().watchlistCoins.map(\.coinId))
    }

    @Test func emptyWatchlistStaysEmpty() throws {
        #expect(try decode(#"{"addedCoins":[]}"#).watchlistCoins.isEmpty)
    }

    @Test func roundTripUsesLegacyWatchlistKey() throws {
        var settings = AppSettings()
        settings.baseCurrency = .jpy
        settings.displayedCoinId = "ethereum"
        settings.watchlistCoins = [WatchlistCoin(coinId: "ethereum", alertKind: .below, notificationThreshold: 3000)]
        let data = try JSONEncoder().encode(settings)

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["addedCoins"] != nil)
        #expect(object?["watchlistCoins"] == nil)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.baseCurrency == .jpy)
        #expect(decoded.displayedCoinId == "ethereum")
        #expect(decoded.watchlistCoins.first?.alertKind == .below)
        #expect(decoded.watchlistCoins.first?.notificationThreshold == 3000)
    }

    @Test func userDefaultsStoreRoundTrips() {
        let store = UserDefaultsSettingsStore(defaults: InMemoryDataStorage())
        #expect(store.load() == nil, "nil when never saved (first launch)")
        var settings = AppSettings()
        settings.baseCurrency = .eur
        store.save(settings)
        #expect(store.load()?.baseCurrency == .eur)
    }

    @Test func corruptedStoredDataFallsBackToDefaults() {
        let storage = InMemoryDataStorage()
        storage.set(json("not json"), forKey: UserDefaultsSettingsStore.settingsKey)
        let loaded = UserDefaultsSettingsStore(defaults: storage).load()
        #expect(loaded?.watchlistCoins.map(\.coinId) == AppSettings().watchlistCoins.map(\.coinId))
    }
}
