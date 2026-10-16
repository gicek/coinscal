import AppKit
import Foundation
import SwiftUI
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
        #expect(defaults.desktopOverlayBackgroundOpacity == 1)
        #expect(defaults.desktopOverlayTextSize == .normal)
        #expect(defaults.desktopOverlayTopLeft == nil)

        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!old.desktopOverlayEnabled, "older data has no overlay")
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(
            #"{"desktopOverlayTopLeft":"x","desktopOverlayTextSize":"huge","desktopOverlayAboveIcons":true,"desktopOverlayBackgroundOpacity":3}"#.utf8))
        #expect(unknown.desktopOverlayTopLeft == nil)
        #expect(unknown.desktopOverlayTextSize == .normal)
        #expect(unknown.desktopOverlayBackgroundOpacity == 1, "out of range is clamped; the removed above-icons key is ignored")

        var settings = AppSettings()
        settings.desktopOverlayEnabled = true
        settings.desktopOverlayBackgroundOpacity = 0.35
        settings.desktopOverlayTextSize = .large
        settings.desktopOverlayTopLeft = DesktopOverlayOrigin(x: 120, y: 300)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.desktopOverlayEnabled)
        #expect(decoded.desktopOverlayBackgroundOpacity == 0.35)
        #expect(decoded.desktopOverlayTextSize == .large)
        #expect(decoded.desktopOverlayTopLeft == DesktopOverlayOrigin(x: 120, y: 300))
    }

    @Test func savedBottomLeftOfTheOldSizesMovesToTheTopLeft() throws {
        func decode(_ json: String) throws -> DesktopOverlayOrigin? {
            try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).desktopOverlayTopLeft
        }
        #expect(try decode(#"{"desktopOverlaySize":"large","desktopOverlayOrigin":{"x":100,"y":200}}"#) == .init(x: 100, y: 582))
        #expect(try decode(#"{"desktopOverlaySize":"small","desktopOverlayOrigin":{"x":100,"y":200}}"#) == .init(x: 100, y: 370))
        #expect(try decode(#"{"desktopOverlayOrigin":{"x":100,"y":200}}"#) == .init(x: 100, y: 370), "medium was the default")
        #expect(try decode(#"{"desktopOverlaySize":"large"}"#) == nil, "never placed: default corner")
        #expect(try decode(#"{"desktopOverlayTopLeft":{"x":5,"y":6},"desktopOverlayOrigin":{"x":100,"y":200}}"#) == .init(x: 5, y: 6))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any]
        #expect(encoded?["desktopOverlaySize"] == nil && encoded?["desktopOverlayOrigin"] == nil, "old keys are not written back")
    }

    private func content(rows: Int, prices: Bool = true) -> WidgetEntryContent {
        let coins = (0..<rows).map { coin("c\($0)", price: prices ? 1 : nil, updated: prices ? 1 : nil) }
        return DesktopOverlayLayout.content(coins: coins, settings: AppSettings())
    }

    @Test func heightFollowsTheCoinsUpTo16() {
        #expect(DesktopOverlayLayout.windowSize(for: content(rows: 1), textSize: .normal) == CGSize(width: 364, height: 88))
        #expect(DesktopOverlayLayout.windowSize(for: content(rows: 8), textSize: .normal).height == 361, "padding, header, 8 rows, 7 dividers")
        #expect(content(rows: 20).rows.count == 16)
        #expect(DesktopOverlayLayout.windowSize(for: content(rows: 20), textSize: .normal).height == 673, "16 rows")
        #expect(DesktopOverlayLayout.windowSize(for: content(rows: 0), textSize: .normal) == CGSize(width: 364, height: 170), "no coins")
        #expect(DesktopOverlayLayout.windowSize(for: content(rows: 3, prices: false), textSize: .normal).height == 170, "no prices yet")
    }

    @Test func largeTextGrowsTheRowsAndTheWidth() {
        let normal = DesktopOverlayLayout.windowSize(for: content(rows: 8), textSize: .normal)
        let large = DesktopOverlayLayout.windowSize(for: content(rows: 8), textSize: .large)
        #expect(large.width == 400 && normal.width == 364)
        #expect(large.height == normal.height + 1 + 8 * 4, "1pt taller header, 4pt taller rows")
        #expect(DesktopOverlayLayout.textBoost(.large) == 2 && DesktopOverlayLayout.textBoost(.normal) == 0)
    }

    /// The computed height must be what the shared list view needs, or the last row is clipped or a gap is left.
    @Test(arguments: DesktopOverlayTextSize.allCases)
    func computedHeightMatchesTheRenderedList(textSize: DesktopOverlayTextSize) {
        for rows in [1, 5, 16] {
            let c = content(rows: rows)
            let padding = DesktopOverlayLayout.contentPadding * 2
            let size = DesktopOverlayLayout.windowSize(for: c, textSize: textSize)
            let view = NSHostingView(rootView: WidgetListView(content: c, now: Date(), large: true)
                .environment(\.widgetTextBoost, DesktopOverlayLayout.textBoost(textSize))
                .frame(width: size.width - padding))
            #expect(abs(view.fittingSize.height - (size.height - padding)) < 0.5, "\(rows) rows: \(view.fittingSize.height)")
        }
    }

    @Test func listTakesTheWatchlistPrefix() {
        let coins = (1...20).map { coin("c\($0)", updated: Double($0)) }
        let shown = DesktopOverlayLayout.content(coins: coins, settings: AppSettings())
        #expect(shown.rows.map(\.id) == (1...16).map { "c\($0)" })
        #expect(shown.updatedAt == Date(timeIntervalSince1970: 16), "latest update among the shown coins")
        let withDead = DesktopOverlayLayout.content(coins: [coin("dead", price: nil, status: .delisted)], settings: AppSettings())
        #expect(withDead.rows.first?.hasMarket == false)
    }

    private let size = CGSize(width: 364, height: 200)

    @Test func defaultPlacementIsTopRight() {
        let origin = DesktopOverlayLayout.origin(saved: nil, windowSize: size, visibleFrame: screen)
        #expect(origin == CGPoint(x: 1440 - 364 - 24, y: 875 - 200 - 24))
    }

    @Test func savedTopLeftIsKeptOnScreen() {
        #expect(DesktopOverlayLayout.origin(saved: .init(x: 100, y: 500), windowSize: size, visibleFrame: screen) == CGPoint(x: 100, y: 300))
        #expect(DesktopOverlayLayout.origin(saved: .init(x: 3000, y: 2000), windowSize: size, visibleFrame: screen)
                == CGPoint(x: 1440 - 364, y: 875 - 200), "smaller display")
        #expect(DesktopOverlayLayout.origin(saved: .init(x: -50, y: 100), windowSize: size, visibleFrame: screen) == .zero, "grew past the bottom")
    }

    @Test func aTallerPanelKeepsItsTopEdge() {
        let saved = DesktopOverlayOrigin(x: 300, y: 800)
        let short = DesktopOverlayLayout.frame(saved: saved, size: CGSize(width: 364, height: 100), screens: [screen])
        let tall = DesktopOverlayLayout.frame(saved: saved, size: CGSize(width: 364, height: 400), screens: [screen])
        #expect(short.maxY == 800 && tall.maxY == 800 && tall.minX == 300)
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
        let frame = DesktopOverlayLayout.frame(saved: .init(x: 1800, y: 800), size: size, screens: displays)
        #expect(frame.origin == CGPoint(x: 1800, y: 600))
        let above = DesktopOverlayLayout.frame(saved: .init(x: 100, y: 1700), size: size, screens: displays)
        #expect(above.origin == CGPoint(x: 100, y: 1500))
    }

    @Test func partlyOffscreenIsPulledOntoTheDisplayItMostlyCovers() {
        // Mostly on the right display, sticking out past its right edge.
        let frame = DesktopOverlayLayout.frame(saved: .init(x: 2250, y: 800), size: size, screens: displays)
        #expect(frame.origin == CGPoint(x: 1440 + 1080 - 364, y: 600))
    }

    @Test func unpluggedDisplayFallsBackToTheNearestOne() {
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
        #expect(!DesktopOverlayLayout.startsAdjusting(previous: on, next: on), "other settings changed, e.g. opacity")
        #expect(!DesktopOverlayLayout.startsAdjusting(previous: on, next: off))
    }

    @Test func resizingWhileAdjustingKeepsTheTopLeftCorner() {
        let short = CGRect(x: 600, y: 512, width: 364, height: 170)  // top edge at 682
        let tall = DesktopOverlayLayout.resized(short, to: CGSize(width: 364, height: 400), screens: [screen])
        #expect(tall == CGRect(x: 600, y: 682 - 400, width: 364, height: 400))
        let nearBottom = CGRect(x: 600, y: 20, width: 364, height: 170)
        let clamped = DesktopOverlayLayout.resized(nearBottom, to: CGSize(width: 364, height: 400), screens: [screen])
        #expect(clamped.minY >= screen.minY, "pulled back on screen")
    }

    @Test func resizingOnAnExternalDisplayStaysOnIt() {
        let short = CGRect(x: 1600, y: 100, width: 364, height: 170)
        let tall = DesktopOverlayLayout.resized(short, to: CGSize(width: 364, height: 500), screens: displays)
        #expect(displays[1].contains(tall))
    }

    @Test func textGetsTheDesktopLabelTreatmentBelow20Percent() {
        #expect(DesktopOverlayLayout.textNeedsHalo(backgroundOpacity: 0, isAdjusting: false))
        #expect(DesktopOverlayLayout.textNeedsHalo(backgroundOpacity: 0.19, isAdjusting: false))
        #expect(!DesktopOverlayLayout.textNeedsHalo(backgroundOpacity: 0.2, isAdjusting: false))
        #expect(!DesktopOverlayLayout.textNeedsHalo(backgroundOpacity: 0, isAdjusting: true), "adjusting keeps a 60% background")
    }
}
