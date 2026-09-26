import Foundation
import XCTest

@testable import VoiceCore

final class FlowLogTests: XCTestCase {
    func testDiagnosticsKeepNumbersAndBooleans() {
        let message: FlowLog.Message = "samples=\(16000) seconds=\(1.0) recovered=\(true)"
        XCTAssertEqual(message.rendered, "samples=16000 seconds=1.0 recovered=true")
    }

    func testErrorMetadataCannotCarryPrivateContent() {
        let error = NSError(
            domain: "synthetic.private.context",
            code: 37,
            userInfo: [
                NSLocalizedDescriptionKey: "synthetic confidential transcript",
                NSFilePathErrorKey: "synthetic-private-document.txt",
                NSUnderlyingErrorKey: NSError(domain: "synthetic.nested.context", code: 99),
            ]
        )
        let message: FlowLog.Message = "model unavailable code=\(errorCode: error)"
        XCTAssertEqual(message.rendered, "model unavailable code=37")
    }

    func testStaticEventTextIsPreserved() {
        let message: FlowLog.Message = "microphone capture recovered"
        XCTAssertEqual(message.rendered, "microphone capture recovered")
    }
}
