import CoreGraphics
import Testing
@testable import Coinscal

/// Menu bar panel placement (docs/MENU_BAR_PANEL.md). Global coordinates, origin at the bottom left.
@Suite struct MenuBarPanelLayoutTests {
    /// A 1440×900 display with a 24pt menu bar.
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 876)
    private let size = CGSize(width: 320, height: 364)

    private func statusItem(midX: CGFloat, width: CGFloat = 100) -> CGRect {
        CGRect(x: midX - width / 2, y: 876, width: width, height: 24)
    }

    @Test func centersUnderTheStatusItem() {
        let frame = MenuBarPanelLayout.frame(size: size, statusItemFrame: statusItem(midX: 700), visibleFrame: visible)
        #expect(frame.midX == 700)
        #expect(frame.maxY == 876 - MenuBarPanelLayout.gap)
        #expect(frame.size == size)
    }

    @Test func staysInsideTheRightEdge() {
        let frame = MenuBarPanelLayout.frame(size: size, statusItemFrame: statusItem(midX: 1420), visibleFrame: visible)
        #expect(frame.maxX == visible.maxX - MenuBarPanelLayout.screenMargin)
    }

    @Test func staysInsideTheLeftEdge() {
        let frame = MenuBarPanelLayout.frame(size: size, statusItemFrame: statusItem(midX: 30), visibleFrame: visible)
        #expect(frame.minX == visible.minX + MenuBarPanelLayout.screenMargin)
    }

    @Test func followsASecondaryDisplay() {
        // A display above and left of the main one.
        let secondary = CGRect(x: -200, y: 900, width: 1920, height: 1056)
        let item = CGRect(x: 400, y: 1956, width: 103, height: 24)
        let frame = MenuBarPanelLayout.frame(size: size, statusItemFrame: item, visibleFrame: secondary)
        #expect(frame.midX.rounded() == item.midX.rounded())
        #expect(frame.maxY == 1956 - MenuBarPanelLayout.gap)
    }

    @Test func neverRisesAboveTheVisibleFrame() {
        // A status item frame reported above the visible frame (e.g. the menu bar is hidden) still places the panel below it.
        let item = CGRect(x: 650, y: 900, width: 100, height: 24)
        let frame = MenuBarPanelLayout.frame(size: size, statusItemFrame: item, visibleFrame: visible)
        #expect(frame.maxY == visible.maxY - MenuBarPanelLayout.gap)
    }

    @Test func narrowScreenPinsToTheLeftMargin() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 600)
        let frame = MenuBarPanelLayout.frame(size: size, statusItemFrame: statusItem(midX: 150), visibleFrame: tiny)
        #expect(frame.minX == MenuBarPanelLayout.screenMargin)
    }
}
