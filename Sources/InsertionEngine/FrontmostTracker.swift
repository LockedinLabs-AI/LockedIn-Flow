import AppKit
import VoiceCore

/// Immutable identity of an application selected at an explicit workflow boundary.
///
/// Holding the process identifier together with the bundle identifier prevents
/// a completed transcript from following a later focus change to another app.
/// The app name is retained for truthful recovery/history labels and as an
/// additional identity check when macOS exposes it.
public struct InsertionFocusLock: Sendable, Equatable {
    public let processIdentifier: pid_t
    public let bundleIdentifier: String
    public let appName: String?
    /// Monotonic token for the most recent distinct non-self activation seen
    /// when this target was frozen. It lets background AX insertion distinguish
    /// our own overlay taking focus from an intervening application switch.
    public let activationGeneration: UInt64

    public init?(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        appName: String?,
        activationGeneration: UInt64 = 0
    ) {
        guard processIdentifier > 0,
            let bundleIdentifier = bundleIdentifier?.trimmingCharacters(
                in: .whitespacesAndNewlines),
            !bundleIdentifier.isEmpty
        else { return nil }
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.activationGeneration = activationGeneration
    }

    public func matches(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        appName: String?
    ) -> Bool {
        guard self.processIdentifier == processIdentifier,
            self.bundleIdentifier == bundleIdentifier
        else { return false }
        guard let expectedName = self.appName else { return true }
        return expectedName == appName
    }
}

/// Target identity and formatting semantics captured from one synchronized
/// tracker snapshot. Keeping these together prevents a deferred workspace UI
/// update from pairing one app's insertion target with another app's profile.
public struct InsertionTargetSnapshot: Sendable, Equatable {
    public let focusLock: InsertionFocusLock?
    public let profile: AppProfile
}

/// Remembers which non-LockedIn Flow application was most recently active,
/// so dictation lands in the app the user was working in — not in our own UI.
public final class FrontmostTracker: @unchecked Sendable {
    public static let shared = FrontmostTracker()

    private let lock = NSLock()
    private var lastPID: pid_t?
    private var lastBundleID: String?
    private var lastAppName: String?
    private var activationGeneration: UInt64 = 0

    init() {}

    public func noteActivation(pid: pid_t, bundleID: String?, appName: String?, isSelf: Bool) {
        guard !isSelf else { return }
        lock.lock()
        if lastPID != pid || lastBundleID != bundleID || lastAppName != appName {
            activationGeneration &+= 1
        }
        lastPID = pid
        lastBundleID = bundleID
        lastAppName = appName
        lock.unlock()
    }

    public func targetPID() -> pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return lastPID
    }

    public func targetBundleID() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastBundleID
    }

    public func targetAppName() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastAppName
    }

    /// Atomically freezes the complete application identity at the caller's
    /// workflow boundary. Reading PID, bundle ID, and name separately could
    /// otherwise describe different activations if focus changes between calls.
    public func focusLock() -> InsertionFocusLock? {
        lock.lock()
        defer { lock.unlock() }
        return makeFocusLock()
    }

    /// Freezes the destination application and resolves its automatic profile
    /// from the same synchronized identity. An explicit user override still wins.
    public func targetSnapshot(profileOverrideID: String?) -> InsertionTargetSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let focusLock = makeFocusLock()
        let override = profileOverrideID.flatMap { id in
            AppProfile.builtIn.first(where: { $0.id == id })
        }
        let profile =
            override
            ?? AppProfile.profile(forBundleID: focusLock?.bundleIdentifier)
        return InsertionTargetSnapshot(focusLock: focusLock, profile: profile)
    }

    /// Used at the insertion boundary to verify that our own UI becoming
    /// frontmost did not conceal a switch through a different application.
    public func currentActivationGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return activationGeneration
    }

    private func makeFocusLock() -> InsertionFocusLock? {
        guard let lastPID else { return nil }
        return InsertionFocusLock(
            processIdentifier: lastPID,
            bundleIdentifier: lastBundleID,
            appName: lastAppName,
            activationGeneration: activationGeneration
        )
    }

    /// Snapshot of whatever is frontmost *right now* (used by the CLI self-test,
    /// where our app is not the active one).
    public static func currentlyFrontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}
