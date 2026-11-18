import AppKit
import Combine
import SwiftUI

/// Borderless window that only becomes key while its position is being adjusted (so the Done button works).
final class DesktopOverlayWindow: NSWindow {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Desktop overlay (docs/ARCHITECTURE.md, "Desktop Ticker"): a transparent, click-through window between the wallpaper and the
/// desktop icons, on every Space, outside Mission Control and the window cycle. Prices follow the app's polling,
/// so unlike WidgetKit there is no refresh budget. Can be dragged onto any display.
@MainActor
final class DesktopOverlayController {
    private let model = DesktopOverlayModel()
    private var window: DesktopOverlayWindow?
    private weak var settingsVM: SettingsViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var settings = AppSettings()
    private var coins: [Coin] = []
    /// nil until the first settings are applied (launch), so an already enabled overlay does not start adjusting.
    private var appliedSettings: AppSettings?

    func bind(coinListVM: CoinListViewModel, settingsVM: SettingsViewModel) {
        self.settingsVM = settingsVM
        model.onDoneAdjusting = { [weak self] in self?.endAdjusting() }

        Publishers.CombineLatest(coinListVM.$coins, settingsVM.$settings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak coinListVM] coins, settings in
                let matchingCurrency = coinListVM?.priceDataCurrency == settings.baseCurrency
                self?.apply(coins: matchingCurrency ? coins : [], settings: settings)
            }
            .store(in: &cancellables)

        // Displays added / removed / resized, and wake from sleep: put the window back on the main display.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.placeWindow() }
            .store(in: &cancellables)
    }

    /// Lets the user drag the overlay; Done saves the position and makes it click-through again.
    func beginAdjusting() {
        guard settings.desktopOverlayEnabled, let window else { return }
        model.isAdjusting = true
        window.allowsKey = true
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Done: save where the panel was put and make it click-through again.
    private func endAdjusting() {
        guard let window, model.isAdjusting else { return }
        stopAdjusting(window)
        settingsVM?.settings.desktopOverlayTopLeft = DesktopOverlayLayout.topLeft(of: window.frame)
    }

    private func stopAdjusting(_ window: DesktopOverlayWindow) {
        model.isAdjusting = false
        window.allowsKey = false
        window.ignoresMouseEvents = true
        window.isMovableByWindowBackground = false
        window.level = Self.level
        window.resignKey()
    }

    private func apply(coins: [Coin], settings: AppSettings) {
        let previous = self.settings
        let startsAdjusting = DesktopOverlayLayout.startsAdjusting(previous: appliedSettings, next: settings)
        self.settings = settings
        self.coins = coins
        appliedSettings = settings
        guard settings.desktopOverlayEnabled else {
            // Turned off while adjusting: leave without saving the position.
            if let window, model.isAdjusting { stopAdjusting(window) }
            window?.orderOut(nil)
            return
        }
        model.backgroundOpacity = settings.desktopOverlayBackgroundOpacity
        model.textSize = settings.desktopOverlayTextSize
        let anchor = model.isAdjusting ? window.map { DesktopOverlayLayout.topLeft(of: $0.frame) } : settings.desktopOverlayTopLeft
        let frame = updateContentAndFrame(anchor: anchor)

        let isNew = window == nil
        let window = window ?? makeWindow()
        if !model.isAdjusting {
            window.level = Self.level
        }
        if model.isAdjusting {
            // The watchlist changed while adjusting: keep the top-left corner where the panel is now; Done stores it.
            if window.frame.size != frame.size {
                window.setFrame(frame, display: true)
            }
        } else if isNew || !window.isVisible || window.frame.size != frame.size
                    || previous.desktopOverlayTopLeft != settings.desktopOverlayTopLeft {
            // The saved corner is the top-left, so a taller or shorter panel keeps its top edge.
            window.setFrame(frame, display: true)
        }
        window.orderFrontRegardless()
        if startsAdjusting {
            beginAdjusting()
        }
    }

    private func placeWindow() {
        guard let window, !model.isAdjusting else { return }
        window.setFrame(updateContentAndFrame(anchor: settings.desktopOverlayTopLeft), display: true)
    }

    private func updateContentAndFrame(anchor: DesktopOverlayOrigin?) -> CGRect {
        let content = DesktopOverlayLayout.content(coins: coins, settings: settings)
        let fullSize = DesktopOverlayLayout.windowSize(for: content, textSize: model.textSize)
        guard let screen = DesktopOverlayLayout.screen(for: anchor, size: fullSize, screens: Self.screens) else {
            model.content = content
            return CGRect(origin: .zero, size: fullSize)
        }
        let limit = DesktopOverlayLayout.rowsThatFit(height: screen.height, textSize: model.textSize, usesDefaultPosition: anchor == nil)
        model.content = content.rows.count <= limit ? content : DesktopOverlayLayout.content(coins: coins, settings: settings, limit: limit)
        let size = DesktopOverlayLayout.windowSize(for: model.content, textSize: model.textSize)
        let origin = DesktopOverlayLayout.origin(saved: anchor, windowSize: size, visibleFrame: screen)
        return CGRect(origin: origin, size: size)
    }

    /// Visible frames of all displays, main (menu bar) display first.
    private static var screens: [CGRect] { NSScreen.screens.map(\.visibleFrame) }

    private func makeWindow() -> DesktopOverlayWindow {
        let window = DesktopOverlayWindow(
            contentRect: CGRect(origin: .zero, size: DesktopOverlayLayout.windowSize(for: model.content, textSize: model.textSize)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        // Every Space, fixed in Mission Control and Show Desktop, never in ⌘` / the window cycle.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: DesktopOverlayView(model: model))
        self.window = window
        return window
    }

    /// One level above the wallpaper (same level would let the wallpaper reorder over it), below the desktop icons.
    static var level: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    }
}
