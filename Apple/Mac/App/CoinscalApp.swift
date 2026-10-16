import SwiftUI

@main
struct CoinscalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // No icons in front of menu items. macOS 26 attaches action images to items such as "Settings" and reads
        // this key before `applicationDidFinishLaunching`, so set it here, before any menu exists. The app domain
        // also wins over a global `NSMenuEnableActionImages = YES`.
        UserDefaults.standard.set(false, forKey: "NSMenuEnableActionImages")
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
