import Foundation
import OSLog
import ServiceManagement

@MainActor
final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()
    private static let logger = Logger(subsystem: "com.gicek.coinscal", category: "LaunchAtLogin")

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
