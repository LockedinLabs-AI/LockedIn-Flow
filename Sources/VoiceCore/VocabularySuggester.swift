import Foundation

public struct VocabularySuggestion: Sendable, Equatable, Identifiable {
    public var id: String { term }
    public let term: String
    public let count: Int
}

/// Suggests vocabulary rules by scanning (local, encrypted) dictation history for
/// frequently used terms that aren't in the dictionary yet. All processing is
/// on-device; suggestions are reviewable and dismissible — nothing is auto-learned.
public enum VocabularySuggester {
    /// Words too common to be worth a rule.
    private static let stoplist: Set<String> = [
        "the", "and", "that", "this", "with", "have", "from", "they", "what", "when",
        "your", "you", "for", "are", "was", "were", "been", "will", "would", "could",
        "should", "about", "there", "their", "them", "then", "than", "just", "like",
        "know", "think", "want", "need", "going", "really", "right", "okay", "yeah",
        "well", "also", "some", "into", "over", "under", "again", "still", "here",
        "where", "which", "while", "these", "those", "because", "before", "after",
        "between", "through", "during", "does", "did", "done", "make", "made", "take",
        "took", "get", "got", "say", "said", "tell", "told", "give", "gave", "find",
        "found", "work", "works", "working", "look", "looking", "see", "seen", "way",
        "thing", "things", "something", "anything", "everything", "nothing", "much",
        "many", "more", "most", "other", "another", "each", "every", "both", "few",
        "own", "same", "new", "old", "first", "last", "next", "good", "great", "best",
        "better", "little", "big", "long", "small", "large", "high", "low", "early",
        "late", "sure", "maybe", "probably", "actually", "basically", "literally",
        "hello", "thanks", "thank", "please", "yes", "not", "but", "how", "why", "who",
        "whom", "whose", "him", "his", "her", "hers", "its", "our", "ours", "mine",
        "yours", "theirs", "myself", "itself", "today", "tomorrow", "yesterday", "now",
        "soon", "later", "often", "always", "never", "sometimes", "usually", "very",
        "too", "quite", "rather", "pretty", "almost", "already", "yet", "even", "ever",
    ]

    /// - Parameters:
    ///   - entries: history to analyze (uses final text)
    ///   - vocabulary: current rules — their spoken and written forms are excluded
    ///   - minimumCount: minimum occurrences to suggest (default 2)
    ///   - limit: max suggestions returned
    public static func suggest(
        from entries: [HistoryEntry],
        vocabulary: Vocabulary,
        minimumCount: Int = 2,
        limit: Int = 10
    ) -> [VocabularySuggestion] {
        var known = Set<String>()
        for rule in vocabulary.rules {
            known.insert(rule.spoken.lowercased())
            known.insert(rule.written.lowercased())
        }

        var counts: [String: (display: String, count: Int)] = [:]
        for entry in entries {
            let words = entry.final.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for word in words {
                guard word.count >= 3 else { continue }
                let lower = word.lowercased()
                guard !stoplist.contains(lower), !known.contains(lower) else { continue }
                // Only suggest words that look distinctive: contain a capital (not at a
                // sentence start we can detect cheaply), a digit, or a dot (AcmeHealth.ai).
                let isCapitalized = word.first?.isUppercase == true
                let hasDigit = word.contains(where: \.isNumber)
                let hasDot = word.contains(".")
                guard isCapitalized || hasDigit || hasDot else { continue }
                let key = lower
                let existing = counts[key]
                counts[key] = (existing?.display ?? word, (existing?.count ?? 0) + 1)
            }
        }

        return
            counts
            .filter { $0.value.count >= minimumCount }
            .sorted { $0.value.count > $1.value.count }
            .prefix(limit)
            .map { VocabularySuggestion(term: $0.value.display, count: $0.value.count) }
    }
}
