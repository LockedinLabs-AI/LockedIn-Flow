import XCTest
@testable import TextIntelligence
import VoiceCore

final class TranscriptCleanerTests: XCTestCase {
    let cleaner = TranscriptCleaner()

    func testBasicCapitalizationAndTerminalPeriod() {
        XCTAssertEqual(cleaner.clean("hello world"), "Hello world.")
    }

    func testSpokenCommaAndPeriod() {
        XCTAssertEqual(cleaner.clean("yes comma we can period"), "Yes, we can.")
    }

    func testNewParagraph() {
        XCTAssertEqual(
            cleaner.clean("first part new paragraph second part"), "First part\n\nSecond part.")
    }

    func testQuestionMark() {
        XCTAssertEqual(cleaner.clean("are you sure question mark"), "Are you sure?")
    }

    func testFillerRemoval() {
        XCTAssertEqual(cleaner.clean("um I think uh we should go"), "I think we should go.")
    }

    func testFillerRemovalCoversAhErmAndLengthenedVariants() {
        XCTAssertEqual(
            cleaner.clean("Ummm ahh ERMM errm uhhh I think"),
            "I think."
        )
    }

    func testRepeatedFillersAndHesitationsAreRemoved() {
        XCTAssertEqual(
            cleaner.clean("um umm uh ah erm I I think we, we should go"),
            "I think we should go."
        )
    }

    func testFillerPausePunctuationDoesNotRemainStranded() {
        XCTAssertEqual(cleaner.clean("Um, I think"), "I think.")
        XCTAssertEqual(cleaner.clean("I, um, think this works"), "I think this works.")
        XCTAssertEqual(cleaner.clean("I — um — think this works"), "I think this works.")
        XCTAssertEqual(cleaner.clean("Um... I think this works"), "I think this works.")
    }

    func testFillerRemovalPreservesClauseSeparators() {
        XCTAssertEqual(
            cleaner.clean("I tried semicolon um it failed"),
            "I tried; it failed."
        )
        XCTAssertEqual(
            cleaner.clean("One warning colon ah check the cable"),
            "One warning: check the cable."
        )
        XCTAssertEqual(
            cleaner.clean("I tried em dash um it failed"),
            "I tried— it failed."
        )
    }

    func testMeaningfulHyphenatedInterjectionIsPreserved() {
        XCTAssertEqual(cleaner.clean("uh-oh this is bad"), "Uh-oh this is bad.")
    }

    func testContentWordRepetitionIsPreserved() {
        XCTAssertEqual(cleaner.clean("this is very very important"), "This is very very important.")
        XCTAssertEqual(cleaner.clean("this is so so good"), "This is so so good.")
        XCTAssertEqual(
            cleaner.clean("very important, very important"),
            "Very important, very important."
        )
    }

    func testRepeatedProperNameIsPreserved() {
        XCTAssertEqual(
            cleaner.clean("New York, New York is a song"),
            "New York, New York is a song."
        )
    }

    func testImmediateRepeatedMultiWordPhrasesAreCollapsed() {
        XCTAssertEqual(
            cleaner.clean("we should we should ship today"),
            "We should ship today."
        )
        XCTAssertEqual(
            cleaner.clean("please send the report, please send the report tomorrow"),
            "Please send the report tomorrow."
        )
        XCTAssertEqual(
            cleaner.clean("I think we can I think we can make this work"),
            "I think we can make this work."
        )
    }

    func testRepeatedPhraseCleanupHandlesMoreThanTwoCopies() {
        XCTAssertEqual(
            cleaner.clean("we need to we need to we need to leave"),
            "We need to leave."
        )
    }

    func testSingleWordEmphasisIsNeverReinterpretedAsAPhrase() {
        XCTAssertEqual(cleaner.clean("go go go go now"), "Go go go go now.")
        XCTAssertEqual(cleaner.clean("really really listen"), "Really really listen.")
    }

    func testRepeatedPhrasesAcrossStrongPunctuationArePreserved() {
        XCTAssertEqual(
            cleaner.clean("we should go. we should go"),
            "We should go. We should go."
        )
        XCTAssertEqual(
            cleaner.clean("we should go question mark we should go"),
            "We should go? We should go."
        )
        XCTAssertEqual(
            cleaner.clean("we should go semicolon we should go"),
            "We should go; we should go."
        )
    }

    func testRepeatedPhraseCleanupPreservesAllCapsTechnicalSpans() {
        XCTAssertEqual(
            cleaner.clean("API client API client is ready"),
            "API client API client is ready."
        )
        XCTAssertEqual(
            cleaner.clean("use HTTP API use HTTP API in production"),
            "Use HTTP API use HTTP API in production."
        )
    }

    func testSafeExplicitFullClauseRestartUsesReplacement() {
        XCTAssertEqual(
            cleaner.clean("send it Thursday scratch that send it Friday"),
            "Send it Friday."
        )
        XCTAssertEqual(
            cleaner.clean(
                "please note, email the report today scratch that email the report tomorrow"),
            "Please note, email the report tomorrow."
        )
    }

    func testAmbiguousShortCorrectionsRemainVerbatim() {
        XCTAssertEqual(
            cleaner.clean("call Alice scratch that Bob"),
            "Call Alice scratch that Bob."
        )
        XCTAssertEqual(
            cleaner.clean("send Thursday scratch that Friday"),
            "Send Thursday scratch that Friday."
        )
        XCTAssertEqual(
            cleaner.clean("I think scratch that I know"),
            "I think scratch that I know."
        )
    }

    func testExplicitRestartDoesNotCrossSentenceBoundaries() {
        XCTAssertEqual(
            cleaner.clean("send it Thursday. scratch that. send it Friday"),
            "Send it Thursday. Scratch that. Send it Friday."
        )
    }

    func testAllCapsIdentifiersAndUnitsArePreserved() {
        XCTAssertEqual(cleaner.clean("send this by IM"), "Send this by IM.")
        XCTAssertEqual(cleaner.clean("the battery is 20 AH"), "The battery is 20 AH.")
        XCTAssertEqual(cleaner.clean("IT IT systems"), "IT IT systems.")
    }

    func testParentheses() {
        XCTAssertEqual(
            cleaner.clean("call me open parenthesis soon close parenthesis please"),
            "Call me (soon) please.")
    }

    func testLiteralModeDisablesPunctuation() {
        let literal = TranscriptCleaner(interpretSpokenPunctuation: false, removeFillers: false)
        XCTAssertEqual(literal.clean("say comma out loud"), "Say comma out loud.")
    }

    func testLiteralModePreservesFillersAndUncorrectedWords() {
        let literal = TranscriptCleaner(interpretSpokenPunctuation: false, removeFillers: false)
        XCTAssertEqual(
            literal.clean("um i definately said comma uh"),
            "Um i definately said comma uh."
        )
    }

    func testSafeWhitespaceAndPunctuationFormatting() {
        XCTAssertEqual(
            cleaner.clean("  hello ,world!how are you ?  "),
            "Hello, world! How are you?"
        )
        XCTAssertEqual(cleaner.clean("use [ brackets ] please"), "Use [brackets] please.")
    }

    func testConservativeGrammarAndSpellingCorrections() {
        XCTAssertEqual(
            cleaner.clean("i definately dont recieve teh seperate report becuase im busy"),
            "I definitely don't receive the separate report because I'm busy."
        )
        XCTAssertEqual(
            cleaner.clean("ive seen alot of wierd issues"), "I've seen a lot of weird issues.")
    }

    func testEmptyInput() {
        XCTAssertEqual(cleaner.clean("   "), "")
    }

    func testExistingTerminalPunctuationPreserved() {
        XCTAssertEqual(cleaner.clean("watch out!"), "Watch out!")
    }

    func testEllipsisIsTerminalPunctuation() {
        XCTAssertEqual(cleaner.clean("wait ellipsis"), "Wait…")
    }

    func testTerminalPunctuationMovesInsideClosingDoubleQuote() {
        XCTAssertEqual(cleaner.clean(#""hello world""#), #""Hello world.""#)
        XCTAssertEqual(cleaner.clean(#"she said "hello world""#), #"She said "hello world.""#)
    }

    func testRawAndCodeProfilesBypassNaturalLanguageCorrections() async throws {
        let rules = RulesCleaner()
        let rawProfile = AppProfile(
            id: "raw-test",
            name: "Raw",
            bundleIdentifiers: [],
            formatting: .raw
        )

        let raw = try await rules.clean("  um i definately said comma  ", profile: rawProfile)
        let code = try await rules.clean(
            "camel case user name open paren close paren",
            profile: .coding
        )
        XCTAssertEqual(raw, "um i definately said comma")
        XCTAssertEqual(code, "userName()")
    }

    func testRawAndCodeProfilesBypassRepeatedPhraseCleanup() async throws {
        let rules = RulesCleaner()
        let rawProfile = AppProfile(
            id: "raw-repeat-test",
            name: "Raw repeats",
            bundleIdentifiers: [],
            formatting: .raw
        )

        let raw = try await rules.clean(
            "  we should we should ship  ",
            profile: rawProfile
        )
        let code = try await rules.clean(
            "foo bar foo bar",
            profile: .coding
        )

        XCTAssertEqual(raw, "we should we should ship")
        XCTAssertEqual(code, "foo bar foo bar")
    }
}
