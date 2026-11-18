import SwiftUI

@main
struct CoinscalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        guard !AppDelegate.isRunningUnitTests else { return }
        // No icons in front of menu items. macOS 26 attaches action images to items such as "Settings" and reads
        // this key before `applicationDidFinishLaunching`, so set it here, before any menu exists. The app domain
        // also wins over a global `NSMenuEnableActionImages = YES`.
        UserDefaults.standard.set(false, forKey: "NSMenuEnableActionImages")
    }

    var body: some Scene {
        // Required scene, never shown: the app menu's Settings item opens the AppKit settings window instead.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(loc("menu.setting")) {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
