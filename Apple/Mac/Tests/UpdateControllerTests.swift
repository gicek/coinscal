import Testing
@testable import Coinscal

@MainActor
struct UpdateControllerTests {
    @Test func withoutBackendEverythingIsDisabled() {
        let controller = UpdateController()
        #expect(!controller.isAvailable)
        #expect(!controller.canCheckForUpdates)
        controller.checkForUpdates()
        controller.setAutomaticallyChecksForUpdates(true)
        #expect(!controller.automaticallyChecksForUpdates)
    }

    @Test func attachReadsBackendState() {
        let controller = UpdateController()
        let backend = FakeUpdaterBackend()
        backend.automaticallyChecksForUpdates = false
        controller.attach(backend)
        #expect(controller.isAvailable)
        #expect(controller.canCheckForUpdates)
        #expect(!controller.automaticallyChecksForUpdates)
    }

    @Test func checkForwardsOnlyWhenBackendCanCheck() {
        let controller = UpdateController()
        let backend = FakeUpdaterBackend()
        controller.attach(backend)
        controller.checkForUpdates()
        #expect(backend.checkCount == 1)

        backend.canCheckForUpdates = false
        controller.refresh()
        controller.checkForUpdates()
        #expect(backend.checkCount == 1)
        #expect(!controller.canCheckForUpdates)
    }

    @Test func automaticChecksPreferenceGoesToBackend() {
        let controller = UpdateController()
        let backend = FakeUpdaterBackend()
        controller.attach(backend)
        controller.setAutomaticallyChecksForUpdates(false)
        #expect(!backend.automaticallyChecksForUpdates)
        #expect(!controller.automaticallyChecksForUpdates)
    }

    @Test func reminderShowsUntilHandled() {
        let controller = UpdateController()
        controller.attach(FakeUpdaterBackend())
        #expect(!controller.updateAvailable)
        controller.scheduledUpdateFound()
        #expect(controller.updateAvailable)
        controller.updateReminderHandled()
        #expect(!controller.updateAvailable)
    }
}
