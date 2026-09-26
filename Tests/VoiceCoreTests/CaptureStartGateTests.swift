import XCTest
@testable import VoiceCore

final class CaptureStartGateTests: XCTestCase {
    func testHoldReleaseDuringSuspendedPermissionCheckRevokesAudioStart() throws {
        var gate = CaptureStartGate()
        let suspendedAttempt = try XCTUnwrap(
            gate.begin(requiresHeldTrigger: true)
        )

        XCTAssertTrue(gate.permitsStart(for: suspendedAttempt))

        // The task is suspended in a permission check when key-up arrives.
        XCTAssertTrue(gate.holdTriggerReleased())

        // The resumed task must fail this check immediately before audio start.
        XCTAssertFalse(gate.permitsStart(for: suspendedAttempt))
        XCTAssertFalse(gate.hasPendingAttempt)
    }

    func testHoldReleaseDuringAsyncStartCheckStillBlocksMicrophoneStart() async throws {
        var gate = CaptureStartGate()
        let homeRecoveryAttempt = try XCTUnwrap(
            gate.begin(requiresHeldTrigger: true)
        )
        let suspendedFocusRecovery = Task {
            await Task.yield()
            return true
        }

        // Permission and readiness checks are asynchronous. A key-up during a
        // wait revokes the lease checked immediately before microphone start.
        XCTAssertTrue(gate.holdTriggerReleased())

        let focusRecoveryEventuallySucceeded = await suspendedFocusRecovery.value
        XCTAssertTrue(focusRecoveryEventuallySucceeded)
        XCTAssertFalse(gate.permitsStart(for: homeRecoveryAttempt))
        XCTAssertFalse(gate.hasPendingAttempt)
    }

    func testHoldReleaseDoesNotCancelToggleOrBarAttempt() throws {
        var gate = CaptureStartGate()
        let toggleAttempt = try XCTUnwrap(
            gate.begin(requiresHeldTrigger: false)
        )

        XCTAssertFalse(gate.holdTriggerReleased())
        XCTAssertTrue(gate.permitsStart(for: toggleAttempt))
    }

    func testFinishingRevokedAttemptCannotClearNewAttempt() throws {
        var gate = CaptureStartGate()
        let revokedAttempt = try XCTUnwrap(
            gate.begin(requiresHeldTrigger: true)
        )
        gate.holdTriggerReleased()
        let replacementAttempt = try XCTUnwrap(
            gate.begin(requiresHeldTrigger: true)
        )

        gate.finish(revokedAttempt)

        XCTAssertTrue(gate.permitsStart(for: replacementAttempt))
    }
}
