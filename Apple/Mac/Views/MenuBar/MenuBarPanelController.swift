import AppKit
import SwiftUI

/// Borderless panel for the menu bar content. It can become key without activating the app, so a panel opened
/// from a widget click (app not active) still receives clicks and keys.
final class MenuBarPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc while the panel is key.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Hosting view for the panel content that acts on the first click. Coinscal is often not the active app while
/// the panel is shown (macOS 14+ may refuse `NSApp.activate`, and a widget click never activates it); a plain
/// `NSHostingView` then treats the click as activation only and the buttons ignore it.
final class MenuBarPanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows the menu bar content below the status item and decides open or close from the panel's own visibility.
///
/// An `NSPopover` can't do this on macOS 27: pressing the status item closes a `.transient` popover on mouse-down
/// (it loses key status), and the status item action then reopens it on mouse-up (docs/MENU_BAR_PANEL.md).
/// The panel closes on clicks outside it, Esc, and losing key status, except when the status item press itself
/// takes key status or reaches the outside-click monitor: that press ends in the toggle, which closes the panel.
@MainActor
final class MenuBarPanelController {
    private let panel: MenuBarPanel
    /// The status item's window: the panel is placed under it, and presses inside it are left to the toggle.
    private let statusItemWindow: () -> NSWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

    var isShown: Bool { panel.isVisible }

    init(contentView: NSView, size: CGSize, statusItemWindow: @escaping () -> NSWindow?) {
        self.statusItemWindow = statusItemWindow
        panel = MenuBarPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The window is transparent outside the rounded material; the system shadow follows that shape.
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Show and hide instantly, like the menu bar's own menus.
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.contentView = Self.materialView(containing: contentView, size: size)
        panel.onCancel = { [weak self] in self?.close() }
    }

    func toggle() {
        if isShown { close() } else { show() }
    }

    /// Returns false when the status item isn't on screen yet (right after launch), so nothing was shown.
    @discardableResult
    func show() -> Bool {
        guard !isShown else { return true }
        guard let anchor = statusItemWindow(), let screen = anchor.screen else { return false }
        panel.setFrame(
            MenuBarPanelLayout.frame(size: panel.frame.size, statusItemFrame: anchor.frame, visibleFrame: screen.visibleFrame),
            display: false
        )
        // An LSUIElement app must activate explicitly, otherwise clicks inside the panel are not routed reliably.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // The shadow is computed from the drawn content; recompute it once the rounded material is on screen.
        panel.invalidateShadow()
        installDismissal()
        return true
    }

    func close() {
        guard isShown else { return }
        panel.orderOut(nil)
        removeDismissal()
    }

    /// Height follows the watchlist size; a shown panel keeps its top edge under the status item.
    func setContentSize(_ size: CGSize) {
        guard panel.frame.size != size else { return }
        guard isShown, let anchor = statusItemWindow(), let screen = anchor.screen else {
            panel.setContentSize(size)
            return
        }
        panel.setFrame(
            MenuBarPanelLayout.frame(size: size, statusItemFrame: anchor.frame, visibleFrame: screen.visibleFrame),
            display: true
        )
        panel.invalidateShadow()
    }

    // MARK: - Look

    /// The system popover material (heavily blurred, so what is behind the panel doesn't compete with the
    /// price colors), clipped to rounded corners with a stretchable mask image so the corners stay smooth.
    private static func materialView(containing content: NSView, size: CGSize) -> NSView {
        let material = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = roundedMask(radius: Constants.Popover.cornerRadius)
        material.autoresizingMask = [.width, .height]
        content.frame = material.bounds
        content.autoresizingMask = [.width, .height]
        material.addSubview(content)
        return material
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - Dismissal

    private func installDismissal() {
        removeDismissal()
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps and on the desktop. macOS 27 also reports presses on our own status item here.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isMouseInStatusItem else { return }
                self.close()
            }
        }
        // Clicks in Coinscal's other windows (Settings, the desktop overlay).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window !== self.panel, event.window !== self.statusItemWindow() {
                    self.close()
                }
            }
            return event
        }
        // Another app or window became key (Cmd-Tab, Mission Control, a click the monitors don't see).
        // This also covers a panel opened from a widget, when Coinscal never became active.
        // Clicking the status item also takes key status; that click's toggle closes the panel instead.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isMouseInStatusItem else { return }
                self.close()
            }
        }
    }

    private func removeDismissal() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
        globalMonitor = nil
        localMonitor = nil
        resignKeyObserver = nil
    }

    private var isMouseInStatusItem: Bool {
        statusItemWindow()?.frame.contains(NSEvent.mouseLocation) ?? false
    }
}
