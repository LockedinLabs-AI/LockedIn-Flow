import XCTest
@testable import VoiceCore

final class RecoveryStoreTests: XCTestCase {
    private func makeStore(
        retention: RetentionPolicy
    ) -> (store: RecoveryStore, defaults: UserDefaults, fileURL: URL) {
        let suite = "ai.lockedin.flow.recovery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(retention.rawValue, forKey: "historyRetention")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-\(UUID().uuidString).enc")
        return (RecoveryStore(defaults: defaults, fileURL: fileURL), defaults, fileURL)
    }

    func testDefaultRetentionIsSessionOnlyAndDoesNotPersist() {
        let suite = "ai.lockedin.flow.recovery-default-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-default-\(UUID().uuidString).enc")
        let store = RecoveryStore(defaults: defaults, fileURL: fileURL)

        store.record(
            raw: "raw",
            final: "memory only",
            targetAppName: nil,
            status: "failed"
        )
        store.waitForPendingWrites()

        XCTAssertEqual(store.all().map(\.final), ["memory only"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testOffRetentionStoresNothingAndClearsExistingRecovery() {
        let context = makeStore(retention: .sevenDays)
        context.store.record(
            raw: "raw",
            final: "final",
            targetAppName: "TextEdit",
            status: "inserted"
        )
        context.store.waitForPendingWrites()
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.fileURL.path))

        context.defaults.set(RetentionPolicy.off.rawValue, forKey: "historyRetention")
        context.store.applyRetention(.off)
        context.store.record(
            raw: "must not persist",
            final: "must not persist",
            targetAppName: nil,
            status: "failed"
        )

        XCTAssertTrue(context.store.all().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.fileURL.path))
    }

    func testSessionOnlyRetentionKeepsMemoryWithoutWritingDisk() {
        let context = makeStore(retention: .sessionOnly)
        context.store.record(
            raw: "raw",
            final: "session transcript",
            targetAppName: "Notes",
            status: "inserted"
        )
        context.store.waitForPendingWrites()

        XCTAssertEqual(context.store.all().map(\.final), ["session transcript"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.fileURL.path))
    }

    func testSwitchingToSessionOnlyClearsPersistentRecovery() {
        let context = makeStore(retention: .sevenDays)
        context.store.record(
            raw: "raw",
            final: "previous session",
            targetAppName: "Notes",
            status: "inserted"
        )
        context.store.waitForPendingWrites()
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.fileURL.path))

        context.defaults.set(RetentionPolicy.sessionOnly.rawValue, forKey: "historyRetention")
        context.store.applyRetention(.sessionOnly)
        context.store.record(
            raw: "raw",
            final: "current session",
            targetAppName: "Notes",
            status: "inserted"
        )
        context.store.waitForPendingWrites()

        XCTAssertEqual(context.store.all().map(\.final), ["current session"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.fileURL.path))
    }

    func testPersistentRetentionEncryptsAndReloadsRecovery() {
        let context = makeStore(retention: .sevenDays)
        context.store.record(
            raw: "raw transcript",
            final: "persistent transcript",
            targetAppName: "Mail",
            status: "inserted"
        )
        context.store.waitForPendingWrites()

        XCTAssertTrue(FileManager.default.fileExists(atPath: context.fileURL.path))
        let encrypted = try? Data(contentsOf: context.fileURL)
        XCTAssertNotNil(encrypted)
        XCTAssertFalse(
            String(data: encrypted ?? Data(), encoding: .utf8)?.contains("persistent transcript")
                ?? false)

        let reloaded = RecoveryStore(defaults: context.defaults, fileURL: context.fileURL)
        XCTAssertEqual(reloaded.all().map(\.final), ["persistent transcript"])
    }

    func testPreparedRecoveryIsUpdatedInPlaceAfterInsertionFailure() {
        let context = makeStore(retention: .sevenDays)
        let id = context.store.record(
            raw: "raw transcript",
            final: "completed transcript",
            targetAppName: nil,
            status: "prepared"
        )

        context.store.update(
            id: id,
            targetAppName: "Slack",
            status: "failed:The paste could not be verified."
        )
        context.store.waitForPendingWrites()

        XCTAssertEqual(context.store.all().count, 1)
        XCTAssertEqual(context.store.latest?.id, id)
        XCTAssertEqual(context.store.latest?.final, "completed transcript")
        XCTAssertEqual(context.store.latest?.targetAppName, "Slack")
        XCTAssertEqual(
            context.store.latest?.status,
            "failed:The paste could not be verified."
        )

        let reloaded = RecoveryStore(defaults: context.defaults, fileURL: context.fileURL)
        XCTAssertEqual(reloaded.latest?.id, id)
        XCTAssertEqual(reloaded.latest?.final, "completed transcript")
        XCTAssertEqual(
            reloaded.latest?.status,
            "failed:The paste could not be verified."
        )
    }

    func testDeleteMatchingRemovesEveryRecoveryCopyFromMemoryAndDisk() {
        let context = makeStore(retention: .sevenDays)
        for status in ["prepared", "failed"] {
            context.store.record(
                raw: "same raw transcript",
                final: "same final transcript",
                targetAppName: "Mail",
                status: status
            )
        }
        context.store.record(
            raw: "keep raw",
            final: "keep final",
            targetAppName: "Notes",
            status: "inserted"
        )

        context.store.deleteMatching(
            raw: "same raw transcript",
            final: "same final transcript"
        )
        context.store.waitForPendingWrites()

        XCTAssertEqual(context.store.all().map(\.final), ["keep final"])
        let reloaded = RecoveryStore(defaults: context.defaults, fileURL: context.fileURL)
        XCTAssertEqual(reloaded.all().map(\.final), ["keep final"])
    }

    func testPersistentRetentionPrunesExpiredRecoveryOnLoad() throws {
        let suite = "ai.lockedin.flow.recovery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(RetentionPolicy.oneHour.rawValue, forKey: "historyRetention")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-\(UUID().uuidString).enc")
        let entries = [
            RecoveryEntry(
                timestamp: Date().addingTimeInterval(-7_200),
                raw: "expired",
                final: "expired",
                targetAppName: nil,
                status: "inserted"
            ),
            RecoveryEntry(
                timestamp: Date(),
                raw: "current",
                final: "current",
                targetAppName: nil,
                status: "inserted"
            ),
        ]
        try SecureStore.writeEncrypted(JSONEncoder().encode(entries), to: fileURL)

        let store = RecoveryStore(defaults: defaults, fileURL: fileURL)
        store.waitForPendingWrites()

        XCTAssertEqual(store.all().map(\.final), ["current"])
        let persisted = try XCTUnwrap(SecureStore.readEncrypted(from: fileURL))
        XCTAssertEqual(
            try JSONDecoder().decode([RecoveryEntry].self, from: persisted).map(\.final),
            ["current"]
        )
    }
}
