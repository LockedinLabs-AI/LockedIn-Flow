import XCTest
@testable import VoiceCore

@MainActor
final class ReinsertTaskGateTests: XCTestCase {
    func testCancellationRevokesSuspendedPreflightAndReportsCancellationOnce() async throws {
        let gate = ReinsertTaskGate()
        var activationCount = 0
        var eventCount = 0
        var completionCount = 0
        var completionWasCancellation = false
        let lease = try XCTUnwrap(gate.begin())

        let task = Task { @MainActor in
            var reportsCancellation = false
            defer {
                gate.finish(lease)
                if reportsCancellation {
                    completionCount += 1
                    completionWasCancellation = true
                }
            }
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch is CancellationError {
                reportsCancellation = true
                return
            } catch {
                XCTFail("unexpected preflight failure: \(error)")
                return
            }
            activationCount += 1
            eventCount += 1
            completionCount += 1
        }
        gate.attach(task, to: lease)

        XCTAssertTrue(gate.cancelAll())
        XCTAssertTrue(gate.hasPendingTask)
        XCTAssertTrue(gate.cancellationRequested(for: lease))
        XCTAssertFalse(gate.deliveryWasCommitted(for: lease))
        XCTAssertFalse(gate.commitDelivery(lease))
        XCTAssertNil(gate.begin(), "a cancelled task retains its lease until terminal")
        XCTAssertEqual(completionCount, 0)
        await task.value

        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(eventCount, 0)
        XCTAssertEqual(completionCount, 1)
        XCTAssertTrue(completionWasCancellation)
        XCTAssertFalse(gate.hasPendingTask)
    }

    func testTaskAttachedAfterPreEventCancellationIsCancelledImmediately() async throws {
        let gate = ReinsertTaskGate()
        let lease = try XCTUnwrap(gate.begin())
        XCTAssertTrue(gate.cancelAll())

        var observedCancellation = false
        let task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch is CancellationError {
                observedCancellation = true
            } catch {
                XCTFail("unexpected attach failure: \(error)")
            }
            gate.finish(lease)
        }
        gate.attach(task, to: lease)
        await task.value

        XCTAssertTrue(observedCancellation)
        XCTAssertFalse(gate.hasPendingTask)
    }

    func testCancelledTaskCannotFinishReplacementLease() async throws {
        let gate = ReinsertTaskGate()
        let stale = try XCTUnwrap(gate.begin())
        let staleTask = Task { @MainActor in await Task.yield() }
        gate.attach(staleTask, to: stale)
        gate.cancelAll()

        XCTAssertNil(gate.begin())
        gate.finish(stale)
        let replacement = try XCTUnwrap(gate.begin())
        gate.finish(stale)

        XCTAssertTrue(gate.permitsEffects(for: replacement))
        XCTAssertFalse(gate.commitDelivery(stale))
        XCTAssertTrue(gate.commitDelivery(replacement))
        gate.finish(replacement)
        XCTAssertFalse(gate.hasPendingTask)
    }

    func testPostEventCancellationDefersReleaseUntilTerminalSafetyOutcome() async throws {
        let gate = ReinsertTaskGate()
        var eventCount = 0
        var terminalSafetyNoticeCount = 0
        var terminalInspection: ReinsertTaskGate.Inspection?
        var releaseReceipt: CheckedContinuation<Void, Never>?
        let lease = try XCTUnwrap(gate.begin())

        let task = Task { @MainActor in
            guard gate.commitDelivery(lease) else { return }
            eventCount += 1
            await withCheckedContinuation { continuation in
                releaseReceipt = continuation
            }
            if gate.cancellationRequested(for: lease) {
                // Models the controller preserving the terminal result instead
                // of publishing an immediate pre-event cancellation.
                terminalSafetyNoticeCount += 1
            }
            terminalInspection = gate.finish(
                lease,
                requiringInspection: true
            )
        }
        gate.attach(task, to: lease)
        while releaseReceipt == nil { await Task.yield() }

        XCTAssertTrue(gate.cancelAll())
        XCTAssertTrue(gate.cancelAll(), "repeated cancellation is idempotent")
        XCTAssertEqual(eventCount, 1)
        XCTAssertTrue(gate.deliveryWasCommitted(for: lease))
        XCTAssertTrue(gate.hasPendingTask)
        XCTAssertNil(gate.begin(), "no second event may queue during receipt")

        releaseReceipt?.resume()
        await task.value

        XCTAssertEqual(eventCount, 1)
        XCTAssertEqual(terminalSafetyNoticeCount, 1)
        XCTAssertFalse(gate.hasPendingTask)
        XCTAssertTrue(gate.hasPendingInspection)
        XCTAssertNil(
            gate.begin(),
            "terminal unknown delivery must remain non-retryable before acknowledgement"
        )

        let inspection = try XCTUnwrap(terminalInspection)
        XCTAssertTrue(gate.acknowledgeInspection(inspection))
        XCTAssertEqual(eventCount, 1, "acknowledgement never posts an event")

        let deliberateRetry = try XCTUnwrap(gate.begin())
        XCTAssertTrue(gate.commitDelivery(deliberateRetry))
        eventCount += 1
        gate.finish(deliberateRetry)
        XCTAssertEqual(eventCount, 2, "retry requires a separate post-acknowledgement action")
    }

    func testStaleInspectionCannotClearANewerNotice() throws {
        let gate = ReinsertTaskGate()
        let firstLease = try XCTUnwrap(gate.begin())
        let first = try XCTUnwrap(
            gate.finish(firstLease, requiringInspection: true)
        )
        XCTAssertTrue(gate.acknowledgeInspection(first))

        let secondLease = try XCTUnwrap(gate.begin())
        let second = try XCTUnwrap(
            gate.finish(secondLease, requiringInspection: true)
        )

        XCTAssertFalse(gate.acknowledgeInspection(first))
        XCTAssertTrue(gate.hasPendingInspection)
        XCTAssertNil(gate.begin())
        XCTAssertTrue(gate.acknowledgeInspection(second))
        XCTAssertFalse(gate.hasPendingInspection)
    }

    func testConfirmedDeliveryCanRequireInspectionBeforeAnotherAttempt() throws {
        let gate = ReinsertTaskGate()
        var eventCount = 0
        let lease = try XCTUnwrap(gate.begin())
        XCTAssertTrue(gate.commitDelivery(lease))
        eventCount += 1

        // Models either a confirmed-before-cancellation result or confirmed
        // delivery whose clipboard restoration could not be verified.
        let inspection = try XCTUnwrap(
            gate.finish(lease, requiringInspection: true)
        )
        XCTAssertEqual(eventCount, 1)
        XCTAssertNil(gate.begin())

        XCTAssertTrue(gate.acknowledgeInspection(inspection))
        XCTAssertEqual(eventCount, 1)
        let nextAttempt = try XCTUnwrap(gate.begin())
        gate.finish(nextAttempt)
    }

    func testTerminalCompletionCannotResetAReentrantReplacement() async throws {
        let gate = ReinsertTaskGate()
        var pipelineIsInserting = true
        var replacement: ReinsertTaskGate.Lease?
        let stale = try XCTUnwrap(gate.begin())

        let staleTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch is CancellationError {
                let owned = gate.permitsEffects(for: stale)
                gate.finish(stale)
                if owned { pipelineIsInserting = false }

                // Mirrors the controller's external completion, which runs
                // only after the old lease and state are fully settled.
                replacement = gate.begin()
                if replacement != nil { pipelineIsInserting = true }
            } catch {
                XCTFail("unexpected stale-task failure: \(error)")
            }
        }
        gate.attach(staleTask, to: stale)

        XCTAssertTrue(gate.cancelAll())
        await staleTask.value

        let newLease = try XCTUnwrap(replacement)
        XCTAssertTrue(pipelineIsInserting)
        XCTAssertTrue(gate.permitsEffects(for: newLease))
        gate.finish(stale)
        XCTAssertTrue(gate.permitsEffects(for: newLease))
        gate.finish(newLease)
    }
}
