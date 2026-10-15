import Foundation

// MARK: - Language enum

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system   = "system"
    case en       = "en"
    case zhHans   = "zh-Hans"
    case zhHant   = "zh-Hant"

    var id: String { rawValue }

    /// Always in the language's own script so users can identify their option:
    /// the catalog holds the same endonym under every localization.
    @MainActor
    var displayName: String {
        switch self {
        case .system: return loc("lang.system")
        case .en:     return loc("lang.endonym.en")
        case .zhHans: return loc("lang.endonym.zh-Hans")
        case .zhHant: return loc("lang.endonym.zh-Hant")
        }
    }

    /// Resolve .system to a concrete language based on device locale.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let tag = Locale.preferredLanguages.first ?? "en"
        if tag.hasPrefix("zh-Hant") || tag.hasPrefix("zh-TW") ||
           tag.hasPrefix("zh-HK")   || tag.hasPrefix("zh-MO") {
            return .zhHant
        } else if tag.hasPrefix("zh") {
            return .zhHans
        }
        return .en
    }

    /// `.lproj` folder name of the resolved language.
    var resourceCode: String {
        switch resolved {
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        case .en, .system: return "en"
        }
    }
}

// MARK: - Manager

@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    private var bundle: Bundle = .main

    func setLanguage(_ language: AppLanguage) {
        bundle = Self.bundle(for: language)
    }

    /// Looks a key up in a given language without the app-wide setting: widgets render outside the app's language state.
    nonisolated static func string(for key: String, language: AppLanguage) -> String {
        bundle(for: language).localizedString(forKey: key, value: key, table: nil)
    }

    private nonisolated static func bundle(for language: AppLanguage) -> Bundle {
        let path = Bundle.main.path(forResource: language.resourceCode, ofType: "lproj") ?? ""
        return Bundle(path: path) ?? .main
    }

    func string(for key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Global shorthand — call inside SwiftUI body or AppKit code.
@MainActor
func loc(_ key: String) -> String {
    LocalizationManager.shared.string(for: key)
}
