import XCTest
@testable import TextIntelligence

final class CodeDictationProcessorTests: XCTestCase {
    let processor = CodeDictationProcessor()

    // MARK: Case commands

    func testCamelCase() {
        XCTAssertEqual(processor.process("camel case get user name"), "getUserName")
    }

    func testPascalCase() {
        XCTAssertEqual(processor.process("pascal case user profile view"), "UserProfileView")
    }

    func testSnakeCase() {
        XCTAssertEqual(processor.process("snake case max retry count"), "max_retry_count")
    }

    func testConstantCase() {
        XCTAssertEqual(processor.process("constant case max retries"), "MAX_RETRIES")
    }

    func testKebabCase() {
        XCTAssertEqual(processor.process("kebab case primary button"), "primary-button")
    }

    func testCaseCommandEmbeddedInSentence() {
        XCTAssertEqual(
            processor.process("function camel case get user name"), "function getUserName")
    }

    // MARK: Symbols

    func testFunctionSignature() {
        XCTAssertEqual(
            processor.process("camel case get user open paren close paren open brace"),
            "getUser() {"
        )
    }

    func testArrowFunctions() {
        XCTAssertEqual(processor.process("items fat arrow value"), "items=>value")
        XCTAssertEqual(processor.process("this arrow name"), "this->name")
    }

    func testDotAccess() {
        XCTAssertEqual(processor.process("user period name"), "user.name")
    }

    func testOperators() {
        XCTAssertEqual(processor.process("x equals equals five"), "x==5")
        XCTAssertEqual(processor.process("count plus plus"), "count++")
    }

    func testQuotesAttach() {
        XCTAssertEqual(processor.process("double quote hello double quote"), "\"hello\"")
    }

    func testHashAndAt() {
        XCTAssertEqual(processor.process("hash include"), "#include")
        // Note: case is preserved as heard — the processor can't know "Published"
        // is capitalized; use camel/pascal case commands for that.
        XCTAssertEqual(processor.process("at sign published"), "@published")
        XCTAssertEqual(processor.process("at sign pascal case published"), "@Published")
    }

    func testNoSpace() {
        XCTAssertEqual(processor.process("foo no space bar"), "foobar")
    }

    func testNewLine() {
        XCTAssertEqual(processor.process("first new line second"), "first\nsecond")
    }

    func testSlashAndUnderscore() {
        XCTAssertEqual(processor.process("usr slash local slash bin"), "usr/local/bin")
        XCTAssertEqual(processor.process("user underscore id"), "user_id")
    }

    func testPlainProsePassesThrough() {
        XCTAssertEqual(
            processor.process("hello world this is normal"), "hello world this is normal")
    }
}
