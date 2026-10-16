import AppKit
import Combine
import Sparkle

/// The updater the UI talks to; Sparkle in the app, a fake in tests (docs/UPDATES.md).
@MainActor
protocol UpdaterBackend: AnyObject {
    /// False while a check or an update session is already running.
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}

/// Update state for the menu, the About pane, and the popover. Without a backend (unit-test host, or before
/// `attach`), every action is disabled.
@MainActor
final class UpdateController: ObservableObject {
    /// A scheduled check found an update but didn't show a window (Coinscal has no Dock icon, so it shouldn't
    /// steal focus); the popover shows "Update Available" until the user looks at it or the session ends.
    @Published private(set) var updateAvailable = false
    /// False in the unit-test host, where no updater runs.
    @Published private(set) var isAvailable = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    private var backend: UpdaterBackend?

    func attach(_ backend: UpdaterBackend) {
        self.backend = backend
        isAvailable = true
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

    func scheduledUpdateFound() {
        updateAvailable = true
    }

    func updateReminderHandled() {
        updateAvailable = false
    }

    func refresh() {
        canCheckForUpdates = backend?.canCheckForUpdates ?? false
        automaticallyChecksForUpdates = backend?.automaticallyChecksForUpdates ?? false
    }
}

/// Sparkle's standard updater with gentle reminders for scheduled checks. Feed URL, public key, and check interval
/// come from Info.plist. Sparkle's standard user driver calls its delegate on the main thread, hence the
/// `@preconcurrency` conformance (checked at runtime).
@MainActor
final class SparkleUpdaterBackend: NSObject, UpdaterBackend, @preconcurrency SPUStandardUserDriverDelegate {
    private weak var controller: UpdateController?
    private var updaterController: SPUStandardUpdaterController!
    private var observation: NSKeyValueObservation?

    init(controller: UpdateController) {
        self.controller = controller
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
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

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Show Sparkle's window right away only when the app is already in front; otherwise remind in the popover.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate && !state.userInitiated {
            controller?.scheduledUpdateFound()
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        controller?.updateReminderHandled()
    }

    func standardUserDriverWillFinishUpdateSession() {
        controller?.updateReminderHandled()
    }
}
