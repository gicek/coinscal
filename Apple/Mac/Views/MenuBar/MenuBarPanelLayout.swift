import CoreGraphics

/// Placement of the menu bar panel below the status item (global screen coordinates, origin at the bottom left).
enum MenuBarPanelLayout {
    /// Space between the bottom of the status item and the top of the panel.
    static let gap: CGFloat = 6
    /// Minimum distance from the left and right edges of the screen's visible frame.
    static let screenMargin: CGFloat = 8

    /// Centered under the status item, then shifted horizontally to stay inside `visibleFrame`.
    /// The top never goes above the visible frame (the menu bar).
    static func frame(size: CGSize, statusItemFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let minX = visibleFrame.minX + screenMargin
        let maxX = visibleFrame.maxX - screenMargin - size.width
        let centeredX = statusItemFrame.midX - size.width / 2
        let x = maxX < minX ? minX : min(max(centeredX, minX), maxX)
        let top = min(statusItemFrame.minY, visibleFrame.maxY) - gap
        return CGRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
    }
}
