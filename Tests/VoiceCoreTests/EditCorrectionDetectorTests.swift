import XCTest
@testable import VoiceCore

final class EditCorrectionDetectorTests: XCTestCase {
    // MARK: - The core use-case: fixing a misrecognized name

    func testLearnsANameCorrection() {
        let correction = EditCorrectionDetector.detect(
            inserted: "Pick up Jawwad from practice at five.",
            edited: "Pick up Jawad from practice at five."
        )
        XCTAssertEqual(correction, EditLearnedCorrection(spoken: "Jawwad", written: "Jawad"))
    }

    func testLearnsWhenRecognizerHeardACommonWordInstead() {
        let correction = EditCorrectionDetector.detect(
            inserted: "I told Jihad we would meet tomorrow.",
            edited: "I told Jawad we would meet tomorrow."
        )
        XCTAssertEqual(correction, EditLearnedCorrection(spoken: "Jihad", written: "Jawad"))
    }

    func testLearnsAMultiWordProperNoun() {
        let correction = EditCorrectionDetector.detect(
            inserted: "Send it to super base support.",
            edited: "Send it to Supabase support."
        )
        XCTAssertEqual(correction, EditLearnedCorrection(spoken: "super base", written: "Supabase"))
    }

    func testLearnsDiacriticsRestoration() {
        let correction = EditCorrectionDetector.detect(
            inserted: "Lunch with Jose on Friday.",
            edited: "Lunch with José on Friday."
        )
        XCTAssertEqual(correction, EditLearnedCorrection(spoken: "Jose", written: "José"))
    }

    func testLearnsStructuredTerm() {
        let correction = EditCorrectionDetector.detect(
            inserted: "Deploy the web app config.",
            edited: "Deploy the web-app.yml config."
        )
        XCTAssertEqual(
            correction,
            EditLearnedCorrection(spoken: "web app", written: "web-app.yml")
        )
    }

    func testTrimsSentencePunctuationFromTheEdges() {
        let correction = EditCorrectionDetector.detect(
            inserted: "Say hi to Jawwad.",
            edited: "Say hi to Jawad."
        )
        XCTAssertEqual(correction, EditLearnedCorrection(spoken: "Jawwad", written: "Jawad"))
    }

    // MARK: - Refusals

    func testNoChangeLearnsNothing() {
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "Nothing changed here.",
                edited: "Nothing changed here."
            ))
    }

    func testGrammarEditsAreNotVocabulary() {
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "Put it over there desk.",
                edited: "Put it over their desk."
            ))
    }

    func testNumbersAreNeverLearned() {
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "The dose is 10 mg.",
                edited: "The dose is 20 mg."
            ))
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "Meet at 5.",
                edited: "Meet at Five."
            ))
    }

    func testPureInsertionOrDeletionIsNotACorrection() {
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "Send the report.",
                edited: "Send the quarterly report."
            ))
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "Send the quarterly report.",
                edited: "Send the report."
            ))
    }

    func testLongRewritesAreNotLearned() {
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "The meeting went well and we agreed on next steps.",
                edited: "The Sync was productive and We aligned on Following actions."
            ))
    }

    func testTwoSeparateEditsAreNotLearned() {
        // Two disjoint edits collapse into one long changed span, which the
        // phrase-length guard rejects rather than guessing which edit to keep.
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "Ask Jawwad to email Marc about the Contract today.",
                edited: "Ask Jawad to email Mark about the Contract tonight."
            ))
    }

    func testCommonSingleWordTriggerIsRefused() {
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "Bring the charger.",
                edited: "Bring The charger."
            ))
    }

    func testLowercaseReplacementIsNotVocabulary() {
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "That was a graet idea.",
                edited: "That was a great idea."
            ))
    }

    func testInsertedSpanGuardRejectsEditsOutsideAppOutput() {
        // The field contained pre-existing text; the user edited that part,
        // not what the app inserted.
        XCTAssertNil(
            EditCorrectionDetector.detect(
                inserted: "Earlier note about Samir. Dictated sentence here.",
                edited: "Earlier note about Sameer. Dictated sentence here.",
                insertedSpan: "Dictated sentence here."
            ))
    }

    func testInsertedSpanGuardAcceptsEditsInsideAppOutput() {
        let correction = EditCorrectionDetector.detect(
            inserted: "Earlier note. Call Jawwad tonight.",
            edited: "Earlier note. Call Jawad tonight.",
            insertedSpan: "Call Jawwad tonight."
        )
        XCTAssertEqual(correction, EditLearnedCorrection(spoken: "Jawwad", written: "Jawad"))
    }

    func testEmptyInputsLearnNothing() {
        XCTAssertNil(EditCorrectionDetector.detect(inserted: "", edited: "Jawad"))
        XCTAssertNil(EditCorrectionDetector.detect(inserted: "Jawad", edited: ""))
    }

    // MARK: - Round trip with Vocabulary

    func testLearnedCorrectionAppliesOnFutureDictations() {
        let correction = EditCorrectionDetector.detect(
            inserted: "Tell Jawwad the game moved.",
            edited: "Tell Jawad the game moved."
        )!
        var vocabulary = Vocabulary()
        vocabulary.rules.append(
            VocabularyRule(
                spoken: correction.spoken,
                written: correction.written
            )
        )
        XCTAssertEqual(
            vocabulary.apply(to: "Jawwad said yes.", profileID: "general"),
            "Jawad said yes."
        )
    }
}
