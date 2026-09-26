import XCTest
@testable import TextIntelligence

final class SpokenCommandParserTests: XCTestCase {
    let parser = SpokenCommandParser()

    func testCancelVariants() {
        XCTAssertEqual(parser.command(for: "cancel"), .cancel)
        XCTAssertEqual(parser.command(for: "Cancel that."), .cancel)
        XCTAssertEqual(parser.command(for: "scratch that"), .cancel)
    }

    func testUndoVariants() {
        XCTAssertEqual(parser.command(for: "undo that"), .undoLast)
        XCTAssertEqual(parser.command(for: "Undo."), .undoLast)
    }

    func testDeleteVariants() {
        XCTAssertEqual(parser.command(for: "delete last sentence"), .deleteLastSentence)
        XCTAssertEqual(parser.command(for: "delete that"), .deleteLastSentence)
    }

    func testCommandInsideLongerUtteranceIsNotTriggered() {
        XCTAssertNil(parser.command(for: "please cancel my subscription"))
        XCTAssertNil(parser.command(for: "I said undo that change yesterday"))
    }

    func testOrdinaryTextIsNotACommand() {
        XCTAssertNil(parser.command(for: "the synthetic device reports mild vibration"))
    }
}
