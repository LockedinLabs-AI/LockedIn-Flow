import KeyboardShortcuts
import SwiftUI

@main
struct LockedInFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    init() {
        #if LOCKEDIN_INTERNAL_DIAGNOSTICS
            // Internal developer/UAT commands run before the menu-bar app starts.
            // The call and implementation do not exist in production builds.
            SelfTest.runIfRequested()
        #endif
    }

    var body: some Scene {
        MenuBarExtra("LockedIn Flow", systemImage: state.menuBarIcon) {
            MenuBarView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
