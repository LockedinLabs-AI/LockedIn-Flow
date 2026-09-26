import Foundation

/// Main-actor ownership for one re-insertion task. Cancellation marks the task,
/// cancels only while delivery is still reversible, and retains its lease until
/// the task reports a terminal result. That keeps a second re-insertion blocked
/// while a dispatched paste is still resolving. Pre-event cancellation is
/// reported only when the cancelled task finishes; post-event outcomes can
/// instead surface a truthful result or inspection notice. An inspection
/// notice keeps new re-insertions blocked until the user explicitly
/// acknowledges that notice. A stale task can finish or clear only state
/// created by its own lease.
@MainActor
public final class ReinsertTaskGate {
    public struct Lease: Equatable {
        fileprivate let identifier: UUID
    }

    /// Opaque identity for a terminal outcome that the user must inspect
    /// before another re-insertion becomes available. It is derived from the
    /// task lease, so a stale view cannot acknowledge a newer outcome.
    public struct Inspection: Equatable, Sendable {
        fileprivate let leaseIdentifier: UUID
    }

    private enum Phase: Equatable {
        case preparing
        case deliveryCommitted
    }

    private struct Pending {
        let lease: Lease
        var task: Task<Void, Never>?
        var cancellationRequested: Bool
        var phase: Phase
    }

    private var pending: Pending?
    private var pendingInspection: Inspection?

    public init() {}

    public var hasPendingTask: Bool { pending != nil }
    public var hasPendingInspection: Bool { pendingInspection != nil }

    public func begin() -> Lease? {
        guard pending == nil, pendingInspection == nil else { return nil }
        let lease = Lease(identifier: UUID())
        pending = Pending(
            lease: lease,
            task: nil,
            cancellationRequested: false,
            phase: .preparing
        )
        return lease
    }

    public func attach(_ task: Task<Void, Never>, to lease: Lease) {
        guard var current = pending, current.lease == lease else {
            task.cancel()
            return
        }
        current.task = task
        pending = current
        // `begin` and `attach` are normally adjacent MainActor operations,
        // but keep the primitive correct if cancellation is requested between
        // them by a future caller.
        if current.cancellationRequested, current.phase == .preparing {
            task.cancel()
        }
    }

    public func permitsEffects(for lease: Lease) -> Bool {
        pending?.lease == lease
    }

    public func cancellationRequested(for lease: Lease) -> Bool {
        guard pending?.lease == lease else { return false }
        return pending?.cancellationRequested == true
    }

    /// Atomically crosses the irreversible AX-setter/Cmd+V boundary. A cancel
    /// already requested while preflight was still reversible wins and refuses
    /// the commit. Once committed, later cancellation retains the lease but
    /// lets receipt verification reach a truthful terminal result.
    public func commitDelivery(_ lease: Lease) -> Bool {
        guard var current = pending,
            current.lease == lease,
            !current.cancellationRequested,
            current.phase == .preparing
        else { return false }
        current.phase = .deliveryCommitted
        pending = current
        return true
    }

    public func deliveryWasCommitted(for lease: Lease) -> Bool {
        pending?.lease == lease && pending?.phase == .deliveryCommitted
    }

    /// Finishes the active task. Unknown delivery or clipboard outcomes can
    /// atomically leave an inspection latch behind before the task lease is
    /// released. The returned token is the only token that can clear it.
    @discardableResult
    public func finish(
        _ lease: Lease,
        requiringInspection: Bool = false
    ) -> Inspection? {
        guard let current = pending, current.lease == lease else { return nil }
        pending = nil
        guard requiringInspection else { return nil }
        let inspection = Inspection(leaseIdentifier: lease.identifier)
        pendingInspection = inspection
        return inspection
    }

    /// Clears only the exact terminal inspection presented to the user. This
    /// method never begins an insertion or posts an event.
    @discardableResult
    public func acknowledgeInspection(_ inspection: Inspection) -> Bool {
        guard pendingInspection == inspection else { return false }
        pendingInspection = nil
        return true
    }

    @discardableResult
    public func cancelAll() -> Bool {
        guard var current = pending else { return false }
        guard !current.cancellationRequested else { return true }
        current.cancellationRequested = true
        pending = current
        if current.phase == .preparing {
            current.task?.cancel()
        }
        return true
    }
}
