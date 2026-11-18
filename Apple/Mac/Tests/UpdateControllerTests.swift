import Foundation
import Testing
@testable import Coinscal

@MainActor
struct UpdateControllerTests {
    @Test func withoutBackendEverythingIsDisabled() {
        let controller = UpdateController(storage: InMemoryDataStorage())
        #expect(!controller.isAvailable)
        #expect(!controller.canCheckForUpdates)
        controller.checkForUpdates()
        controller.setAutomaticallyChecksForUpdates(true)
        #expect(!controller.automaticallyChecksForUpdates)
    }

    @Test func attachReadsBackendState() {
        let controller = UpdateController(storage: InMemoryDataStorage())
        let backend = FakeUpdaterBackend()
        backend.automaticallyChecksForUpdates = false
        controller.attach(backend)
        #expect(controller.isAvailable)
        #expect(controller.canCheckForUpdates)
        #expect(!controller.automaticallyChecksForUpdates)
    }

    @Test func checkForwardsOnlyWhenBackendCanCheck() {
        let controller = UpdateController(storage: InMemoryDataStorage())
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
        let controller = UpdateController(storage: InMemoryDataStorage())
        let backend = FakeUpdaterBackend()
        controller.attach(backend)
        controller.setAutomaticallyChecksForUpdates(false)
        #expect(!backend.automaticallyChecksForUpdates)
        #expect(!controller.automaticallyChecksForUpdates)
    }

    @Test func reminderShowsUntilHandled() {
        let controller = UpdateController(storage: InMemoryDataStorage(), currentBuild: "3")
        controller.attach(FakeUpdaterBackend())
        #expect(!controller.updateAvailable)
        controller.scheduledUpdateFound(build: "4")
        #expect(controller.updateAvailable)
        controller.updateReminderHandled()
        #expect(!controller.updateAvailable)
    }

    @Test func reminderSurvivesRelaunchUntilInstalledOrHandled() {
        let storage = InMemoryDataStorage()
        let first = UpdateController(storage: storage, currentBuild: "3")
        first.attach(FakeUpdaterBackend())
        first.scheduledUpdateFound(build: "10")

        let relaunched = UpdateController(storage: storage, currentBuild: "3")
        relaunched.attach(FakeUpdaterBackend())
        #expect(relaunched.updateAvailable, "build 10 is newer than 3 (numeric comparison)")

        let updated = UpdateController(storage: storage, currentBuild: "10")
        updated.attach(FakeUpdaterBackend())
        #expect(!updated.updateAvailable, "the found build is installed")
        let afterUpdate = UpdateController(storage: storage, currentBuild: "3")
        afterUpdate.attach(FakeUpdaterBackend())
        #expect(!afterUpdate.updateAvailable, "the stale reminder was cleared")

        relaunched.scheduledUpdateFound(build: "11")
        relaunched.updateReminderHandled()
        let handled = UpdateController(storage: storage, currentBuild: "3")
        handled.attach(FakeUpdaterBackend())
        #expect(!handled.updateAvailable)
    }

    @Test func automaticInstallsNeedAutomaticChecks() {
        let controller = UpdateController(storage: InMemoryDataStorage())
        let backend = FakeUpdaterBackend()
        controller.attach(backend)
        controller.setAutomaticallyInstallsUpdates(true)
        #expect(backend.automaticallyDownloadsUpdates)
        #expect(controller.automaticallyInstallsUpdates)

        controller.setAutomaticallyChecksForUpdates(false)
        #expect(!controller.canAutomaticallyInstallUpdates)
        #expect(!controller.automaticallyInstallsUpdates, "shown off while automatic checks are off")
        controller.setAutomaticallyInstallsUpdates(false)
        #expect(backend.automaticallyDownloadsUpdates, "ignored while not allowed")
    }

    @Test func feedFollowsTheAppLanguage() {
        let base = URL(string: "https://dl.coinscal.app/appcast.xml")!
        #expect(UpdateFeed.url(base: base, languageCode: "en").absoluteString == "https://dl.coinscal.app/appcast.en.xml")
        #expect(UpdateFeed.url(base: base, languageCode: "zh-Hant").absoluteString == "https://dl.coinscal.app/appcast.zh-Hant.xml")
        #expect(AppLanguage.zhHans.resourceCode == "zh-Hans", "the feed name uses the resource code")
    }
}
