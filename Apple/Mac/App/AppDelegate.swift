import AppKit
import SwiftUI
import Combine

private struct ReloadSettingsSnapshot: Equatable {
    let baseCurrency: BaseCurrency
    let priceChangeNotificationEnabled: Bool
    let pollingInterval: TimeInterval
    let language: AppLanguage
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?

    let settingsVM = SettingsViewModel()
    let catalog = CoinCatalog.bundled()
    lazy var coinListVM = CoinListViewModel(settingsViewModel: settingsVM, catalog: catalog)
    lazy var watchlistVM = WatchlistViewModel(catalog: catalog)
    private let menuBarVM = MenuBarViewModel()
    /// Lazy: the unit-test host never touches the App Group container.
    private lazy var widgetSnapshotWriter = WidgetSnapshotWriter()
    /// Lazy like the snapshot writer: nothing is created when the app is the unit-test host.
    private lazy var desktopOverlay = DesktopOverlayController()
    /// Lazy like the snapshot writer: the App Group container and the network stay untouched in the unit-test host.
    private lazy var logoStore = CoinLogoStore(client: URLSession.shared)
    /// A widget click launched the app: the URL arrives before the popover exists, so it is shown after setup.
    private var opensPopoverAfterLaunch = false
    /// Closes the popover on clicks in other apps or the desktop while it is shown (see `popoverDidShow`).
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// When launched as the unit-test host, set nothing up: no network polling, no notification permission,
    /// no login item, and no exiting because a release build of the app is already running.
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isRunningUnitTests { return }

        // Single instance: exit when another instance with the same bundle id is running (e.g. a release copy next to a debug build).
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }

        // On newer macOS versions, AppKit may auto-attach action images
        // to some NSMenuItem selectors (e.g. Settings/Quit).
        UserDefaults.standard.set(false, forKey: "NSMenuEnableActionImages")

        // Hide dock icon - LSUIElement handles this via Info.plist
        setupStatusItem()
        setupPopover()
        widgetSnapshotWriter.bind(coinListVM: coinListVM, settingsVM: settingsVM)
        desktopOverlay.bind(coinListVM: coinListVM, settingsVM: settingsVM)
        // Download logos of watchlist coins that ship without one, at launch and whenever the watchlist changes.
        settingsVM.$settings
            .map { $0.watchlistCoins.map(\.coinId) }
            .removeDuplicates()
            .sink { [weak self] ids in
                guard let self else { return }
                self.logoStore.sync(watchlist: ids.compactMap { self.catalog.metadata(for: $0) })
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .coinscalAdjustDesktopOverlay)
            .sink { [weak self] _ in self?.desktopOverlay.beginAdjusting() }
            .store(in: &cancellables)
        if opensPopoverAfterLaunch {
            opensPopoverAfterLaunch = false
            showPopoverFromURL(retries: 10)
        }
        NotificationService.shared.requestPermission()

        // Sync launch at login
        LaunchAtLoginService.shared.setEnabled(settingsVM.settings.launchAtLogin)

        // Re-poll after settings change
        settingsVM.$settings
            .map {
                ReloadSettingsSnapshot(
                    baseCurrency: $0.baseCurrency,
                    priceChangeNotificationEnabled: $0.priceChangeNotificationEnabled,
                    pollingInterval: $0.pollingInterval,
                    language: $0.language
                )
            }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.coinListVM.reloadAfterSettingsChange()
            }
            .store(in: &cancellables)

        // Apply the persisted language.
        LocalizationManager.shared.setLanguage(settingsVM.settings.language)

        // Apply language changes immediately (no debounce).
        settingsVM.$settings
            .map(\.language)
            .removeDuplicates()
            .sink { language in
                LocalizationManager.shared.setLanguage(language)
            }
            .store(in: &cancellables)

        // Buttons inside the SwiftUI popover navigate via NotificationCenter.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigationNotification(_:)),
            name: .coinscalNavigate,
            object: nil
        )

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--open-watchlist-for-ui-check") {
            DispatchQueue.main.async { [weak self] in
                self?.openSettingsWindow(tab: .watchlist)
            }
        }
#endif
    }

    /// Widgets open `coinscal://popover` when clicked (docs/WIDGET.md).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !Self.isRunningUnitTests, urls.contains(where: { $0.scheme == "coinscal" }) else { return }
        guard popover != nil else {
            opensPopoverAfterLaunch = true
            return
        }
        showPopoverFromURL()
    }

    /// Right after launch the status item is not on screen yet and `show` silently does nothing; retry briefly.
    private func showPopoverFromURL(retries: Int = 0) {
        if !popover.isShown { togglePopover() }
        guard !popover.isShown, retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showPopoverFromURL(retries: retries - 1)
        }
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        let selfPid = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .contains { $0.processIdentifier != selfPid }
    }

    @objc private func handleNavigationNotification(_ notification: Notification) {
        let rawValue = notification.userInfo?["tab"] as? String ?? SettingsTab.general.rawValue
        let tab = SettingsTab(rawValue: rawValue) ?? .general
        openSettingsWindow(tab: tab)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuBarVM.bind(to: coinListVM, settingsVM: settingsVM, statusItem: statusItem)

        guard let button = statusItem.button else { return }
        button.title = ""
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        // Show the popover right away; the default spring animation feels sluggish from the menu bar.
        popover.animates = false
        // Hide the anchor arrow between the popover and the status item (private KVC, common practice for menu bar apps).
        popover.setValue(true, forKey: "shouldHideAnchor")
        let popoverView = CoinPopoverView()
            .environmentObject(coinListVM)
            .environmentObject(settingsVM)
            .environment(\.coinLogoStore, logoStore)
        let hosting = NSHostingController(rootView: popoverView)
        hosting.view.wantsLayer = true
        hosting.view.layer?.isOpaque = false
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hosting
        syncPopoverSize(coinCount: coinListVM.coins.count)

        // Popover height follows the watchlist size: at least 4 rows, at most 8, then it scrolls.
        coinListVM.$coins
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.syncPopoverSize(coinCount: count)
            }
            .store(in: &cancellables)
    }

    private func syncPopoverSize(coinCount: Int) {
        popover.contentSize = NSSize(
            width: Constants.Popover.width,
            height: Constants.Popover.height(forCoinCount: coinCount)
        )
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            // An LSUIElement app must activate explicitly, otherwise clicks inside the popover are not routed.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()
        menu.showsStateColumn = false

        // Change - submenu to switch displayed coin
        let changeItem = NSMenuItem(title: loc("menu.change"), action: nil, keyEquivalent: "")
        let changeSubmenu = NSMenu()
        for watchlistCoin in settingsVM.settings.watchlistCoins {
            if let meta = catalog.metadata(for: watchlistCoin.coinId) {
                let item = NSMenuItem(
                    title: "\(meta.symbol) - \(meta.name)",
                    action: #selector(changeCoin(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = meta.id
                item.target = self
                if meta.id == settingsVM.settings.displayedCoinId {
                    item.state = .on
                }
                changeSubmenu.addItem(item)
            }
        }
        changeItem.submenu = changeSubmenu
        menu.addItem(changeItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem(title: loc("menu.setting"), action: #selector(openSettings), key: ""))
        menu.addItem(makeItem(title: loc("menu.about"),   action: #selector(openAbout),    key: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem(title: loc("menu.quit"),     action: #selector(handleQuit),   key: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = nil
        return item
    }

    @objc private func changeCoin(_ sender: NSMenuItem) {
        guard let coinId = sender.representedObject as? String else { return }
        settingsVM.settings.displayedCoinId = coinId
    }

    // MARK: - Settings Window

    @objc func openSettings() {
        openSettingsWindow(tab: .general)
    }

    @objc func openWatchlist() {
        openSettingsWindow(tab: .watchlist)
    }

    @objc func openAbout() {
        openSettingsWindow(tab: .about)
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    func openSettingsWindow(tab: SettingsTab) {
        // Close the popover so its transient event monitor does not steal focus.
        if popover.isShown { popover.performClose(nil) }
        // An LSUIElement app must activate first for the window to come to the front.
        NSApp.activate(ignoringOtherApps: true)
        settingsVM.settingsWindowTab = tab

        if let window = settingsWindow {
            // Do not replace contentViewController: a new NSHostingController makes the window resize to its content.
            window.makeKeyAndOrderFront(nil)
            return
        }
        let settingsView = SettingsWindow()
            .environmentObject(settingsVM)
            .environmentObject(coinListVM)
            .environmentObject(watchlistVM)
            .environment(\.coinLogoStore, logoStore)
        let initialSize = Constants.Window.settingsDefaultSize
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Initial title only: once shown, SwiftUI's navigationTitle (the selected pane) owns it.
        window.title = loc("window.settings.title")
        let hostingController = NSHostingController(rootView: settingsView)
        // Bridge navigationTitle and the toolbar to the window: a real unified title bar instead of a transparent one.
        hostingController.sceneBridgingOptions = [.title, .toolbars]
        window.contentViewController = hostingController
        // configureSettingsWindowChrome must run after contentViewController is set:
        // the NSHostingController layout pass resets the window's maxSize constraint.
        Self.configureSettingsWindowChrome(window)
        // Setting contentViewController resizes the window to the SwiftUI view's fitting size (its minimum, 600 wide),
        // which discards the contentRect above; apply the default again. A saved frame still wins below.
        window.setContentSize(initialSize)
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        Self.clampSettingsWindowFrame(window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    /// Settings-style window: full-size content under a unified toolbar showing the pane title;
    /// the sidebar runs the full height beside the traffic lights.
    private static func configureSettingsWindowChrome(_ window: NSWindow) {
        let min = Constants.Window.settingsMinSize
        let max = Constants.Window.settingsMaxSize
        window.minSize = NSSize(width: min.width, height: min.height)
        window.maxSize = NSSize(width: max.width, height: max.height)
        window.contentMinSize = NSSize(width: min.width, height: min.height)
        window.contentMaxSize = NSSize(width: max.width, height: max.height)
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        // An empty toolbar makes the title bar a unified toolbar: same height for every pane, title on the leading side.
        // (With no SwiftUI toolbar items, the bridge would otherwise create none and leave a plain 32pt title bar.)
        if window.toolbar == nil {
            window.toolbar = NSToolbar(identifier: "SettingsToolbar")
        }
        window.toolbarStyle = .unified
    }

    private static func clampSettingsWindowFrame(_ window: NSWindow) {
        let minSize = Constants.Window.settingsMinSize
        let maxSize = Constants.Window.settingsMaxSize
        var frame = window.frame
        frame.size.width = Swift.min(maxSize.width, Swift.max(minSize.width, frame.size.width))
        frame.size.height = Swift.min(maxSize.height, Swift.max(minSize.height, frame.size.height))
        window.setFrame(frame, display: false)
    }
}

// MARK: - NSPopoverDelegate
extension AppDelegate: NSPopoverDelegate {
    /// `.transient` closes on app deactivation, but a popover opened from a widget click belongs to an app that never
    /// became active (macOS 14 cooperative activation), so clicking the desktop did nothing. A global mouse monitor
    /// (no permission needed for mouse events) closes it on any click outside the app.
    func popoverDidShow(_ notification: Notification) {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // The NSHostingController layout pass can override maxSize at runtime;
        // windowWillResize fires on every drag resize, so it is a reliable place to clamp.
        let minSize = Constants.Window.settingsMinSize
        let maxSize = Constants.Window.settingsMaxSize
        return NSSize(
            width:  Swift.min(maxSize.width,  Swift.max(minSize.width,  frameSize.width)),
            height: Swift.min(maxSize.height, Swift.max(minSize.height, frameSize.height))
        )
    }

    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
    }
}

enum SettingsTab: String, CaseIterable {
    case general, watchlist, about
}

extension Notification.Name {
    /// Posted by buttons inside the SwiftUI popover to open a settings tab.
    /// userInfo: ["tab": SettingsTab.rawValue]
    static let coinscalNavigate = Notification.Name("coinscal.navigate")
    /// Posted by the settings window to drag the desktop overlay into place.
    static let coinscalAdjustDesktopOverlay = Notification.Name("coinscal.adjustDesktopOverlay")
}
