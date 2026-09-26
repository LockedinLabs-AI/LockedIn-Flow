import XCTest
@testable import AudioCapture

final class VoiceProcessingConfiguratorTests: XCTestCase {
    func testAutomaticModeEnablesVoiceProcessingAndAGC() {
        let input = TestInput()

        let result = VoiceProcessingConfigurator.activate(on: input, preference: .automatic)

        XCTAssertEqual(result, .enabled)
        XCTAssertEqual(input.enableRequests, [true])
        XCTAssertTrue(input.isVoiceProcessingEnabled)
        XCTAssertFalse(input.isVoiceProcessingBypassed)
        XCTAssertTrue(input.isVoiceProcessingAGCEnabled)
    }

    func testUnavailableVoiceProcessingFallsBackWithoutThrowing() {
        let input = TestInput()
        input.enableError = TestError.unsupported

        let result = VoiceProcessingConfigurator.activate(on: input, preference: .automatic)

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(input.enableRequests, [true])
        XCTAssertFalse(input.isVoiceProcessingEnabled)
    }

    func testDisabledPreferenceDoesNotTouchAudioDevice() {
        let input = TestInput()

        let result = VoiceProcessingConfigurator.activate(on: input, preference: .disabled)

        XCTAssertEqual(result, .disabledByPreference)
        XCTAssertTrue(input.enableRequests.isEmpty)
        XCTAssertFalse(input.isVoiceProcessingEnabled)
    }

    func testDeviceThatDoesNotEnterVoiceProcessingFallsBack() {
        let input = TestInput()
        input.reflectEnabledRequest = false

        let result = VoiceProcessingConfigurator.activate(on: input, preference: .automatic)

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(input.enableRequests, [true])
        XCTAssertFalse(input.isVoiceProcessingEnabled)
    }

    func testAutomaticCapturePlansAStandardMicrophoneRetry() {
        XCTAssertEqual(
            VoiceProcessingAttemptPlan.preferences(for: .automatic),
            [.automatic, .disabled]
        )
        XCTAssertEqual(
            VoiceProcessingAttemptPlan.preferences(for: .disabled),
            [.disabled]
        )
    }

    func testVoiceFocusDefaultsOffWhenPreferenceIsUnset() {
        XCTAssertFalse(
            VoiceFocusPreferencePolicy.isEnabled(storedPreference: nil)
        )
    }

    func testVoiceFocusPolicyPreservesExplicitUserChoice() {
        XCTAssertTrue(
            VoiceFocusPreferencePolicy.isEnabled(storedPreference: true)
        )
        XCTAssertFalse(
            VoiceFocusPreferencePolicy.isEnabled(storedPreference: false)
        )
    }

    func testSilentVoiceProcessingCaptureLatchesStandardFallback() {
        var recovery = VoiceProcessingRecoveryState()

        let latched = recovery.recordCapture(
            wasVoiceProcessingActive: true,
            samples: [Float](
                repeating: 0,
                count: VoiceProcessingRecoveryState.minimumSilentCaptureSamples
            )
        )

        XCTAssertTrue(latched)
        XCTAssertTrue(recovery.shouldUseStandardCapture)
        XCTAssertEqual(recovery.effectivePreference(for: .automatic), .disabled)
    }

    func testStandardCaptureSilenceDoesNotLatchFallback() {
        var recovery = VoiceProcessingRecoveryState()

        let latched = recovery.recordCapture(
            wasVoiceProcessingActive: false,
            samples: [Float](
                repeating: 0,
                count: VoiceProcessingRecoveryState.minimumSilentCaptureSamples
            )
        )

        XCTAssertFalse(latched)
        XCTAssertFalse(recovery.shouldUseStandardCapture)
    }

    func testShortSilentCaptureDoesNotLatchFallback() {
        var recovery = VoiceProcessingRecoveryState()

        let latched = recovery.recordCapture(
            wasVoiceProcessingActive: true,
            samples: [Float](
                repeating: 0,
                count: VoiceProcessingRecoveryState.minimumSilentCaptureSamples - 1
            )
        )

        XCTAssertFalse(latched)
        XCTAssertFalse(recovery.shouldUseStandardCapture)
    }

    func testRealSignalDoesNotLatchFallback() {
        var recovery = VoiceProcessingRecoveryState()
        var samples = [Float](
            repeating: 0,
            count: VoiceProcessingRecoveryState.minimumSilentCaptureSamples
        )
        samples[samples.count / 2] = 0.01

        let latched = recovery.recordCapture(
            wasVoiceProcessingActive: true,
            samples: samples
        )

        XCTAssertFalse(latched)
        XCTAssertFalse(recovery.shouldUseStandardCapture)
    }

    func testReenablingVoiceFocusClearsSilentFallbackLatch() {
        var recovery = VoiceProcessingRecoveryState()
        recovery.recordCapture(
            wasVoiceProcessingActive: true,
            samples: [Float](
                repeating: 0,
                count: VoiceProcessingRecoveryState.minimumSilentCaptureSamples
            )
        )

        recovery.preferenceChanged(to: .automatic)

        XCTAssertFalse(recovery.shouldUseStandardCapture)
        XCTAssertEqual(recovery.effectivePreference(for: .automatic), .automatic)
    }

    func testSignalProbeDoesNotRecoverWhileLowEnergyBuffersKeepArriving() {
        var probe = CaptureSignalProbe()
        probe.record(
            sampleCount: VoiceProcessingRecoveryState.minimumSilentCaptureSamples,
            peak: 0.00001,
            at: 0.75
        )

        XCTAssertFalse(probe.requestRecovery(recordingAge: 1, at: 1))
        probe.record(sampleCount: 4_800, peak: 0, at: 1.75)
        XCTAssertFalse(probe.requestRecovery(recordingAge: 2, at: 2))
        XCTAssertFalse(probe.recoveryRequested)
    }

    func testSignalProbeDoesNotUseAccumulatedEnergyAsLiveRecoveryEvidence() {
        var probe = CaptureSignalProbe()
        probe.record(
            sampleCount: VoiceProcessingRecoveryState.minimumSilentCaptureSamples,
            peak: 0.5,
            at: 1
        )

        XCTAssertFalse(probe.requestRecovery(recordingAge: 1.5, at: 1.5))
    }

    func testSignalProbeRecoversAfterDeliveredBuffersBecomeStarved() {
        var probe = CaptureSignalProbe()
        probe.record(sampleCount: 2_400, peak: 0, at: 1)

        XCTAssertFalse(probe.requestRecovery(recordingAge: 1.9, at: 1.9))
        XCTAssertTrue(probe.requestRecovery(recordingAge: 2, at: 2))
        XCTAssertFalse(probe.requestRecovery(recordingAge: 3, at: 3))
    }

    func testSignalProbeRecoversAStarvedTapAfterGracePeriod() {
        var probe = CaptureSignalProbe()

        XCTAssertFalse(
            probe.requestRecovery(
                recordingAge: CaptureSignalProbe.starvedTapGracePeriod - 0.01,
                at: CaptureSignalProbe.starvedTapGracePeriod - 0.01
            )
        )
        XCTAssertTrue(
            probe.requestRecovery(
                recordingAge: CaptureSignalProbe.starvedTapGracePeriod,
                at: CaptureSignalProbe.starvedTapGracePeriod
            )
        )
    }

    func testSignalProbeResetAllowsOneFreshAttempt() {
        var probe = CaptureSignalProbe()
        probe.record(
            sampleCount: 4_800,
            peak: 0,
            at: 0
        )
        XCTAssertTrue(
            probe.requestRecovery(
                recordingAge: CaptureSignalProbe.minimumRecoveryAge,
                at: CaptureSignalProbe.starvedTapGracePeriod
            )
        )

        probe.reset()

        XCTAssertEqual(probe.sampleCount, 0)
        XCTAssertEqual(probe.peak, 0)
        XCTAssertNil(probe.lastBufferAt)
        XCTAssertFalse(probe.recoveryRequested)
        XCTAssertTrue(
            probe.requestRecovery(
                recordingAge: CaptureSignalProbe.minimumRecoveryAge,
                at: CaptureSignalProbe.minimumRecoveryAge
            )
        )
    }

    func testReplacementGraphGetsAFreshStarvationGracePeriod() {
        var clock = CaptureAttemptClock()
        clock.start(at: 10)
        XCTAssertEqual(clock.age(at: 12), 2)

        clock.start(at: 20)

        XCTAssertEqual(clock.age(at: 20.25), 0.25)
    }

    func testAttemptClockClearsAndClampsClockSkew() {
        var clock = CaptureAttemptClock()
        clock.start(at: 10)
        XCTAssertEqual(clock.age(at: 9), 0)

        clock.stop()

        XCTAssertEqual(clock.age(at: 100), 0)
    }

    func testConfigurationRestartFailureReachesManagerHealthCheck() {
        let manager = AudioCaptureManager(voiceProcessing: .disabled)
        let expected = AudioCaptureError.engineFailed("input device vanished")

        manager.latchCaptureFailure(expected)

        XCTAssertThrowsError(try manager.recoverSilentVoiceProcessingIfNeeded()) { error in
            XCTAssertEqual(error as? AudioCaptureError, expected)
        }
        _ = manager.stopWithResult()
        XCTAssertNoThrow(try manager.recoverSilentVoiceProcessingIfNeeded())
    }

    func testManagerStopDrainsPreservedSamplesAndErrorWhenAlreadyStopped() {
        var store = CaptureSampleStore()
        let generation = store.begin(preservingExisting: false)
        XCTAssertTrue(store.append([0.1, 0.2], generation: generation))
        let manager = AudioCaptureManager(
            voiceProcessing: .disabled,
            sampleStore: store,
            isRecording: false
        )
        let expected = AudioCaptureError.engineFailed("replacement failed")
        manager.latchCaptureFailure(expected)

        let firstStop = manager.stopWithResult()
        let secondStop = manager.stopWithResult()

        XCTAssertEqual(firstStop.samples, [0.1, 0.2])
        XCTAssertEqual(firstStop.terminalError, expected)
        XCTAssertEqual(secondStop.samples, [])
        XCTAssertNil(secondStop.terminalError)
    }

    func testManagerCancelDiscardsPreservedSamplesAndError() {
        var store = CaptureSampleStore()
        let generation = store.begin(preservingExisting: false)
        XCTAssertTrue(store.append([0.1], generation: generation))
        let manager = AudioCaptureManager(
            voiceProcessing: .disabled,
            sampleStore: store,
            isRecording: false
        )
        manager.latchCaptureFailure(AudioCaptureError.engineFailed("replacement failed"))

        manager.cancel()
        let stopped = manager.stopWithResult()

        XCTAssertEqual(stopped.samples, [])
        XCTAssertNil(stopped.terminalError)
    }

    func testReplacementGraphPreservesSamplesAndRejectsOldCallbacks() {
        var store = CaptureSampleStore()
        let oldGeneration = store.begin(preservingExisting: false)
        XCTAssertTrue(store.append([1, 2], generation: oldGeneration))

        let replacementGeneration = store.begin(preservingExisting: true)

        XCTAssertFalse(store.append([99], generation: oldGeneration))
        XCTAssertTrue(store.append([3, 4], generation: replacementGeneration))
        XCTAssertEqual(store.drain(), [1, 2, 3, 4])
        XCTAssertEqual(store.drain(), [])
    }

    func testCallbackFinishingBeforeReplacementBeginsPreservesTailSamples() {
        var store = CaptureSampleStore()
        let oldGeneration = store.begin(preservingExisting: false)
        XCTAssertTrue(store.append([1], generation: oldGeneration))

        // Teardown has started, but the replacement generation has not. A
        // render callback already converting belongs to the captured tail.
        XCTAssertTrue(store.append([2], generation: oldGeneration))
        let replacementGeneration = store.begin(preservingExisting: true)
        XCTAssertTrue(store.append([3], generation: replacementGeneration))

        XCTAssertEqual(store.drain(), [1, 2, 3])
    }

    func testLateCallbackCannotRepopulateDrainedSamples() {
        var store = CaptureSampleStore()
        let generation = store.begin(preservingExisting: false)
        XCTAssertTrue(store.append([1], generation: generation))
        XCTAssertEqual(store.drain(), [1])

        XCTAssertFalse(store.append([2], generation: generation))
        XCTAssertEqual(store.samples, [])
    }

    func testDiscardInvalidatesCallbacksAndClearsPreservedSamples() {
        var store = CaptureSampleStore()
        let generation = store.begin(preservingExisting: false)
        XCTAssertTrue(store.append([1, 2], generation: generation))

        store.discard()

        XCTAssertFalse(store.append([3], generation: generation))
        XCTAssertEqual(store.drain(), [])
    }

    func testRecoveryStateCanLatchStandardCaptureImmediately() {
        var recovery = VoiceProcessingRecoveryState()

        recovery.requireStandardCapture()

        XCTAssertTrue(recovery.shouldUseStandardCapture)
        XCTAssertEqual(recovery.effectivePreference(for: .automatic), .disabled)
    }
}

private enum TestError: Error {
    case unsupported
}

private final class TestInput: VoiceProcessingConfiguring {
    var isVoiceProcessingEnabled = false
    var isVoiceProcessingBypassed = true
    var isVoiceProcessingAGCEnabled = false
    var reflectEnabledRequest = true
    var enableError: Error?
    var enableRequests: [Bool] = []

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        enableRequests.append(enabled)
        if let enableError {
            throw enableError
        }
        if reflectEnabledRequest {
            isVoiceProcessingEnabled = enabled
        }
    }
}
