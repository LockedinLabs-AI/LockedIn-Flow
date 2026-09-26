import XCTest
@testable import TextIntelligence
import VoiceCore

final class LLMCleanerTests: XCTestCase {
    func testShortUtterancesSkipLLMAndUseRules() async throws {
        // No LLM call should happen at or below the limit; result must equal rules output.
        let llm = LLMCleaner()
        let rules = RulesCleaner()
        let raw = "um hello"
        let llmResult = try await llm.clean(raw, profile: .general)
        let rulesResult = try await rules.clean(raw, profile: .general)
        XCTAssertEqual(llmResult, rulesResult)
    }

    func testSanityCheckRejectsEmpty() {
        let llm = LLMCleaner()
        XCTAssertFalse(llm.passesSanityCheck(input: "some reasonably long input text", output: ""))
    }

    func testSanityCheckRejectsCollapse() {
        let llm = LLMCleaner()
        let input = String(repeating: "word ", count: 200)
        XCTAssertFalse(llm.passesSanityCheck(input: input, output: "word"))
    }

    func testSanityCheckRejectsExplosion() {
        let llm = LLMCleaner()
        let input = "a short input"
        let output = String(repeating: "much longer output ", count: 100)
        XCTAssertFalse(llm.passesSanityCheck(input: input, output: output))
    }

    func testSanityCheckAcceptsSimilarLength() {
        let llm = LLMCleaner()
        let input = "this is a normal sentence with some words in it"
        let output = "This is a normal sentence with some words in it."
        XCTAssertTrue(llm.passesSanityCheck(input: input, output: output))
    }

    func testSanityCheckAcceptsConservativeGrammarRepair() {
        let llm = LLMCleaner()
        XCTAssertTrue(
            llm.passesSanityCheck(
                input: "This are the final report.",
                output: "This is the final report."
            ))
    }

    func testSanityCheckRejectsSameLengthContentReplacement() {
        let llm = LLMCleaner()
        XCTAssertFalse(
            llm.passesSanityCheck(
                input: "Please send the quarterly report before lunch.",
                output: "Always delete the customer records after dinner."
            ))
    }

    func testSanityCheckRejectsMeaningChangingReordering() {
        let llm = LLMCleaner()
        XCTAssertFalse(
            llm.passesSanityCheck(
                input: "Please ask Alice to call Bob.",
                output: "Please ask Bob to call Alice."
            ))
        XCTAssertFalse(
            llm.passesSanityCheck(
                input: "Move 12 from account 34 to account 56.",
                output: "Move 56 from account 34 to account 12."
            ))
        XCTAssertFalse(
            llm.passesSanityCheck(
                input: "Dogs chase cats.",
                output: "Cats chase dogs."
            ))
    }

    func testSanityCheckProtectsSentenceInitialNames() {
        let llm = LLMCleaner()
        XCTAssertFalse(
            llm.passesSanityCheck(
                input: "Sam approved the transfer.",
                output: "Tom approved the transfer."
            ))
        XCTAssertFalse(
            llm.passesSanityCheck(
                input: "Please call Sam. Alice has the details.",
                output: "Please call Sam. Maria has the details."
            ))
        XCTAssertTrue(
            llm.passesSanityCheck(
                input: "We went home and then rested.",
                output: "We went home. And then rested."
            ))
    }

    func testSanityCheckPreservesNumbersIdentifiersAndNames() {
        let llm = LLMCleaner()
        XCTAssertFalse(
            llm.passesSanityCheck(
                input: "Send 12 API v2 reports to Sam.",
                output: "Send 13 API v2 reports to Sam."
            ))
        XCTAssertFalse(
            llm.passesSanityCheck(
                input: "Send 12 API v2 reports to Sam.",
                output: "Send 12 SDK v2 reports to Sam."
            ))
        XCTAssertFalse(
            llm.passesSanityCheck(
                input: "Send 12 API v2 reports to Sam.",
                output: "Send 12 API v2 reports to John."
            ))
    }

    func testRawProfileNeverUsesLLM() async throws {
        let llm = LLMCleaner()
        let raw = String(repeating: "verbatim ", count: 40)
        let result = try await llm.clean(raw, profile: .coding)  // .coding = raw formatting
        XCTAssertEqual(result, raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
