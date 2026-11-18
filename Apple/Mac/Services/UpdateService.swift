import AppKit
import Combine
import Sparkle

/// The updater the UI talks to; Sparkle in the app, a fake in tests (docs/ARCHITECTURE.md, "Updates").
@MainActor
protocol UpdaterBackend: AnyObject {
    /// False while a check or an update session is already running.
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    /// Download and install found updates without asking (Sparkle's "automatically install" option).
    var automaticallyDownloadsUpdates: Bool { get set }
    /// False while automatic checks are off: automatic installs depend on them.
    var allowsAutomaticUpdates: Bool { get }
    func checkForUpdates()
}

/// Update state for the menu, the About pane, and the popover. Without a backend (unit-test host, or before
/// `attach`), every action is disabled.
@MainActor
final class UpdateController: ObservableObject {
    /// Build number of an update a scheduled check found and the user hasn't looked at yet.
    static let pendingBuildKey = "pendingUpdateBuild"

    /// A scheduled check found an update but didn't show a window (Coinscal has no Dock icon, so it shouldn't
    /// steal focus); the popover shows "Update Available" until the user looks at it or the session ends.
    /// The found build is remembered, so the reminder survives a relaunch while this build is older.
    @Published private(set) var updateAvailable = false
    /// False in the unit-test host, where no updater runs.
    @Published private(set) var isAvailable = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyInstallsUpdates = false
    @Published private(set) var canAutomaticallyInstallUpdates = false

    private var backend: UpdaterBackend?
    private let storage: SettingsDataStorage
    private let currentBuild: String

    init(
        storage: SettingsDataStorage = UserDefaults.standard,
        currentBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    ) {
        self.storage = storage
        self.currentBuild = currentBuild
    }

    func attach(_ backend: UpdaterBackend) {
        self.backend = backend
        isAvailable = true
        if let pending = pendingBuild, Self.isNewer(pending, than: currentBuild) {
            updateAvailable = true
        } else {
            pendingBuild = nil
        }
        refresh()
    }

    /// Opens Sparkle's update window: the found update if there is one, otherwise a fresh check.
    func checkForUpdates() {
        guard let backend, backend.canCheckForUpdates else { return }
        // An LSUIElement app must activate first for Sparkle's window to come to the front.
        NSApp.activate(ignoringOtherApps: true)
        backend.checkForUpdates()
        refresh()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        backend?.automaticallyChecksForUpdates = enabled
        refresh()
    }

    func setAutomaticallyInstallsUpdates(_ enabled: Bool) {
        guard let backend, backend.allowsAutomaticUpdates else { return }
        backend.automaticallyDownloadsUpdates = enabled
        refresh()
    }

    func scheduledUpdateFound(build: String) {
        pendingBuild = build
        updateAvailable = true
    }

    func updateReminderHandled() {
        pendingBuild = nil
        updateAvailable = false
    }

    func refresh() {
        canCheckForUpdates = backend?.canCheckForUpdates ?? false
        automaticallyChecksForUpdates = backend?.automaticallyChecksForUpdates ?? false
        canAutomaticallyInstallUpdates = backend?.allowsAutomaticUpdates ?? false
        automaticallyInstallsUpdates = canAutomaticallyInstallUpdates && (backend?.automaticallyDownloadsUpdates ?? false)
    }

    private var pendingBuild: String? {
        get { storage.data(forKey: Self.pendingBuildKey).flatMap { String(data: $0, encoding: .utf8) } }
        set { storage.set(newValue.map { Data($0.utf8) }, forKey: Self.pendingBuildKey) }
    }

    /// Build numbers compare numerically ("10" is newer than "9").
    static func isNewer(_ build: String, than current: String) -> Bool {
        build.compare(current, options: .numeric) == .orderedDescending
    }
}

/// The appcast for one UI language. Sparkle picks among localized release notes by the system language, so the app
/// asks for a feed that carries only the notes in its own language: `appcast.xml` becomes `appcast.<code>.xml`.
/// `appcast.xml` keeps every language for builds without this lookup.
enum UpdateFeed {
    static func url(base: URL, languageCode: String) -> URL {
        let name = base.deletingPathExtension().lastPathComponent
        return base.deletingLastPathComponent().appendingPathComponent("\(name).\(languageCode).\(base.pathExtension)")
    }
}

/// Sparkle's standard updater with gentle reminders for scheduled checks. Public key and check interval come from
/// Info.plist; the feed follows the in-app language (`UpdateFeed`). Sparkle calls its delegates on the main thread;
/// `SPUUpdaterDelegate` is main-actor isolated, and the user driver delegate needs a `@preconcurrency` conformance.
@MainActor
final class SparkleUpdaterBackend: NSObject, UpdaterBackend, SPUUpdaterDelegate,
    @preconcurrency SPUStandardUserDriverDelegate {
    private weak var controller: UpdateController?
    private var updaterController: SPUStandardUpdaterController!
    private var observation: NSKeyValueObservation?

    init(controller: UpdateController) {
        self.controller = controller
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        observation = updaterController.updater.observe(\.canCheckForUpdates) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.controller?.refresh() }
        }
    }

    var canCheckForUpdates: Bool { updaterController.updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }

    var allowsAutomaticUpdates: Bool { updaterController.updater.allowsAutomaticUpdates }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    /// Read before every check, so a language change applies to the next one.
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard let base = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:))
        else { return nil }
        return UpdateFeed.url(base: base, languageCode: LocalizationManager.shared.language.resourceCode).absoluteString
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Show Sparkle's window right away only when the app is already in front; otherwise remind in the popover.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate && !state.userInitiated {
            controller?.scheduledUpdateFound(build: update.versionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        controller?.updateReminderHandled()
    }

    func standardUserDriverWillFinishUpdateSession() {
        controller?.updateReminderHandled()
    }
}
