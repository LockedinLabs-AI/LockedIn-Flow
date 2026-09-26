import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService. Only meaningful for the packaged .app;
/// fails gracefully (and reports honestly) for unpackaged dev binaries.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @MainActor
    static func set(_ enabled: Bool, state: AppState) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            state.statusMessage = "Launch at login requires the packaged app."
            state.launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
