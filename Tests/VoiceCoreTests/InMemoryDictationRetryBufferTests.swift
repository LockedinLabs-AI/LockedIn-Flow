import XCTest
@testable import VoiceCore

final class InMemoryDictationRetryBufferTests: XCTestCase {
    func testStartsEmptyAndDoesNotInventRetryAudio() {
        let buffer = InMemoryDictationRetryBuffer()

        XCTAssertFalse(buffer.hasRecording)
        XCTAssertEqual(buffer.sampleCount, 0)
        XCTAssertNil(buffer.recordingForRetry())
    }

    func testRetainsFailedRecordingForRepeatedReadsInSameSession() {
        var buffer = InMemoryDictationRetryBuffer()
        let samples: [Float] = [0.1, -0.2, 0.3]

        XCTAssertTrue(buffer.retain(samples))

        XCTAssertTrue(buffer.hasRecording)
        XCTAssertEqual(buffer.sampleCount, samples.count)
        XCTAssertEqual(buffer.recordingForRetry(), samples)
        XCTAssertEqual(buffer.recordingForRetry(), samples)
    }

    func testLatestFailedRecordingReplacesEarlierRecording() {
        var buffer = InMemoryDictationRetryBuffer()
        buffer.retain([0.1, 0.2])

        buffer.retain([-0.4, 0.8, 0.2])

        XCTAssertEqual(buffer.recordingForRetry(), [-0.4, 0.8, 0.2])
    }

    func testEmptyFailureDoesNotReplaceUsableRecording() {
        var buffer = InMemoryDictationRetryBuffer()
        buffer.retain([0.25])

        XCTAssertFalse(buffer.retain([]))

        XCTAssertEqual(buffer.recordingForRetry(), [0.25])
    }

    func testDiscardImmediatelyRemovesRetryRecording() {
        var buffer = InMemoryDictationRetryBuffer()
        buffer.retain([0.1, 0.2])

        buffer.discard()

        XCTAssertFalse(buffer.hasRecording)
        XCTAssertEqual(buffer.sampleCount, 0)
        XCTAssertNil(buffer.recordingForRetry())
    }
}
