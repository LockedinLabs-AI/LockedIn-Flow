import Foundation

/// Main-actor state for an asynchronous attempt to open the microphone.
///
/// A lease is tied to the input gesture that requested capture. Hold-to-talk
/// leases are revoked when that key is released; toggle, floating-bar, and
/// meeting leases deliberately survive an unrelated hold-key release. A stale
/// task can finish only its own lease, so it cannot clear a newer attempt.
public struct CaptureStartGate: Sendable {
    public struct Lease: Sendable, Equatable {
        fileprivate let identifier: UUID
    }

    private struct Pending: Sendable {
        let lease: Lease
        let requiresHeldTrigger: Bool
    }

    private var pending: Pending?

    public init() {}

    public var hasPendingAttempt: Bool { pending != nil }

    public mutating func begin(requiresHeldTrigger: Bool) -> Lease? {
        guard pending == nil else { return nil }
        let lease = Lease(identifier: UUID())
        pending = Pending(
            lease: lease,
            requiresHeldTrigger: requiresHeldTrigger
        )
        return lease
    }

    public func permitsStart(for lease: Lease) -> Bool {
        pending?.lease == lease
    }

    public mutating func finish(_ lease: Lease) {
        guard pending?.lease == lease else { return }
        pending = nil
    }

    public mutating func cancelAll() {
        pending = nil
    }

    /// Revokes only a capture that originated from the hold shortcut.
    /// Returns true when a pending attempt was cancelled.
    @discardableResult
    public mutating func holdTriggerReleased() -> Bool {
        guard pending?.requiresHeldTrigger == true else { return false }
        pending = nil
        return true
    }
}
