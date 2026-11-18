import Testing
@testable import Coinscal

@MainActor
struct SettingsWindowTests {
    @Test func panesAreOrderedGeneralDisplayWatchlistAbout() {
        #expect(SettingsTab.allCases == [.general, .display, .watchlist, .about])
    }

    @Test func paneTitlesAreTranslated() {
        for tab in SettingsTab.allCases {
            #expect(!tab.title.hasPrefix("nav."), "Missing title for \(tab.rawValue)")
        }
    }

    @Test func panelNavigationKeepsTabRawValues() {
        // The panel posts the raw value in `coinscalNavigate`; the stored values must stay stable.
        #expect(SettingsTab(rawValue: "watchlist") == .watchlist)
        #expect(SettingsTab(rawValue: "display") == .display)
    }
}
