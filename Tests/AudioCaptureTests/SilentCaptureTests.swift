import XCTest

@testable import AudioCapture

final class SilentCaptureTests: XCTestCase {
    func testEmptyCaptureIsSilent() {
        XCTAssertTrue(AudioCaptureManager.isSilentCapture([]))
    }

    func testExactZeroesAreSilent() {
        XCTAssertTrue(
            AudioCaptureManager.isSilentCapture(
                [Float](repeating: 0, count: 16_000)
            )
        )
    }

    func testNearZeroDitherIsSilent() {
        let samples = (0..<16_000).map { index in
            index.isMultiple(of: 2) ? Float(0.00001) : Float(-0.00001)
        }
        XCTAssertTrue(AudioCaptureManager.isSilentCapture(samples))
    }

    func testQuietRoomNoiseFloorIsNotSilent() {
        let samples = (0..<16_000).map { index in
            index.isMultiple(of: 2) ? Float(0.001) : Float(-0.001)
        }
        XCTAssertFalse(AudioCaptureManager.isSilentCapture(samples))
    }

    func testSpeechIsNotSilent() {
        let samples = (0..<16_000).map { index in
            sinf(Float(index) * 0.05) * 0.3
        }
        XCTAssertFalse(AudioCaptureManager.isSilentCapture(samples))
    }

    func testSingleNonZeroFrameDefeatsSilence() {
        var samples = [Float](repeating: 0, count: 16_000)
        samples[8_000] = 0.5
        XCTAssertFalse(AudioCaptureManager.isSilentCapture(samples))
    }

    func testThresholdBoundaryIsExclusive() {
        XCTAssertFalse(
            AudioCaptureManager.isSilentCapture([0.0005], threshold: 0.0005)
        )
        XCTAssertTrue(
            AudioCaptureManager.isSilentCapture([0.0004], threshold: 0.0005)
        )
    }

    func testNegativePeaksCount() {
        XCTAssertFalse(AudioCaptureManager.isSilentCapture([0, 0, -0.4, 0]))
    }
}
