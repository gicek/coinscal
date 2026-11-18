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
    private var menuBarPanel: MenuBarPanelController!
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
    /// Always present for the views; Sparkle is attached only outside the unit-test host (docs/ARCHITECTURE.md, "Updates").
    let updateController = UpdateController()
    /// A widget click launched the app: the URL arrives before the panel exists, so it is shown after setup.
    private var opensPanelAfterLaunch = false
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

        updateController.attach(SparkleUpdaterBackend(controller: updateController))
        setupStatusItem()
        setupMenuBarPanel()
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
        if opensPanelAfterLaunch {
            opensPanelAfterLaunch = false
            showPanelFromURL(retries: 10)
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

        // Buttons inside the menu bar panel navigate via NotificationCenter.
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

    /// Widgets open `coinscal://popover` when clicked (docs/ARCHITECTURE.md, "Widgets").
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !Self.isRunningUnitTests, urls.contains(where: { $0.scheme == WidgetStyle.urlScheme }) else { return }
        guard menuBarPanel != nil else {
            opensPanelAfterLaunch = true
            return
        }
        showPanelFromURL()
    }

    /// Right after launch the status item is not on screen yet and `show()` returns false; retry briefly.
    private func showPanelFromURL(retries: Int = 0) {
        guard !menuBarPanel.show(), retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showPanelFromURL(retries: retries - 1)
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
            menuBarPanel.close()
            showContextMenu()
        } else {
            menuBarPanel.toggle()
        }
    }

    // MARK: - Menu Bar Panel

    private func setupMenuBarPanel() {
        let panelView = CoinPopoverView()
            .environmentObject(coinListVM)
            .environmentObject(settingsVM)
            .environmentObject(updateController)
            .environment(\.coinLogoStore, logoStore)
        let hostingView = MenuBarPanelHostingView(rootView: panelView)
        // The panel sets its own size from `Constants.Popover`; don't let the SwiftUI content resize the window.
        hostingView.sizingOptions = []
        menuBarPanel = MenuBarPanelController(
            contentView: hostingView,
            size: panelSize(coinCount: coinListVM.coins.count),
            statusItemWindow: { [weak self] in self?.statusItem.button?.window }
        )

        // Panel height follows the watchlist size: at least 4 rows, at most 8, then it scrolls.
        coinListVM.$coins
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self else { return }
                self.menuBarPanel.setContentSize(self.panelSize(coinCount: count))
            }
            .store(in: &cancellables)
    }

    private func panelSize(coinCount: Int) -> CGSize {
        CGSize(width: Constants.Popover.width, height: Constants.Popover.height(forCoinCount: coinCount))
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()
        menu.showsStateColumn = false
        // Items are enabled as set below (the update item is disabled while a check is running).
        menu.autoenablesItems = false

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
        let updateItem = makeItem(title: loc("menu.checkForUpdates"), action: #selector(checkForUpdates), key: "")
        updateItem.isEnabled = updateController.canCheckForUpdates
        menu.addItem(updateItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem(title: loc("menu.quit"),     action: #selector(handleQuit),   key: "q"))
        hideItemImages(in: menu)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Text-only menu. macOS 27 adds a system symbol to standard items such as "Settings" on its own, even with
    /// `NSMenuEnableActionImages` off (see `CoinscalApp`); hide images on every item, submenus included.
    private func hideItemImages(in menu: NSMenu) {
        guard #available(macOS 27, *) else { return }
        for item in menu.items where !item.isSeparatorItem {
            item.preferredImageVisibility = .hidden
            if let submenu = item.submenu { hideItemImages(in: submenu) }
        }
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

    @objc private func checkForUpdates() {
        updateController.checkForUpdates()
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    func openSettingsWindow(tab: SettingsTab) {
        menuBarPanel.close()
        // An LSUIElement app must activate first for the window to come to the front.
        NSApp.activate(ignoringOtherApps: true)
        settingsVM.settingsWindowTab = tab

        if let window = settingsWindow {
            // Do not replace contentViewController: a new NSHostingController makes the window resize to its content.
            bringToFront(window)
            return
        }
        let settingsView = SettingsWindow()
            .environmentObject(settingsVM)
            .environmentObject(coinListVM)
            .environmentObject(watchlistVM)
            .environmentObject(updateController)
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
        bringToFront(window)
        settingsWindow = window
    }

    /// Coinscal is usually not the active app here (the menu bar panel doesn't activate it), and macOS may decline
    /// the activation request; ordering the window front regardless keeps it from opening behind the active app.
    private func bringToFront(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
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
    /// Posted by buttons inside the menu bar panel to open a settings tab.
    /// userInfo: ["tab": SettingsTab.rawValue]
    static let coinscalNavigate = Notification.Name("coinscal.navigate")
    /// Posted by the settings window to drag the desktop overlay into place.
    static let coinscalAdjustDesktopOverlay = Notification.Name("coinscal.adjustDesktopOverlay")
}
