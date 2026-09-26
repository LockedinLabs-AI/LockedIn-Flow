import XCTest
@testable import VoiceCore

final class SnippetLibraryTests: XCTestCase {
    let library = SnippetLibrary(snippets: [
        Snippet(trigger: "insert signature", expansion: "Best,\nSam"),
        Snippet(trigger: "my address", expansion: "123 Main St"),
    ])

    func testExactTriggerExpands() {
        XCTAssertEqual(library.expansion(for: "insert signature"), "Best,\nSam")
    }

    func testTriggerIsCaseAndPunctuationInsensitive() {
        XCTAssertEqual(library.expansion(for: "Insert Signature."), "Best,\nSam")
        XCTAssertEqual(library.expansion(for: "  my address! "), "123 Main St")
    }

    func testInlineTriggerDoesNotExpand() {
        XCTAssertNil(library.expansion(for: "please insert signature at the bottom"))
        XCTAssertNil(library.expansion(for: "insert signature now"))
    }

    func testUnknownTriggerReturnsNil() {
        XCTAssertNil(library.expansion(for: "something else entirely"))
        XCTAssertNil(library.expansion(for: ""))
    }
}
