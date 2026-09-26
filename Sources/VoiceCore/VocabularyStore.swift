import Foundation

public struct VocabularyImportReport: Sendable, Equatable {
    public let vocabulary: Vocabulary
    public let importedCount: Int
    public let skippedCount: Int

    public init(vocabulary: Vocabulary, importedCount: Int, skippedCount: Int) {
        self.vocabulary = vocabulary
        self.importedCount = importedCount
        self.skippedCount = skippedCount
    }
}

public enum VocabularyImportError: LocalizedError, Equatable {
    case fileTooLarge
    case tooManyRows
    case tooManyRecords
    case tooManyRules
    case duplicateRuleID
    case invalidTerm
    case invalidProfileReference
    case duplicateRuleScope
    case portableExportTooLarge
    case invalidDeletion
    case staleWrite
    case malformedCSV

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "The vocabulary file is larger than the 2 MB import limit."
        case .tooManyRows:
            return "The vocabulary file contains more than 10,000 rule rows."
        case .tooManyRecords:
            return "The vocabulary file contains too many non-rule records to process safely."
        case .tooManyRules:
            return "The vocabulary would contain more than 10,000 rules."
        case .duplicateRuleID:
            return "Every vocabulary rule must have a unique identifier."
        case .invalidTerm:
            return "Vocabulary terms must be 1–256 safe characters without surrounding whitespace."
        case .invalidProfileReference:
            return "A vocabulary rule refers to an unavailable or repeated profile."
        case .duplicateRuleScope:
            return "Only one rule can use the same spoken term in the same profile scope."
        case .portableExportTooLarge:
            return "The vocabulary is too large to export and restore within the 2 MB limit."
        case .invalidDeletion:
            return "The vocabulary changed before that rule could be removed. Reload and try again."
        case .staleWrite:
            return "The vocabulary changed before this update could be saved. Reload and try again."
        case .malformedCSV:
            return "The vocabulary file is not valid CSV."
        }
    }
}

/// Shared encrypted persistence for the user's custom vocabulary.
public enum VocabularyStore {
    public static let maximumImportBytes = 2 * 1_024 * 1_024
    public static let maximumImportRows = 10_000
    public static let maximumVocabularyRules = 10_000
    private static let maximumTermCharacters = 256
    private static let maximumTermBytes = 4_096
    private static let maximumParsedRecords = maximumImportRows + 100
    private static let persistenceLock = NSLock()

    public static func load() -> Vocabulary {
        load(from: AppPaths.vocabularyFile)
    }

    static func load(from fileURL: URL) -> Vocabulary {
        do {
            return try withPersistenceLock {
                guard let vocabulary = try loadPersistedVocabulary(from: fileURL) else {
                    return Vocabulary()
                }
                return vocabulary
            }
        } catch {
            FlowLog.error("vocabulary load failed code=\(errorCode: error)")
            return Vocabulary()
        }
    }

    /// Whole-store replacement is deliberately internal. Interactive callers
    /// must use the atomic operations below so a stale in-memory snapshot cannot
    /// erase a rule that another window or correction flow added later.
    static func saveOrThrow(_ vocabulary: Vocabulary) throws {
        try saveOrThrow(vocabulary, to: AppPaths.vocabularyFile)
    }

    static func saveOrThrow(_ vocabulary: Vocabulary, to fileURL: URL) throws {
        try validateForPersistence(vocabulary)
        try withPersistenceLock {
            try write(vocabulary, to: fileURL)
        }
    }

    /// Atomically appends one rule to the latest encrypted vocabulary.
    ///
    /// The current file is read again while the persistence lock is held; the
    /// caller's potentially stale view state is never used as the write base.
    @discardableResult
    public static func addRule(_ rule: VocabularyRule) throws -> Vocabulary {
        try addRule(rule, to: AppPaths.vocabularyFile)
    }

    @discardableResult
    static func addRule(_ rule: VocabularyRule, to fileURL: URL) throws -> Vocabulary {
        try withPersistenceLock {
            var current = try loadPersistedVocabulary(from: fileURL) ?? Vocabulary()
            current.rules.append(rule)
            try validateForPersistence(current)
            try write(current, to: fileURL)
            return current
        }
    }

    /// Atomically removes exactly the rule identified by `id` from the latest
    /// encrypted vocabulary and returns the persisted result. This also provides
    /// the safe recovery path for a legacy vocabulary that exceeds current
    /// limits: every other persisted rule remains byte-for-byte unchanged.
    @discardableResult
    public static func removeRule(id: UUID) throws -> Vocabulary {
        try removeRule(id: id, from: AppPaths.vocabularyFile)
    }

    @discardableResult
    static func removeRule(id: UUID, from fileURL: URL) throws -> Vocabulary {
        try withPersistenceLock {
            guard var current = try loadPersistedVocabulary(from: fileURL),
                current.rules.lazy.filter({ $0.id == id }).count == 1
            else {
                throw VocabularyImportError.invalidDeletion
            }
            current.rules.removeAll { $0.id == id }
            try write(current, to: fileURL)
            return current
        }
    }

    /// Compare-and-swap for future whole-rule editing surfaces. A caller must
    /// supply the exact snapshot it edited; a later add, delete, import, or edit
    /// makes the operation fail instead of silently overwriting that change.
    @discardableResult
    public static func saveIfUnchanged(
        _ vocabulary: Vocabulary,
        from expected: Vocabulary
    ) throws -> Vocabulary {
        try saveIfUnchanged(vocabulary, from: expected, to: AppPaths.vocabularyFile)
    }

    @discardableResult
    static func saveIfUnchanged(
        _ vocabulary: Vocabulary,
        from expected: Vocabulary,
        to fileURL: URL
    ) throws -> Vocabulary {
        try validateForPersistence(vocabulary)
        return try withPersistenceLock {
            let current = try loadPersistedVocabulary(from: fileURL) ?? Vocabulary()
            guard current == expected else {
                throw VocabularyImportError.staleWrite
            }
            try write(vocabulary, to: fileURL)
            return vocabulary
        }
    }

    /// Persists a deletion even when a legacy vocabulary cannot pass current
    /// limits yet. The candidate must be an ordered, strict subset of the rule
    /// IDs currently stored on disk, and every retained rule must be unchanged.
    /// This lets an oversized legacy store be reduced one rule at a time without
    /// turning the recovery path into a validation bypass for additions or edits.
    static func saveDeletionOnly(_ vocabulary: Vocabulary, to fileURL: URL) throws {
        try withPersistenceLock {
            guard let persisted = try loadPersistedVocabulary(from: fileURL) else {
                throw VocabularyImportError.invalidDeletion
            }
            let persistedIDs = Set(persisted.rules.map(\.id))
            let candidateIDs = Set(vocabulary.rules.map(\.id))
            guard persistedIDs.count == persisted.rules.count,
                candidateIDs.count == vocabulary.rules.count,
                persistedIDs.count == candidateIDs.count + 1,
                candidateIDs.isSubset(of: persistedIDs)
            else {
                throw VocabularyImportError.invalidDeletion
            }
            let expectedRules = persisted.rules.filter { candidateIDs.contains($0.id) }
            guard expectedRules == vocabulary.rules else {
                throw VocabularyImportError.invalidDeletion
            }
            try write(vocabulary, to: fileURL)
        }
    }

    /// Parses and atomically imports CSV into the latest encrypted vocabulary.
    /// Concurrent additions are part of the import base and therefore cannot be
    /// erased by an import started from an older view snapshot.
    public static func importCSVAndSave(_ text: String) throws -> VocabularyImportReport {
        try importCSVAndSave(text, to: AppPaths.vocabularyFile)
    }

    static func importCSVAndSave(
        _ text: String,
        to fileURL: URL
    ) throws -> VocabularyImportReport {
        try withPersistenceLock {
            let current = try loadPersistedVocabulary(from: fileURL) ?? Vocabulary()
            let report = try importCSVReport(text, into: current)
            try validateForPersistence(report.vocabulary)
            try write(report.vocabulary, to: fileURL)
            return report
        }
    }

    private static func loadPersistedVocabulary(from fileURL: URL) throws -> Vocabulary? {
        guard let data = try SecureStore.readEncrypted(from: fileURL) else {
            return nil
        }
        return try JSONDecoder().decode(Vocabulary.self, from: data)
    }

    private static func write(_ vocabulary: Vocabulary, to fileURL: URL) throws {
        let data = try JSONEncoder().encode(vocabulary)
        try SecureStore.writeEncrypted(data, to: fileURL)
    }

    private static func withPersistenceLock<T>(_ operation: () throws -> T) rethrows -> T {
        persistenceLock.lock()
        defer { persistenceLock.unlock() }
        return try operation()
    }

    /// Compatibility wrapper for callers that do not surface an import report.
    /// CSV columns are `spoken,written[,caseSensitive[,profiles]]`; profiles are
    /// separated by `|`. Quoted commas and CRLF input are supported.
    public static func importCSV(_ text: String, into vocabulary: Vocabulary) -> Vocabulary {
        (try? importCSVReport(text, into: vocabulary).vocabulary) ?? vocabulary
    }

    public static func importCSVReport(
        _ text: String,
        into vocabulary: Vocabulary
    ) throws -> VocabularyImportReport {
        guard text.lengthOfBytes(using: .utf8) <= maximumImportBytes else {
            throw VocabularyImportError.fileTooLarge
        }
        let rows = try parseCSV(text)
        guard vocabulary.rules.count <= maximumVocabularyRules else {
            throw VocabularyImportError.tooManyRules
        }

        var result = vocabulary
        var importedCount = 0
        var skippedCount = 0
        var ruleRowCount = 0
        let knownProfiles = Set(AppProfile.builtIn.map(\.id))
        var occupiedScopes = ImportScopeIndex(rules: result.rules)

        for rawFields in rows {
            let fields = rawFields.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard fields.contains(where: { !$0.isEmpty }) else { continue }
            if fields.count == 1, fields[0].hasPrefix("#") { continue }
            if isHeader(fields) { continue }
            ruleRowCount += 1
            guard ruleRowCount <= maximumImportRows else {
                throw VocabularyImportError.tooManyRows
            }
            guard fields.count >= 2, fields.count <= 4 else {
                skippedCount += 1
                continue
            }

            let spoken = fields[0].precomposedStringWithCanonicalMapping
            let written = fields[1].precomposedStringWithCanonicalMapping
            guard validTerm(spoken), validTerm(written) else {
                skippedCount += 1
                continue
            }

            let caseSensitive: Bool
            if fields.count < 3 || fields[2].isEmpty {
                caseSensitive = false
            } else {
                switch fields[2].lowercased() {
                case "true", "yes", "1": caseSensitive = true
                case "false", "no", "0": caseSensitive = false
                default:
                    skippedCount += 1
                    continue
                }
            }

            let profileIDs: [String]?
            if fields.count < 4 || fields[3].isEmpty {
                profileIDs = nil
            } else {
                let parsed = fields[3]
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard !parsed.contains(where: { $0.isEmpty }),
                    Set(parsed).isSubset(of: knownProfiles)
                else {
                    skippedCount += 1
                    continue
                }
                profileIDs = Array(Set(parsed)).sorted()
            }

            let rule = VocabularyRule(
                spoken: spoken,
                written: written,
                caseSensitive: caseSensitive,
                profileIDs: profileIDs
            )
            guard occupiedScopes.insertIfAvailable(rule) else {
                skippedCount += 1
                continue
            }
            guard result.rules.count < maximumVocabularyRules else {
                throw VocabularyImportError.tooManyRules
            }
            result.rules.append(rule)
            importedCount += 1
        }
        guard exportCSV(result).lengthOfBytes(using: .utf8) <= maximumImportBytes else {
            throw VocabularyImportError.portableExportTooLarge
        }
        return VocabularyImportReport(
            vocabulary: result,
            importedCount: importedCount,
            skippedCount: skippedCount
        )
    }

    public static func exportCSV(_ vocabulary: Vocabulary) -> String {
        var lines = [
            "# LockedIn Flow user vocabulary",
            "# First-party profile packs are omitted; reinstall them from Settings.",
            "spoken,written,caseSensitive,profiles",
        ]
        for rule in vocabulary.rules where rule.sourceID == nil {
            let fields = [
                rule.spoken,
                rule.written,
                String(rule.caseSensitive),
                (rule.profileIDs ?? []).sorted().joined(separator: "|"),
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private struct RuleScopeKey: Hashable {
        let spoken: String
        let profileIDs: [String]
    }

    /// Tracks exact scope signatures for each normalized spoken form. Global,
    /// broad, and narrow overrides may coexist; only a second rule with the same
    /// normalized term and identical profile set conflicts.
    private struct ImportScopeIndex {
        private var keys = Set<RuleScopeKey>()

        init(rules: [VocabularyRule]) {
            for rule in rules {
                keys.insert(VocabularyStore.scopeKey(for: rule))
            }
        }

        mutating func insertIfAvailable(_ rule: VocabularyRule) -> Bool {
            keys.insert(VocabularyStore.scopeKey(for: rule)).inserted
        }
    }

    private static func scopeKey(for rule: VocabularyRule) -> RuleScopeKey {
        RuleScopeKey(
            spoken: normalizedSpokenKey(rule.spoken),
            profileIDs: Array(Set(rule.profileIDs ?? [])).sorted()
        )
    }

    private static func validateForPersistence(_ vocabulary: Vocabulary) throws {
        guard vocabulary.rules.count <= maximumVocabularyRules else {
            throw VocabularyImportError.tooManyRules
        }
        let knownProfiles = Set(AppProfile.builtIn.map(\.id))
        var ruleIDs = Set<UUID>()
        var scopes = Set<RuleScopeKey>()
        for rule in vocabulary.rules {
            guard ruleIDs.insert(rule.id).inserted else {
                throw VocabularyImportError.duplicateRuleID
            }
            guard validTerm(rule.spoken), validTerm(rule.written) else {
                throw VocabularyImportError.invalidTerm
            }
            let profileIDs = rule.profileIDs ?? []
            let profileSet = Set(profileIDs)
            guard profileSet.count == profileIDs.count,
                profileSet.isSubset(of: knownProfiles)
            else {
                throw VocabularyImportError.invalidProfileReference
            }
            guard scopes.insert(scopeKey(for: rule)).inserted else {
                throw VocabularyImportError.duplicateRuleScope
            }
        }
        guard exportCSV(vocabulary).lengthOfBytes(using: .utf8) <= maximumImportBytes else {
            throw VocabularyImportError.portableExportTooLarge
        }
    }

    private static func normalizedSpokenKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func validTerm(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == trimmed,
            !value.isEmpty,
            value.count <= maximumTermCharacters,
            value.lengthOfBytes(using: .utf8) <= maximumTermBytes
        else { return false }
        for scalar in value.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) { return false }
            if (0x202A...0x202E).contains(scalar.value)
                || (0x2066...0x2069).contains(scalar.value)
            {
                return false
            }
        }
        return true
    }

    private static func isHeader(_ fields: [String]) -> Bool {
        guard fields.count >= 2,
            fields[0].lowercased() == "spoken",
            fields[1].lowercased() == "written"
        else { return false }
        switch fields.count {
        case 2:
            return true
        case 3:
            return fields[2].lowercased() == "casesensitive"
        case 4:
            return fields[2].lowercased() == "casesensitive"
                && fields[3].lowercased() == "profiles"
        default:
            return false
        }
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseCSV(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var closedQuote = false
        var index = text.startIndex

        func finishField() {
            row.append(field)
            field = ""
            closedQuote = false
        }
        func finishRow() throws {
            finishField()
            guard rows.count < maximumParsedRecords else {
                throw VocabularyImportError.tooManyRecords
            }
            rows.append(row)
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if inQuotes {
                if character == "\"" {
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    inQuotes = false
                    closedQuote = true
                } else {
                    field.append(character)
                }
                index = next
                continue
            }

            if closedQuote {
                if character == "," {
                    finishField()
                } else if character == "\n" || character == "\r\n" {
                    try finishRow()
                } else if character == "\r" {
                    try finishRow()
                    if next < text.endIndex, text[next] == "\n" {
                        index = text.index(after: next)
                        continue
                    }
                } else if !character.isWhitespace {
                    throw VocabularyImportError.malformedCSV
                }
                index = next
                continue
            }

            switch character {
            case "\"":
                guard field.allSatisfy(\.isWhitespace) else {
                    throw VocabularyImportError.malformedCSV
                }
                field = ""
                inQuotes = true
            case ",":
                finishField()
            case "\n", "\r\n":
                try finishRow()
            case "\r":
                try finishRow()
                if next < text.endIndex, text[next] == "\n" {
                    index = text.index(after: next)
                    continue
                }
            default:
                field.append(character)
            }
            index = next
        }
        guard !inQuotes else { throw VocabularyImportError.malformedCSV }
        if !field.isEmpty || !row.isEmpty || closedQuote {
            try finishRow()
        }
        return rows
    }
}
