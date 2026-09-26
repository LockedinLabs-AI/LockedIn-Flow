import XCTest
@testable import SpeechEngine

final class VoiceActivityFilterTests: XCTestCase {
    func testLeadingAndTrailingNonSpeechAreRemoved() async {
        let samples = Array(0..<8_000).map(Float.init)
        let preparer = VoiceAwareAudioPreparer(
            detector: TestSpeechDetector(bounds: 1_000..<7_000)
        )

        let result = await preparer.prepare(samples, enabled: true)

        guard case .speech(let prepared, let originalCount) = result else {
            return XCTFail("Expected detected speech")
        }
        XCTAssertEqual(originalCount, 8_000)
        XCTAssertEqual(prepared, Array(samples[1_000..<7_000]))
    }

    func testInternalSilenceIsPreservedByteForByte() async {
        var samples = Array(0..<8_000).map(Float.init)
        samples.replaceSubrange(3_000..<4_000, with: repeatElement(0, count: 1_000))
        let preparer = VoiceAwareAudioPreparer(
            detector: TestSpeechDetector(bounds: 1_000..<7_000)
        )

        let result = await preparer.prepare(samples, enabled: true)

        guard case .speech(let prepared, _) = result else {
            return XCTFail("Expected detected speech")
        }
        XCTAssertEqual(prepared, Array(samples[1_000..<7_000]))
        XCTAssertEqual(Array(prepared[2_000..<3_000]), [Float](repeating: 0, count: 1_000))
    }

    func testShortDetectedSpeechExpandsToMinimumTranscriptionLength() async {
        let samples = [Float](repeating: 0.25, count: 8_000)
        let preparer = VoiceAwareAudioPreparer(
            detector: TestSpeechDetector(bounds: 3_900..<4_100)
        )

        let result = await preparer.prepare(samples, enabled: true)

        guard case .speech(let prepared, _) = result else {
            return XCTFail("Expected detected speech")
        }
        XCTAssertEqual(prepared.count, VoiceAwareAudioPreparer.minimumTranscriptionSamples)
    }

    func testSubminimumNoSpeechAvoidsTranscriptionInput() async {
        let preparer = VoiceAwareAudioPreparer(
            detector: TestSpeechDetector(bounds: nil)
        )

        let result = await preparer.prepare([0, 0, 0], enabled: true)

        guard case .noSpeech = result else {
            return XCTFail("Expected no-speech result")
        }
        XCTAssertNil(result.samplesForTranscription)
    }

    func testValidLengthNoSpeechFallsBackToOriginalSamples() async {
        let samples = Array(0..<VoiceAwareAudioPreparer.minimumTranscriptionSamples)
            .map { Float($0) / 100 }
        let preparer = VoiceAwareAudioPreparer(
            detector: TestSpeechDetector(bounds: nil)
        )

        let result = await preparer.prepare(samples, enabled: true)

        guard case .fallback(let prepared, let originalCount) = result else {
            return XCTFail("Expected a valid recording to fail open")
        }
        XCTAssertEqual(prepared, samples)
        XCTAssertEqual(originalCount, samples.count)
        XCTAssertEqual(result.samplesForTranscription, samples)
    }

    func testDisabledFilteringReturnsOriginalSamplesWithoutCallingDetector() async {
        let detector = TestSpeechDetector(bounds: 1..<2)
        let samples: [Float] = [0, 1, 0]
        let preparer = VoiceAwareAudioPreparer(detector: detector)

        let result = await preparer.prepare(samples, enabled: false)

        guard case .fallback(let prepared, let originalCount) = result else {
            return XCTFail("Expected bypass fallback")
        }
        XCTAssertEqual(prepared, samples)
        XCTAssertEqual(originalCount, samples.count)
        let calls = await detector.speechBoundsCallCount
        XCTAssertEqual(calls, 0)
    }

    func testDetectorFailureReturnsOriginalSamples() async {
        let samples: [Float] = [0, 1, 2, 3]
        let detector = TestSpeechDetector(error: TestError.unavailable)
        let preparer = VoiceAwareAudioPreparer(detector: detector)

        let firstResult = await preparer.prepare(samples, enabled: true)
        let secondResult = await preparer.prepare(samples, enabled: true)

        guard case .fallback(let prepared, let originalCount) = firstResult else {
            return XCTFail("Expected fail-open fallback")
        }
        XCTAssertEqual(prepared, samples)
        XCTAssertEqual(originalCount, samples.count)
        XCTAssertEqual(secondResult.samplesForTranscription, samples)
        let calls = await detector.speechBoundsCallCount
        XCTAssertEqual(calls, 1, "A failed optional detector should not delay every dictation")
    }

    func testCancellationDoesNotDisableDetectorForTheSession() async {
        let detector = TestSpeechDetector(
            bounds: 0..<5_000,
            errors: [CancellationError(), nil]
        )
        let samples = [Float](repeating: 0.25, count: 5_000)
        let preparer = VoiceAwareAudioPreparer(detector: detector)

        let firstResult = await preparer.prepare(samples, enabled: true)
        let secondResult = await preparer.prepare(samples, enabled: true)

        guard case .fallback = firstResult else {
            return XCTFail("Cancellation should fall back for the cancelled request")
        }
        guard case .speech = secondResult else {
            return XCTFail("Cancellation should not disable future detection")
        }
        let calls = await detector.speechBoundsCallCount
        XCTAssertEqual(calls, 2)
    }

    func testExpandedBoundsClampAtBothEdges() {
        XCTAssertEqual(
            VoiceAwareAudioPreparer.expandedBounds(-10..<2, sampleCount: 10, minimumCount: 6),
            0..<6
        )
        XCTAssertEqual(
            VoiceAwareAudioPreparer.expandedBounds(9..<20, sampleCount: 10, minimumCount: 6),
            4..<10
        )
    }
}

private enum TestError: Error {
    case unavailable
}

private actor TestSpeechDetector: SpeechActivityDetecting {
    private let bounds: Range<Int>?
    private let error: Error?
    private var errors: [Error?]
    private(set) var speechBoundsCallCount = 0

    init(
        bounds: Range<Int>? = nil,
        error: Error? = nil,
        errors: [Error?] = []
    ) {
        self.bounds = bounds
        self.error = error
        self.errors = errors
    }

    func prepare() async throws {
        if let error { throw error }
    }

    func speechBounds(in samples: [Float]) async throws -> Range<Int>? {
        speechBoundsCallCount += 1
        if !errors.isEmpty, let nextError = errors.removeFirst() {
            throw nextError
        }
        if let error { throw error }
        return bounds
    }
}
