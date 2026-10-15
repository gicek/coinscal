import Foundation
import OSLog

/// Injection point for settings persistence: `SettingsViewModel` depends only on this; tests inject an in-memory store.
protocol SettingsStore {
    /// nil means settings were never saved (first launch).
    func load() -> AppSettings?
    func save(_ settings: AppSettings)
}

/// Minimal key-value interface used by `UserDefaultsSettingsStore`; `UserDefaults` conforms as is, tests inject an in-memory one.
protocol SettingsDataStorage {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: SettingsDataStorage {}

/// Stores the whole `AppSettings` as JSON under the `appSettings` key in UserDefaults.
struct UserDefaultsSettingsStore: SettingsStore {
    static let settingsKey = "appSettings"
    private static let logger = Logger(subsystem: "com.gicek.coinscal", category: "Settings")

    private let defaults: SettingsDataStorage

    init(defaults: SettingsDataStorage = UserDefaults.standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings? {
        guard let data = defaults.data(forKey: Self.settingsKey) else { return nil }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            // AppSettings decodes field by field, so reaching this means the data is corrupt as a whole; fall back to defaults.
            Self.logger.error("Failed to decode stored settings: \(error.localizedDescription, privacy: .public)")
            return AppSettings()
        }
    }

    func save(_ settings: AppSettings) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.settingsKey)
        } catch {
            Self.logger.error("Failed to encode settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
