import AppKit
import KeyboardShortcuts
import VoiceCore

extension Notification.Name {
    /// AppDelegate stays independent of AppState; the state object observes this
    /// request and opens the retained Home window on the main actor.
    static let lockedInFlowShowHome = Notification.Name("LockedInFlow.ShowHome")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu-bar agent: no Dock icon
        terminateDuplicateInstances()

        // A normal Finder/Applications launch should feel like opening an app,
        // not like starting an invisible agent. Do not infer the current launch
        // source from the Launch at Login preference: that preference can remain
        // enabled when the user later opens the app manually.
        let isDefaultLaunch =
            notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        let onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        if isDefaultLaunch, onboardingComplete {
            requestHomeWindow()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        requestHomeWindow()
        return true
    }

    /// Dev cycles and manual relaunches can leave zombies behind. Duplicates mean
    /// double hotkeys and dueling bars — exactly the "app disappeared" weirdness.
    /// On launch, the newest instance wins and the rest are terminated.
    private func terminateDuplicateInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others =
            NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me }
        for other in others {
            other.terminate()
        }
        if !others.isEmpty {
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                for other in others where !other.isTerminated {
                    other.forceTerminate()
                }
            }
        }
    }

    private func requestHomeWindow() {
        // AppState is constructed by SwiftUI before didFinishLaunching in normal
        // app startup. Dispatching one turn also makes that ordering explicit.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .lockedInFlowShowHome, object: nil)
        }
    }
}

extension KeyboardShortcuts.Name {
    /// Global shortcut used by the selected hold or toggle activation mode.
    static let holdToTalk = Self(
        "holdToTalk",
        default: DictationShortcutPreference.currentDefault
    )
}
