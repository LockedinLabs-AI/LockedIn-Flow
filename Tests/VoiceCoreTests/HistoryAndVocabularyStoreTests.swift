import XCTest
@testable import VoiceCore

final class HistoryStoreTests: XCTestCase {
    private func makeStore(
        retention: RetentionPolicy = .sessionOnly
    ) -> (store: HistoryStore, defaults: UserDefaults, fileURL: URL) {
        let suite = "ai.lockedin.flow.history-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(retention.rawValue, forKey: "historyRetention")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).enc")
        return (HistoryStore(defaults: defaults, fileURL: fileURL), defaults, fileURL)
    }

    private func entry(final: String, age: TimeInterval = 0) -> HistoryEntry {
        HistoryEntry(
            createdAt: Date().addingTimeInterval(-age),
            raw: final,
            final: final,
            duration: 1,
            profileID: "general",
            targetAppName: "TextEdit",
            modelID: "test"
        )
    }

    func testRetentionCutoffs() {
        let now = Date()
        XCTAssertNil(RetentionPolicy.off.cutoff(now: now))
        XCTAssertNil(RetentionPolicy.forever.cutoff(now: now))
        XCTAssertEqual(
            RetentionPolicy.oneHour.cutoff(now: now)!.timeIntervalSince(now), -3600, accuracy: 1)
        XCTAssertEqual(
            RetentionPolicy.sevenDays.cutoff(now: now)!.timeIntervalSince(now), -604_800,
            accuracy: 1)
    }

    func testPersistenceFlag() {
        XCTAssertFalse(RetentionPolicy.off.persistsAcrossLaunches)
        XCTAssertFalse(RetentionPolicy.sessionOnly.persistsAcrossLaunches)
        XCTAssertTrue(RetentionPolicy.oneDay.persistsAcrossLaunches)
    }

    func testDefaultRetentionIsSessionOnlyAndDoesNotPersist() {
        let suite = "ai.lockedin.flow.history-default-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-default-\(UUID().uuidString).enc")
        let store = HistoryStore(defaults: defaults, fileURL: fileURL)

        XCTAssertEqual(store.retention, .sessionOnly)
        store.record(entry(final: "memory only"))
        store.waitForPendingWrites()
        XCTAssertEqual(store.all().map(\.final), ["memory only"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testSearchMatchesFinalAndRaw() {
        let store = makeStore().store
        store.record(entry(final: "Synthetic device report shows a short battery life"))
        store.record(entry(final: "Meeting agenda for Tuesday"))
        XCTAssertEqual(store.search("battery").count, 1)
        XCTAssertEqual(store.search("agenda").count, 1)
        XCTAssertEqual(store.search("nonexistent").count, 0)
        store.deleteAll()
    }

    func testOffRetentionRecordsNothing() {
        let store = makeStore().store
        store.retention = .off
        store.record(entry(final: "should not be retained"))
        XCTAssertEqual(store.search("retained").count, 0)
    }

    func testSessionOnlyRemovesPreviouslyPersistedHistory() {
        let context = makeStore(retention: .sevenDays)
        context.store.record(entry(final: "persisted transcript"))
        context.store.waitForPendingWrites()
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.fileURL.path))

        context.store.retention = .sessionOnly
        context.store.record(entry(final: "current session only"))
        context.store.waitForPendingWrites()

        XCTAssertEqual(context.store.all().map(\.final), ["current session only"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.fileURL.path))
    }

    func testDeleteAllWinsAgainstPendingPersistence() {
        let context = makeStore(retention: .sevenDays)
        context.store.record(entry(final: "delete me"))
        context.store.deleteAll()
        context.store.waitForPendingWrites()

        XCTAssertTrue(context.store.all().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.fileURL.path))
    }
}

final class VocabularyStoreTests: XCTestCase {
    func testCSVImport() {
        let csv = """
            # comment line
            super base,Supabase
            F H I R,FHIR,true
            bad line without comma
            """
        let vocabulary = VocabularyStore.importCSV(csv, into: Vocabulary())
        XCTAssertEqual(vocabulary.rules.count, 2)
        XCTAssertEqual(vocabulary.rules[0].written, "Supabase")
        XCTAssertFalse(vocabulary.rules[0].caseSensitive)
        XCTAssertEqual(vocabulary.rules[1].written, "FHIR")
        XCTAssertTrue(vocabulary.rules[1].caseSensitive)
    }

    func testCSVImportSkipsDuplicates() {
        let existing = Vocabulary(rules: [VocabularyRule(spoken: "super base", written: "Supabase")]
        )
        let vocabulary = VocabularyStore.importCSV("super base,Supabase", into: existing)
        XCTAssertEqual(vocabulary.rules.count, 1)
    }

    func testCSVExportRoundTrip() {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "acme, health", written: "AcmeHealth, Inc."),
            VocabularyRule(
                spoken: "H P S",
                written: "HPS",
                caseSensitive: true,
                profileIDs: ["coding", "email"]
            ),
            VocabularyRule(spoken: "spoken", written: "written"),
        ])
        let exported = VocabularyStore.exportCSV(vocabulary)
        let reimported = VocabularyStore.importCSV(exported, into: Vocabulary())
        XCTAssertEqual(reimported.rules.count, 3)
        XCTAssertEqual(reimported.rules[0].spoken, "acme, health")
        XCTAssertEqual(reimported.rules[0].written, "AcmeHealth, Inc.")
        XCTAssertTrue(reimported.rules[1].caseSensitive)
        XCTAssertEqual(reimported.rules[1].profileIDs, ["coding", "email"])
        XCTAssertEqual(reimported.rules[2].spoken, "spoken")
        XCTAssertEqual(reimported.rules[2].written, "written")
    }

    func testCSVExportOmitsFirstPartyRules() throws {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "user term", written: "User Term"),
            VocabularyRule(
                spoken: "starter term",
                written: "Starter Term",
                sourceID: "starter-pack"
            ),
        ])

        let report = try VocabularyStore.importCSVReport(
            VocabularyStore.exportCSV(vocabulary),
            into: Vocabulary()
        )

        XCTAssertEqual(report.importedCount, 1)
        XCTAssertEqual(report.vocabulary.rules.map(\.spoken), ["user term"])
    }

    func testCSVImportSupportsHeaderQuotesCRLFAndScopedDuplicates() throws {
        let csv = """
            spoken,written,caseSensitive,profiles\r
            "jay, wad",Jawad,false,email|coding\r
            flow,Flow,false,coding\r
            flow,Flow,false,email\r
            """
        let report = try VocabularyStore.importCSVReport(csv, into: Vocabulary())
        XCTAssertEqual(report.importedCount, 3)
        XCTAssertEqual(report.skippedCount, 0)
        XCTAssertEqual(report.vocabulary.rules[0].spoken, "jay, wad")
        XCTAssertEqual(report.vocabulary.rules[0].profileIDs, ["coding", "email"])
    }

    func testCSVImportRejectsUnknownProfilesControlsAndConflicts() throws {
        let existing = Vocabulary(rules: [
            VocabularyRule(spoken: "flow", written: "Flow", profileIDs: ["coding"])
        ])
        let csv = """
            flow,Other,false,coding
            name,Name,false,unknown
            unsafe,\u{202E}value,false,general
            """
        let report = try VocabularyStore.importCSVReport(csv, into: existing)
        XCTAssertEqual(report.importedCount, 0)
        XCTAssertEqual(report.skippedCount, 3)
        XCTAssertEqual(report.vocabulary, existing)
    }

    func testCSVImportAcceptsOverlappingScopesAndRejectsOnlyExactScope() throws {
        let existing = Vocabulary(rules: [
            VocabularyRule(spoken: "flow", written: "Coding Flow", profileIDs: ["coding"])
        ])
        let csv = """
            flow,Overlapping Flow,false,coding|email
            flow,Chat Flow,false,chat
            flow,Duplicate Coding Flow,false,coding
            """

        let report = try VocabularyStore.importCSVReport(csv, into: existing)

        XCTAssertEqual(report.importedCount, 2)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertEqual(report.vocabulary.rules[1].written, "Overlapping Flow")
        XCTAssertEqual(report.vocabulary.rules.last?.written, "Chat Flow")
    }

    func testCSVExportRoundTripsGlobalBroadAndNarrowOverrides() throws {
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "flow", written: "Global Flow"),
            VocabularyRule(
                spoken: "flow",
                written: "Broad Flow",
                profileIDs: ["coding", "email"]
            ),
            VocabularyRule(spoken: "flow", written: "Coding Flow", profileIDs: ["coding"]),
        ])

        let report = try VocabularyStore.importCSVReport(
            VocabularyStore.exportCSV(vocabulary),
            into: Vocabulary()
        )

        XCTAssertEqual(report.importedCount, 3)
        XCTAssertEqual(report.skippedCount, 0)
        XCTAssertEqual(report.vocabulary.apply(to: "flow", profileID: "general"), "Global Flow")
        XCTAssertEqual(report.vocabulary.apply(to: "flow", profileID: "email"), "Broad Flow")
        XCTAssertEqual(report.vocabulary.apply(to: "flow", profileID: "coding"), "Coding Flow")
    }

    func testCSVImportEnforcesRowLimitWhileParsing() {
        let tooManyRows = String(
            repeating: "invalid,row\n",
            count: VocabularyStore.maximumImportRows + 1
        )

        XCTAssertThrowsError(
            try VocabularyStore.importCSVReport(tooManyRows, into: Vocabulary())
        ) { error in
            XCTAssertEqual(error as? VocabularyImportError, .tooManyRows)
        }
    }

    func testCSVImportBoundsNonRuleRecordsDuringParsing() {
        let tooManyRecords = String(
            repeating: "\n",
            count: VocabularyStore.maximumImportRows + 101
        )

        XCTAssertThrowsError(
            try VocabularyStore.importCSVReport(tooManyRecords, into: Vocabulary())
        ) { error in
            XCTAssertEqual(error as? VocabularyImportError, .tooManyRecords)
        }
    }

    func testCSVImportHandlesMaximumUniqueRowsWithoutQuadraticConflictScan() throws {
        let csv = (0..<VocabularyStore.maximumImportRows)
            .map { "term \($0),Written \($0)" }
            .joined(separator: "\n")

        let report = try VocabularyStore.importCSVReport(csv, into: Vocabulary())

        XCTAssertEqual(report.importedCount, VocabularyStore.maximumImportRows)
        XCTAssertEqual(report.skippedCount, 0)
    }

    func testMaximumVocabularyExportRoundTripsWithMetadataRows() throws {
        let rules = (0..<VocabularyStore.maximumVocabularyRules).map {
            VocabularyRule(spoken: "term \($0)", written: "Written \($0)")
        }
        let exported = VocabularyStore.exportCSV(Vocabulary(rules: rules))

        let report = try VocabularyStore.importCSVReport(exported, into: Vocabulary())

        XCTAssertEqual(report.importedCount, VocabularyStore.maximumVocabularyRules)
        XCTAssertEqual(report.skippedCount, 0)
    }

    func testCSVImportEnforcesTotalVocabularyLimitAcrossImports() {
        let existing = Vocabulary(
            rules: (0..<VocabularyStore.maximumVocabularyRules).map {
                VocabularyRule(spoken: "existing \($0)", written: "Existing \($0)")
            })

        XCTAssertThrowsError(
            try VocabularyStore.importCSVReport("new term,New Term", into: existing)
        ) { error in
            XCTAssertEqual(error as? VocabularyImportError, .tooManyRules)
        }
    }

    func testPersistenceRejectsVocabularyAboveTotalLimitBeforeWriting() {
        let oversized = Vocabulary(
            rules: (0...VocabularyStore.maximumVocabularyRules).map {
                VocabularyRule(spoken: "term \($0)", written: "Written \($0)")
            })

        XCTAssertThrowsError(try VocabularyStore.saveOrThrow(oversized)) { error in
            XCTAssertEqual(error as? VocabularyImportError, .tooManyRules)
        }
    }

    func testPersistenceRejectsDuplicateIDsUnsafeTermsProfilesAndExactScopes() {
        let sharedID = UUID()
        let invalidCases: [(Vocabulary, VocabularyImportError)] = [
            (
                Vocabulary(rules: [
                    VocabularyRule(id: sharedID, spoken: "one", written: "One"),
                    VocabularyRule(id: sharedID, spoken: "two", written: "Two"),
                ]),
                .duplicateRuleID
            ),
            (
                Vocabulary(rules: [
                    VocabularyRule(spoken: "unsafe", written: "\u{202E}value")
                ]),
                .invalidTerm
            ),
            (
                Vocabulary(rules: [
                    VocabularyRule(
                        spoken: String(repeating: "x", count: 257),
                        written: "Too Long"
                    )
                ]),
                .invalidTerm
            ),
            (
                Vocabulary(rules: [
                    VocabularyRule(spoken: " padded ", written: "Padded")
                ]),
                .invalidTerm
            ),
            (
                Vocabulary(rules: [
                    VocabularyRule(
                        spoken: "flow",
                        written: "Flow",
                        profileIDs: ["coding", "coding"]
                    )
                ]),
                .invalidProfileReference
            ),
            (
                Vocabulary(rules: [
                    VocabularyRule(
                        spoken: "flow",
                        written: "Flow",
                        profileIDs: ["unknown"]
                    )
                ]),
                .invalidProfileReference
            ),
            (
                Vocabulary(rules: [
                    VocabularyRule(
                        spoken: "flow",
                        written: "One",
                        profileIDs: ["coding", "email"]
                    ),
                    VocabularyRule(
                        spoken: "FLOW",
                        written: "Two",
                        profileIDs: ["email", "coding"]
                    ),
                ]),
                .duplicateRuleScope
            ),
        ]

        for (vocabulary, expectedError) in invalidCases {
            XCTAssertThrowsError(try VocabularyStore.saveOrThrow(vocabulary)) { error in
                XCTAssertEqual(error as? VocabularyImportError, expectedError)
            }
        }
    }

    func testPersistenceAllowsGlobalBroadAndNarrowOverrides() throws {
        let fileURL = temporaryVocabularyFile()
        let vocabulary = Vocabulary(rules: [
            VocabularyRule(spoken: "flow", written: "Global Flow"),
            VocabularyRule(
                spoken: "flow",
                written: "Broad Flow",
                profileIDs: ["coding", "email"]
            ),
            VocabularyRule(spoken: "flow", written: "Coding Flow", profileIDs: ["coding"]),
        ])

        try VocabularyStore.saveOrThrow(vocabulary, to: fileURL)

        XCTAssertEqual(VocabularyStore.load(from: fileURL), vocabulary)
    }

    func testPersistenceRejectsVocabularyWhosePortableExportExceedsImportLimit() {
        let padding = String(repeating: "x", count: 110)
        let vocabulary = Vocabulary(
            rules: (0..<VocabularyStore.maximumVocabularyRules).map {
                VocabularyRule(
                    spoken: "spoken-\($0)-\(padding)",
                    written: "written-\($0)-\(padding)"
                )
            })
        XCTAssertGreaterThan(
            VocabularyStore.exportCSV(vocabulary).lengthOfBytes(using: .utf8),
            VocabularyStore.maximumImportBytes
        )

        XCTAssertThrowsError(try VocabularyStore.saveOrThrow(vocabulary)) { error in
            XCTAssertEqual(error as? VocabularyImportError, .portableExportTooLarge)
        }
    }

    func testCSVImportRejectsTwoSubLimitInputsThatAccumulateBeyondPortableLimit() throws {
        let padding = String(repeating: "x", count: 110)
        let firstCSV = (0..<5_000).map {
            "spoken-\($0)-\(padding),written-\($0)-\(padding)"
        }.joined(separator: "\n")
        let secondCSV = (5_000..<10_000).map {
            "spoken-\($0)-\(padding),written-\($0)-\(padding)"
        }.joined(separator: "\n")
        XCTAssertLessThan(firstCSV.lengthOfBytes(using: .utf8), VocabularyStore.maximumImportBytes)
        XCTAssertLessThan(
            secondCSV.lengthOfBytes(using: .utf8),
            VocabularyStore.maximumImportBytes
        )

        let first = try VocabularyStore.importCSVReport(firstCSV, into: Vocabulary()).vocabulary
        XCTAssertLessThan(
            VocabularyStore.exportCSV(first).lengthOfBytes(using: .utf8),
            VocabularyStore.maximumImportBytes
        )

        XCTAssertThrowsError(try VocabularyStore.importCSVReport(secondCSV, into: first)) {
            error in
            XCTAssertEqual(error as? VocabularyImportError, .portableExportTooLarge)
        }
    }

    func testDeletionOnlyRecoveryShrinksAnOversizedLegacyStoreIncrementally() throws {
        let fileURL = temporaryVocabularyFile()
        let original = Vocabulary(
            rules: (0..<(VocabularyStore.maximumVocabularyRules + 2)).map {
                VocabularyRule(spoken: "term \($0)", written: "Written \($0)")
            })
        try persistLegacyVocabulary(original, to: fileURL)

        var firstCandidate = original
        firstCandidate.rules.removeFirst()
        try VocabularyStore.saveDeletionOnly(firstCandidate, to: fileURL)
        XCTAssertEqual(VocabularyStore.load(from: fileURL), firstCandidate)

        var secondCandidate = firstCandidate
        secondCandidate.rules.removeFirst()
        try VocabularyStore.saveDeletionOnly(secondCandidate, to: fileURL)
        XCTAssertEqual(secondCandidate.rules.count, VocabularyStore.maximumVocabularyRules)
        XCTAssertEqual(VocabularyStore.load(from: fileURL), secondCandidate)
    }

    func testKeyedDeletionPreservesRuleAddedAfterViewSnapshot() throws {
        let fileURL = temporaryVocabularyFile()
        let first = VocabularyRule(spoken: "first", written: "First")
        let second = VocabularyRule(spoken: "second", written: "Second")
        let original = Vocabulary(rules: [first, second])
        try VocabularyStore.saveOrThrow(original, to: fileURL)

        var staleViewCandidate = original
        staleViewCandidate.rules.removeAll { $0.id == first.id }
        let later = VocabularyRule(spoken: "later", written: "Later")
        try VocabularyStore.addRule(later, to: fileURL)

        XCTAssertThrowsError(
            try VocabularyStore.saveDeletionOnly(staleViewCandidate, to: fileURL)
        ) { error in
            XCTAssertEqual(error as? VocabularyImportError, .invalidDeletion)
        }
        XCTAssertEqual(VocabularyStore.load(from: fileURL).rules, [first, second, later])

        let persisted = try VocabularyStore.removeRule(id: first.id, from: fileURL)
        XCTAssertEqual(persisted.rules, [second, later])
        XCTAssertEqual(VocabularyStore.load(from: fileURL), persisted)
    }

    func testAtomicAddUsesLatestPersistedVocabularyInsteadOfStaleSnapshot() throws {
        let fileURL = temporaryVocabularyFile()
        let original = VocabularyRule(spoken: "original", written: "Original")
        try VocabularyStore.saveOrThrow(Vocabulary(rules: [original]), to: fileURL)

        let staleSnapshot = VocabularyStore.load(from: fileURL)
        let later = VocabularyRule(spoken: "later", written: "Later")
        let addedFromStaleView = VocabularyRule(spoken: "view rule", written: "View Rule")
        try VocabularyStore.addRule(later, to: fileURL)

        XCTAssertFalse(staleSnapshot.rules.contains { $0.id == later.id })
        let persisted = try VocabularyStore.addRule(addedFromStaleView, to: fileURL)
        XCTAssertEqual(persisted.rules, [original, later, addedFromStaleView])
    }

    func testAtomicImportUsesRulesAddedAfterImportViewSnapshot() throws {
        let fileURL = temporaryVocabularyFile()
        let original = VocabularyRule(spoken: "original", written: "Original")
        try VocabularyStore.saveOrThrow(Vocabulary(rules: [original]), to: fileURL)

        let staleSnapshot = VocabularyStore.load(from: fileURL)
        let later = VocabularyRule(spoken: "later", written: "Later")
        try VocabularyStore.addRule(later, to: fileURL)
        let staleReport = try VocabularyStore.importCSVReport(
            "imported,Imported",
            into: staleSnapshot
        )
        XCTAssertFalse(staleReport.vocabulary.rules.contains { $0.id == later.id })

        let persistedReport = try VocabularyStore.importCSVAndSave(
            "imported,Imported",
            to: fileURL
        )
        XCTAssertEqual(persistedReport.importedCount, 1)
        XCTAssertEqual(persistedReport.vocabulary.rules.prefix(2), [original, later])
        XCTAssertEqual(persistedReport.vocabulary.rules.last?.written, "Imported")
        XCTAssertEqual(VocabularyStore.load(from: fileURL), persistedReport.vocabulary)
    }

    func testCompareAndSwapRejectsEditAfterConcurrentAddition() throws {
        let fileURL = temporaryVocabularyFile()
        let original = VocabularyRule(spoken: "original", written: "Original")
        let snapshot = Vocabulary(rules: [original])
        try VocabularyStore.saveOrThrow(snapshot, to: fileURL)

        let later = VocabularyRule(spoken: "later", written: "Later")
        try VocabularyStore.addRule(later, to: fileURL)
        var editedSnapshot = snapshot
        editedSnapshot.rules[0].written = "Edited"

        XCTAssertThrowsError(
            try VocabularyStore.saveIfUnchanged(
                editedSnapshot,
                from: snapshot,
                to: fileURL
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyImportError, .staleWrite)
        }
        XCTAssertEqual(VocabularyStore.load(from: fileURL).rules, [original, later])
    }

    func testDeletionOnlyRecoveryRejectsEditsReorderingAndNonStrictSubsets() throws {
        let fileURL = temporaryVocabularyFile()
        let original = Vocabulary(rules: [
            VocabularyRule(spoken: "one", written: "One"),
            VocabularyRule(spoken: "two", written: "Two"),
            VocabularyRule(spoken: "three", written: "Three"),
        ])
        try VocabularyStore.saveOrThrow(original, to: fileURL)

        var edited = Vocabulary(rules: Array(original.rules.dropFirst()))
        edited.rules[0].written = "Changed"
        XCTAssertThrowsError(try VocabularyStore.saveDeletionOnly(edited, to: fileURL)) { error in
            XCTAssertEqual(error as? VocabularyImportError, .invalidDeletion)
        }

        let reordered = Vocabulary(rules: [original.rules[2], original.rules[1]])
        XCTAssertThrowsError(try VocabularyStore.saveDeletionOnly(reordered, to: fileURL)) {
            error in
            XCTAssertEqual(error as? VocabularyImportError, .invalidDeletion)
        }

        XCTAssertThrowsError(try VocabularyStore.saveDeletionOnly(original, to: fileURL)) {
            error in
            XCTAssertEqual(error as? VocabularyImportError, .invalidDeletion)
        }
        XCTAssertEqual(VocabularyStore.load(from: fileURL), original)
    }

    func testHashPrefixedTermIsNotTreatedAsAComment() throws {
        let report = try VocabularyStore.importCSVReport(
            "#include,C include,false,coding",
            into: Vocabulary()
        )

        XCTAssertEqual(report.importedCount, 1)
        XCTAssertEqual(report.vocabulary.rules.first?.spoken, "#include")
    }

    func testCSVImportRejectsMalformedQuotes() {
        XCTAssertThrowsError(
            try VocabularyStore.importCSVReport("\"unterminated,value", into: Vocabulary())
        ) { error in
            XCTAssertEqual(error as? VocabularyImportError, .malformedCSV)
        }
    }

    private func temporaryVocabularyFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vocabulary-\(UUID().uuidString).enc")
    }

    private func persistLegacyVocabulary(_ vocabulary: Vocabulary, to fileURL: URL) throws {
        let data = try JSONEncoder().encode(vocabulary)
        try SecureStore.writeEncrypted(data, to: fileURL)
    }
}
