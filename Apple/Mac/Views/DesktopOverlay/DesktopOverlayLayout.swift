import CoreGraphics
import Foundation

/// Pure rules of the desktop overlay (docs/DESKTOP_OVERLAY.md): window size, placement and content.
enum DesktopOverlayLayout {
    /// Gap to the visible screen edge for the default corner.
    static let margin: CGFloat = 24
    /// Inner padding, as the system applies to widgets.
    static let contentPadding: CGFloat = 14
    static let cornerRadius: CGFloat = 22
    /// Below this background opacity the wallpaper decides legibility, so text gets the desktop-label treatment.
    static let legibleBackgroundOpacity = 0.2

    /// Like Finder's desktop icon labels: light text over a soft dark blur, readable on any wallpaper.
    /// Not while adjusting, which keeps at least 60% background.
    static func textNeedsHalo(backgroundOpacity: Double, isAdjusting: Bool) -> Bool {
        !isAdjusting && backgroundOpacity < legibleBackgroundOpacity
    }

    /// One layout, the large widget's: 364pt wide, its height follows the number of coins up to `rowLimit`.
    static let width: CGFloat = 364
    static let rowLimit = 16
    /// Row height of the large widget list (`WidgetListView`), and the 1pt divider between rows.
    static let rowHeight: CGFloat = 38
    static let dividerHeight: CGFloat = 1
    /// List header: the 16pt logo row plus its 6pt bottom padding.
    static let headerHeight: CGFloat = 22
    /// Before the first prices (`WidgetEmptyView`): the medium widget's height.
    static let emptyHeight: CGFloat = 170

    static func windowSize(for content: WidgetEntryContent) -> CGSize {
        guard content.hasPrices, !content.rows.isEmpty else { return CGSize(width: width, height: emptyHeight) }
        let rows = CGFloat(content.rows.count)
        let height = contentPadding * 2 + headerHeight + rows * rowHeight + (rows - 1) * dividerHeight
        return CGSize(width: width, height: height)
    }

    /// Top-right corner of the visible frame (below the menu bar, beside the Dock).
    static func defaultOrigin(windowSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.maxX - windowSize.width - margin, y: visibleFrame.maxY - windowSize.height - margin)
    }

    /// Bottom-left origin for a saved top-left corner, pulled back inside the visible frame (display changed,
    /// resolution changed, the panel grew).
    static func origin(saved: DesktopOverlayOrigin?, windowSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        guard let saved else { return defaultOrigin(windowSize: windowSize, visibleFrame: visibleFrame) }
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)
        let y = saved.y - windowSize.height
        return CGPoint(x: min(max(saved.x, visibleFrame.minX), maxX), y: min(max(y, visibleFrame.minY), maxY))
    }

    /// Height changed while adjusting: keep the top-left corner where the user has dragged it so far, then pull it
    /// back onto the display it is on.
    static func resized(_ frame: CGRect, to size: CGSize, screens: [CGRect]) -> CGRect {
        self.frame(saved: topLeft(of: frame), size: size, screens: screens)
    }

    static func topLeft(of frame: CGRect) -> DesktopOverlayOrigin {
        DesktopOverlayOrigin(x: frame.minX, y: frame.maxY)
    }

    /// Window frame across displays. `screens` are the visible frames with the main display first.
    /// The saved position goes to the display it overlaps most; if none (that display was unplugged), to the nearest
    /// one. The saved value itself is not changed, so the panel returns when the display comes back.
    static func frame(saved: DesktopOverlayOrigin?, size: CGSize, screens: [CGRect]) -> CGRect {
        guard let main = screens.first else { return CGRect(origin: .zero, size: size) }
        guard let saved else { return CGRect(origin: defaultOrigin(windowSize: size, visibleFrame: main), size: size) }
        let wanted = CGRect(origin: CGPoint(x: saved.x, y: saved.y - size.height), size: size)
        let screen = screens.max { overlap($0, wanted) < overlap($1, wanted) }.flatMap { overlap($0, wanted) > 0 ? $0 : nil }
            ?? screens.min { distance($0, wanted) < distance($1, wanted) }
            ?? main
        return CGRect(origin: origin(saved: saved, windowSize: size, visibleFrame: screen), size: size)
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    private static func distance(_ screen: CGRect, _ rect: CGRect) -> CGFloat {
        hypot(screen.midX - rect.midX, screen.midY - rect.midY)
    }

    /// Turning "Show on Desktop" on in settings starts in adjust mode so the panel can be placed right away;
    /// launching with it already on does not (`previous` is nil for the first settings the app applies).
    static func startsAdjusting(previous: AppSettings?, next: AppSettings) -> Bool {
        guard let previous else { return false }
        return !previous.desktopOverlayEnabled && next.desktopOverlayEnabled
    }

    /// Watchlist order up to the row limit.
    static func content(coins: [Coin], settings: AppSettings) -> WidgetEntryContent {
        let shown = coins.prefix(rowLimit)
        let rows = shown.map { coin in
            WidgetRow(
                id: coin.id, symbol: coin.symbol, name: coin.name, logoAssetName: coin.logoAssetName,
                hasMarket: coin.status == .active, price: coin.currentPrice, change24hPercent: coin.priceChange24hPercent
            )
        }
        return WidgetEntryContent(
            rows: rows,
            currency: settings.baseCurrency,
            updatedAt: shown.compactMap(\.lastUpdated).max(),
            language: settings.language,
            colorByChange: settings.priceColorEnabled,
            upColorHex: settings.resolvedUpColorHex,
            downColorHex: settings.resolvedDownColorHex
        )
    }
}
