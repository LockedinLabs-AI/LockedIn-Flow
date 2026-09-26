import XCTest
@testable import TextIntelligence
@testable import VoiceCore

final class MeetingSummarizerTests: XCTestCase {
    func testParsesWellFormedOutput() {
        let output = """
            TITLE: Sprint planning recap
            SUMMARY: The team reviewed the roadmap and assigned owners for the release.
            POINTS:
            - Release moved to Friday
            - The synthetic export job is the launch blocker
            ACTIONS:
            - Example Owner A to prepare the test fixture
            - Example Owner B to verify the build
            """
        let note = MeetingSummarizer.parse(output)
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.title, "Sprint planning recap")
        XCTAssertEqual(note?.keyPoints.count, 2)
        XCTAssertEqual(note?.actionItems.count, 2)
    }

    func testNoneActionItemsAreDropped() {
        let output = """
            TITLE: Catch-up
            SUMMARY: General sync with no assigned tasks.
            POINTS:
            - Chatted about the weather
            ACTIONS:
            - NONE
            """
        let note = MeetingSummarizer.parse(output)
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.actionItems.count, 0)
    }

    func testMalformedOutputReturnsNil() {
        XCTAssertNil(MeetingSummarizer.parse("Here is your summary, enjoy!"))
        XCTAssertNil(MeetingSummarizer.parse("TITLE: only a title"))
        XCTAssertNil(MeetingSummarizer.parse(""))
    }
}

final class MeetingStoreTests: XCTestCase {
    private func meeting(title: String) -> Meeting {
        Meeting(
            durationSeconds: 120,
            rawTranscript: "raw words here",
            note: MeetingNote(
                title: title, summary: "A summary.", keyPoints: ["one"], actionItems: ["do it"])
        )
    }

    func testMarkdownFormat() {
        let markdown = meeting(title: "Test Meeting").markdown
        XCTAssertTrue(markdown.contains("# Test Meeting"))
        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("- one"))
        XCTAssertTrue(markdown.contains("- [ ] do it"))
    }

    func testRecordAndDelete() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meetings-\(UUID().uuidString).enc")
        let store = MeetingStore(fileURL: fileURL)
        let before = store.all().count
        let m = meeting(title: "Store Test \(UUID().uuidString.prefix(6))")
        try await store.record(m)
        XCTAssertEqual(store.all().count, before + 1)
        store.delete(id: m.id)
        XCTAssertEqual(store.all().count, before)
    }

    func testUpdateReplacesPreservedTranscriptWithoutDuplicating() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meetings-\(UUID().uuidString).enc")
        let store = MeetingStore(fileURL: fileURL)
        let preserved = meeting(title: "Transcript preserved")
        try await store.record(preserved)

        var completed = preserved
        completed.note = MeetingNote(
            title: "Completed notes",
            summary: "The final summary.",
            keyPoints: [],
            actionItems: []
        )
        let didUpdate = try await store.update(completed)
        XCTAssertTrue(didUpdate)

        let matches = store.all().filter { $0.id == preserved.id }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.note.title, "Completed notes")

        let reloaded = MeetingStore(fileURL: fileURL)
        let persistedMatches = reloaded.all().filter { $0.id == preserved.id }
        XCTAssertEqual(persistedMatches.count, 1)
        XCTAssertEqual(persistedMatches.first?.note.title, "Completed notes")
    }

    func testUpdateDoesNotResurrectADeletedMeeting() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meetings-\(UUID().uuidString).enc")
        let store = MeetingStore(fileURL: fileURL)
        let preserved = meeting(title: "Transcript preserved")
        try await store.record(preserved)
        store.delete(id: preserved.id)
        store.waitForPendingWrites()

        var completed = preserved
        completed.note.title = "Must stay deleted"
        let didUpdate = try await store.update(completed)
        XCTAssertFalse(didUpdate)
        XCTAssertTrue(store.all().isEmpty)
    }
}
