import AppKit
import Foundation
import Testing
@testable import Coinscal

/// Desktop overlay rules (docs/DESKTOP_OVERLAY.md). No window is created here.
@MainActor
@Suite struct DesktopOverlayTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    private func coin(_ id: String, price: Double? = 1, updated: TimeInterval? = nil, status: CoinStatus = .active) -> Coin {
        Coin(id: id, symbol: id.uppercased(), name: id, rank: nil, logoAssetName: nil, logoURL: nil, status: status,
             currentPrice: price, priceChange24hPercent: 1, lastUpdated: updated.map(Date.init(timeIntervalSince1970:)))
    }

    @Test func settingsDefaultOffAndDecodeTolerantly() throws {
        let defaults = AppSettings()
        #expect(!defaults.desktopOverlayEnabled)
        #expect(defaults.desktopOverlaySize == .medium, "first time: medium")
        #expect(defaults.desktopOverlayBackgroundOpacity == 1)
        #expect(defaults.desktopOverlayOrigin == nil)

        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!old.desktopOverlayEnabled, "older data has no overlay")
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(
            #"{"desktopOverlaySize":"huge","desktopOverlayOrigin":"x","desktopOverlayAboveIcons":true,"desktopOverlayBackgroundOpacity":3}"#.utf8))
        #expect(unknown.desktopOverlaySize == .medium)
        #expect(unknown.desktopOverlayOrigin == nil)
        #expect(unknown.desktopOverlayBackgroundOpacity == 1, "out of range is clamped; the removed above-icons key is ignored")

        var settings = AppSettings()
        settings.desktopOverlayEnabled = true
        settings.desktopOverlaySize = .large
        settings.desktopOverlayBackgroundOpacity = 0.35
        settings.desktopOverlayOrigin = DesktopOverlayOrigin(x: 120, y: 300)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.desktopOverlayEnabled)
        #expect(decoded.desktopOverlayBackgroundOpacity == 0.35)
        #expect(decoded.desktopOverlaySize == .large)
        #expect(decoded.desktopOverlayOrigin == DesktopOverlayOrigin(x: 120, y: 300))
    }

    @Test func sizesMatchTheWidgets() {
        #expect(DesktopOverlayLayout.windowSize(.small) == CGSize(width: 170, height: 170))
        #expect(DesktopOverlayLayout.windowSize(.medium) == CGSize(width: 364, height: 170))
        #expect(DesktopOverlayLayout.windowSize(.large) == CGSize(width: 364, height: 382))
    }

    @Test func defaultPlacementIsTopRight() {
        let size = DesktopOverlayLayout.windowSize(.small)
        let origin = DesktopOverlayLayout.origin(saved: nil, windowSize: size, visibleFrame: screen)
        #expect(origin == CGPoint(x: 1440 - 170 - 24, y: 875 - 170 - 24))
    }

    @Test func savedPositionIsKeptOnScreen() {
        let size = DesktopOverlayLayout.windowSize(.large)
        #expect(DesktopOverlayLayout.origin(saved: .init(x: 100, y: 200), windowSize: size, visibleFrame: screen) == CGPoint(x: 100, y: 200))
        #expect(DesktopOverlayLayout.origin(saved: .init(x: 3000, y: 2000), windowSize: size, visibleFrame: screen)
                == CGPoint(x: 1440 - 364, y: 875 - 382), "smaller display or larger size")
        #expect(DesktopOverlayLayout.origin(saved: .init(x: -50, y: -50), windowSize: size, visibleFrame: screen) == .zero)
    }

    @Test func smallShowsTheMenuBarCoin() {
        var settings = AppSettings()
        settings.displayedCoinId = "ethereum"
        let coins = [coin("bitcoin"), coin("ethereum")]
        #expect(DesktopOverlayLayout.content(coins: coins, settings: settings, size: .small).rows.map(\.id) == ["ethereum"])
        settings.displayedCoinId = "gone"
        #expect(DesktopOverlayLayout.content(coins: coins, settings: settings, size: .small).rows.map(\.id) == ["bitcoin"])
        #expect(DesktopOverlayLayout.content(coins: [], settings: settings, size: .small).rows.isEmpty)
    }

    @Test func listsTakeTheWatchlistPrefix() {
        let coins = (1...10).map { coin("c\($0)", updated: Double($0)) } + [coin("dead", price: nil, status: .delisted)]
        let medium = DesktopOverlayLayout.content(coins: coins, settings: AppSettings(), size: .medium)
        #expect(medium.rows.map(\.id) == ["c1", "c2", "c3", "c4"])
        #expect(medium.updatedAt == Date(timeIntervalSince1970: 4), "latest update among the shown coins")
        #expect(DesktopOverlayLayout.content(coins: coins, settings: AppSettings(), size: .large).rows.count == 8)
        let withDead = DesktopOverlayLayout.content(coins: [coin("dead", price: nil, status: .delisted)], settings: AppSettings(), size: .medium)
        #expect(withDead.rows.first?.hasMarket == false)
    }

    @Test func windowSitsBetweenWallpaperAndIcons() {
        let level = DesktopOverlayController.level.rawValue
        #expect(level > Int(CGWindowLevelForKey(.desktopWindow)) && level < Int(CGWindowLevelForKey(.desktopIconWindow)))
    }

    // MARK: Displays

    /// Main 1440×875 at the origin; an external display to the right and one above-left (like a real arrangement).
    private let displays = [
        CGRect(x: 0, y: 0, width: 1440, height: 875),
        CGRect(x: 1440, y: -200, width: 1080, height: 1880),
        CGRect(x: -400, y: 900, width: 1920, height: 1055),
    ]

    @Test func savedPositionOnAnExternalDisplayStaysThere() {
        let size = DesktopOverlayLayout.windowSize(.small)
        let frame = DesktopOverlayLayout.frame(saved: .init(x: 1800, y: 600), size: size, screens: displays)
        #expect(frame.origin == CGPoint(x: 1800, y: 600))
        let above = DesktopOverlayLayout.frame(saved: .init(x: 100, y: 1500), size: size, screens: displays)
        #expect(above.origin == CGPoint(x: 100, y: 1500))
    }

    @Test func partlyOffscreenIsPulledOntoTheDisplayItMostlyCovers() {
        let size = DesktopOverlayLayout.windowSize(.small)
        // Mostly on the right display, sticking out past its right edge.
        let frame = DesktopOverlayLayout.frame(saved: .init(x: 2450, y: 600), size: size, screens: displays)
        #expect(frame.origin == CGPoint(x: 1440 + 1080 - 170, y: 600))
    }

    @Test func unpluggedDisplayFallsBackToTheNearestOne() {
        let size = DesktopOverlayLayout.windowSize(.small)
        // Was on a display further right that is gone now.
        let frame = DesktopOverlayLayout.frame(saved: .init(x: 3000, y: 300), size: size, screens: displays)
        #expect(displays[1].contains(frame), "nearest remaining display")
        #expect(DesktopOverlayLayout.frame(saved: nil, size: size, screens: displays).origin
                == DesktopOverlayLayout.defaultOrigin(windowSize: size, visibleFrame: displays[0]), "default: main display")
    }

    @Test func turningOnStartsAdjustingButLaunchDoesNot() {
        var on = AppSettings()
        on.desktopOverlayEnabled = true
        let off = AppSettings()
        #expect(DesktopOverlayLayout.startsAdjusting(previous: off, next: on), "switched on in settings")
        #expect(!DesktopOverlayLayout.startsAdjusting(previous: nil, next: on), "launch with it already on")
        #expect(!DesktopOverlayLayout.startsAdjusting(previous: on, next: on), "other settings changed, e.g. size")
        #expect(!DesktopOverlayLayout.startsAdjusting(previous: on, next: off))
    }

    @Test func resizingWhileAdjustingKeepsTheTopLeftCorner() {
        let small = CGRect(x: 600, y: 512, width: 170, height: 170)  // top edge at 682
        let large = DesktopOverlayLayout.resized(small, to: DesktopOverlayLayout.windowSize(.large), screens: [screen])
        #expect(large == CGRect(x: 600, y: 682 - 382, width: 364, height: 382))
        let nearEdge = CGRect(x: 1250, y: 100, width: 170, height: 170)
        let clamped = DesktopOverlayLayout.resized(nearEdge, to: DesktopOverlayLayout.windowSize(.large), screens: [screen])
        #expect(clamped.maxX <= screen.maxX && clamped.minY >= screen.minY, "pulled back on screen")
    }

    @Test func resizingOnAnExternalDisplayStaysOnIt() {
        let small = CGRect(x: 2300, y: 100, width: 170, height: 170)
        let large = DesktopOverlayLayout.resized(small, to: DesktopOverlayLayout.windowSize(.large), screens: displays)
        #expect(displays[1].contains(large))
    }

    @Test func textGetsTheDesktopLabelTreatmentBelow20Percent() {
        #expect(DesktopOverlayLayout.textNeedsHalo(backgroundOpacity: 0, isAdjusting: false))
        #expect(DesktopOverlayLayout.textNeedsHalo(backgroundOpacity: 0.19, isAdjusting: false))
        #expect(!DesktopOverlayLayout.textNeedsHalo(backgroundOpacity: 0.2, isAdjusting: false))
        #expect(!DesktopOverlayLayout.textNeedsHalo(backgroundOpacity: 0, isAdjusting: true), "adjusting keeps a 60% background")
    }
}
