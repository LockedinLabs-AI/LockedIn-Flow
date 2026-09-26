import AppKit
import KeyboardShortcuts
import VoiceCore

/// Owns the shipped shortcut default and the one-time move away from bare Fn.
/// Bare modifier keys are unusually collision-prone because another dictation
/// app can observe the same press and start its own microphone path. Control-
/// Shift-Space is a conventional full chord and avoids the common macOS
/// Control-Space and Command-Space bindings.
enum DictationShortcutPreference {
    static let currentDefault = KeyboardShortcuts.Shortcut(
        .space,
        modifiers: [.control, .shift]
    )
    static let bareFunction = KeyboardShortcuts.Shortcut(
        .function,
        modifiers: []
    )

    private static let migrationVersionKey = "dictationShortcutMigrationVersion"
    private static let migrationNoticePendingKey = "dictationShortcutMigrationNoticePending"

    static var migrationNoticeIsPending: Bool {
        UserDefaults.standard.bool(forKey: migrationNoticePendingKey)
    }

    @discardableResult
    @MainActor
    static func migrateLegacyDefaultIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        let storedShortcut = KeyboardShortcuts.getShortcut(for: .holdToTalk)
        let signature = storedShortcut.map {
            ShortcutPreferenceSignature(
                keyCode: $0.carbonKeyCode,
                modifierFlags: $0.carbonModifiers
            )
        }
        let completedVersion = defaults.integer(forKey: migrationVersionKey)
        let didMigrate = DictationShortcutMigrationPolicy.shouldReplaceLegacyDefault(
            completedVersion: completedVersion,
            storedShortcut: signature
        )

        if didMigrate {
            // Persist the explanation before changing either the shortcut or
            // migration version. If the process exits between these writes,
            // the next launch still has a durable notice to present.
            defaults.set(true, forKey: migrationNoticePendingKey)
            KeyboardShortcuts.setShortcut(currentDefault, for: .holdToTalk)
        }

        if completedVersion < DictationShortcutMigrationPolicy.currentVersion {
            defaults.set(
                DictationShortcutMigrationPolicy.currentVersion,
                forKey: migrationVersionKey
            )
        }

        return didMigrate
    }

    static func setMigrationNoticePending(_ isPending: Bool) {
        UserDefaults.standard.set(isPending, forKey: migrationNoticePendingKey)
    }

    @MainActor
    static func useBareFunctionShortcut() {
        // Record the migration before setting Fn so this explicit choice is
        // never mistaken for the old default on a later launch.
        UserDefaults.standard.set(
            DictationShortcutMigrationPolicy.currentVersion,
            forKey: migrationVersionKey
        )
        KeyboardShortcuts.setShortcut(bareFunction, for: .holdToTalk)
    }

    @MainActor
    static func useRecommendedShortcut() {
        KeyboardShortcuts.setShortcut(currentDefault, for: .holdToTalk)
    }
}
