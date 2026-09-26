import XCTest
@testable import VoiceCore

final class VocabularyTests: XCTestCase {
    func testWholeWordReplacement() {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "super base", written: "Supabase")
        ])
        XCTAssertEqual(
            vocabulary.apply(to: "we store it in super base today"), "we store it in Supabase today"
        )
    }

    func testCaseInsensitiveMatchKeepsWrittenForm() {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "acme health", written: "AcmeHealth.ai")
        ])
        XCTAssertEqual(
            vocabulary.apply(to: "Acme Health is the platform"), "AcmeHealth.ai is the platform")
    }

    func testDoesNotReplaceInsideOtherWords() {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "flow", written: "Flow")
        ])
        XCTAssertEqual(
            vocabulary.apply(to: "airflow and workflow stay"), "airflow and workflow stay")
    }

    func testCaseSensitiveRuleRespected() {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "F H I R", written: "FHIR", caseSensitive: true)
        ])
        XCTAssertEqual(vocabulary.apply(to: "F H I R but not f h i r"), "FHIR but not f h i r")
    }

    func testDollarAndSpecialCharactersInReplacementAreLiteral() {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "price", written: "$5")
        ])
        XCTAssertEqual(vocabulary.apply(to: "the price is right"), "the $5 is right")
    }

    func testEngineeringTermsWithPunctuationUseTokenBoundaries() {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: ". net", written: ".NET"),
            VocabularyRule(spoken: "c plus plus", written: "C++"),
            VocabularyRule(spoken: "C++", written: "C++"),
        ])

        XCTAssertEqual(
            vocabulary.apply(to: "Use . net with c plus plus and C++."),
            "Use .NET with C++ and C++."
        )
    }

    func testReplacementDoesNotCascadeIntoAnotherRule() {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "alpha", written: "beta"),
            VocabularyRule(spoken: "beta", written: "gamma"),
        ])

        XCTAssertEqual(vocabulary.apply(to: "alpha beta"), "beta gamma")
    }

    func testLongestRuleAndProfileScopedRuleWinAtSamePosition() {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "flow", written: "Global Flow"),
            VocabularyRule(spoken: "locked in", written: "Locked"),
            VocabularyRule(spoken: "locked in flow", written: "LockedIn Flow"),
            VocabularyRule(
                spoken: "flow", written: "Engineering Flow", profileIDs: ["coding"]),
        ])

        XCTAssertEqual(
            vocabulary.apply(to: "locked in flow uses flow", profileID: "coding"),
            "LockedIn Flow uses Engineering Flow"
        )
    }

    func testNarrowerProfileScopeWinsForLegacyOverlappingRules() {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "flow", written: "Global Flow"),
            VocabularyRule(
                spoken: "flow", written: "Broad Flow", profileIDs: ["coding", "email"]),
            VocabularyRule(spoken: "flow", written: "Coding Flow", profileIDs: ["coding"]),
        ])

        XCTAssertEqual(
            vocabulary.apply(to: "flow", profileID: "coding"),
            "Coding Flow"
        )
    }

    func testMaximumVocabularyMatchesWithoutPerRuleRegexCompilation() {
        let vocabulary = Vocabulary(
            rules: (0..<VocabularyStore.maximumVocabularyRules).map {
                VocabularyRule(spoken: "enterprise term \($0)", written: "EnterpriseTerm\($0)")
            })

        XCTAssertEqual(
            vocabulary.apply(to: "use enterprise term 9999 today"),
            "use EnterpriseTerm9999 today"
        )
    }

    func testEmptyRulesReturnInput() {
        XCTAssertEqual(Vocabulary().apply(to: "unchanged"), "unchanged")
    }
}
