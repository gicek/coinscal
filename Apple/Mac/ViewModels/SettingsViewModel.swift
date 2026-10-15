import Foundation
import Combine
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    /// Selected settings sidebar tab; set by menu / popover navigation, not persisted.
    @Published var settingsWindowTab: SettingsTab = .general

    private let store: SettingsStore

    /// The login item is synced from `settings.launchAtLogin` by AppDelegate at launch; this only reads and writes settings.
    init(store: SettingsStore = UserDefaultsSettingsStore()) {
        self.store = store
        self.settings = store.load() ?? AppSettings()
    }

    private func save() {
        store.save(settings)
    }

    private static let defaultUpColor = Color(hex: Constants.Defaults.upColorHex)!
    private static let defaultDownColor = Color(hex: Constants.Defaults.downColorHex)!

    func upColor(for scheme: PriceColorScheme) -> Color {
        switch scheme {
        case .greenUpRedDown: return Self.defaultUpColor
        case .redUpGreenDown: return Self.defaultDownColor
        case .custom: return Color(hex: settings.customUpColorHex) ?? Self.defaultUpColor
        }
    }

    func downColor(for scheme: PriceColorScheme) -> Color {
        switch scheme {
        case .greenUpRedDown: return Self.defaultDownColor
        case .redUpGreenDown: return Self.defaultUpColor
        case .custom: return Color(hex: settings.customDownColorHex) ?? Self.defaultDownColor
        }
    }

    func priceColor(changePercent: Double?) -> Color {
        guard settings.priceColorEnabled, let change = changePercent else {
            return .primary
        }
        if change >= 0 {
            return upColor(for: settings.colorScheme)
        } else {
            return downColor(for: settings.colorScheme)
        }
    }

    func priceNSColor(changePercent: Double?) -> NSColor {
        let color = priceColor(changePercent: changePercent)
        return NSColor(color)
    }
}
