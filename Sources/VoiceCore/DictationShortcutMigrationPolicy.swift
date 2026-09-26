/// Content-free identity for a stored global shortcut.
///
/// The app keeps the platform-specific shortcut registration in its macOS
/// target. This small value lets the one-time preference migration remain
/// deterministic and testable without reading or writing user defaults.
public struct ShortcutPreferenceSignature: Equatable, Sendable {
    public let keyCode: Int
    public let modifierFlags: Int

    public init(keyCode: Int, modifierFlags: Int) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

/// Decides whether an existing shortcut is the exact legacy LockedIn Flow
/// default that must be moved away from bare Fn.
///
/// Versioning is intentionally separate from the shortcut value: after this
/// migration has run, a user can choose bare Fn again and the app will preserve
/// that explicit choice on every later launch.
public enum DictationShortcutMigrationPolicy {
    public static let currentVersion = 1

    /// Carbon key code 63 is the standalone Function/Fn key. The previous
    /// LockedIn Flow default stored it with no modifiers.
    public static let legacyBareFunction = ShortcutPreferenceSignature(
        keyCode: 63,
        modifierFlags: 0
    )

    public static func shouldReplaceLegacyDefault(
        completedVersion: Int,
        storedShortcut: ShortcutPreferenceSignature?
    ) -> Bool {
        completedVersion < currentVersion
            && storedShortcut == legacyBareFunction
    }
}

/// Keeps the upgrade explanation pending until it can be presented in a ready
/// app, and until the user explicitly acknowledges it. The persistence itself
/// remains in the macOS app target; this policy is content-free and testable.
public enum DictationShortcutMigrationNoticePolicy {
    public static func pendingAfterLaunch(
        persistedPending: Bool,
        migrationDidOccur: Bool
    ) -> Bool {
        persistedPending || migrationDidOccur
    }

    public static func shouldPresent(
        isPending: Bool,
        modelIsReady: Bool
    ) -> Bool {
        isPending && modelIsReady
    }
}
