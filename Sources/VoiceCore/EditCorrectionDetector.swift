import Foundation

/// A correction inferred from the user editing text the app just inserted:
/// the app wrote `spoken`, the person changed it to `written`.
public struct EditLearnedCorrection: Sendable, Equatable {
    public let spoken: String
    public let written: String

    public init(spoken: String, written: String) {
        self.spoken = spoken
        self.written = written
    }
}

/// Detects a single, learnable word or short-phrase substitution between the
/// text LockedIn Flow inserted and the text as the person edited it.
///
/// Deliberately conservative: it proposes a correction only when exactly one
/// contiguous span changed, both sides are short, the replacement looks like
/// vocabulary (a name, product, or term — not grammar, casing noise, or
/// numbers), and the replaced span actually came from the inserted text. It
/// never proposes changes to numeric content.
public enum EditCorrectionDetector {
    /// Words too common to ever learn as a spoken form on their own.
    /// Single-word corrections must replace something distinctive.
    private static let commonWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
        "had", "has", "have", "he", "her", "his", "i", "in", "is", "it", "its",
        "me", "my", "not", "of", "on", "or", "our", "she", "so", "that", "the",
        "their", "them", "then", "there", "they", "this", "to", "was", "we",
        "were", "what", "when", "which", "who", "will", "with", "you", "your",
    ]

    /// Compares the originally inserted text with the edited text and returns
    /// the one learnable substitution, or nil when there is nothing safe to
    /// learn.
    ///
    /// `insertedSpan` optionally narrows the guard to the app's own output:
    /// when the watched field contained other content, pass the exact text
    /// the app inserted so an edit elsewhere in the field is never learned.
    public static func detect(
        inserted: String,
        edited: String,
        insertedSpan: String? = nil,
        maximumPhraseWords: Int = 3
    ) -> EditLearnedCorrection? {
        guard inserted != edited else { return nil }

        let insertedWords = words(of: inserted)
        let editedWords = words(of: edited)
        guard !insertedWords.isEmpty, !editedWords.isEmpty else { return nil }

        // Locate the single changed middle by stripping the common prefix and
        // suffix of the word sequences. Two separate edits merge into one long
        // middle and fail the phrase-length guard below.
        var prefix = 0
        while prefix < insertedWords.count,
            prefix < editedWords.count,
            insertedWords[prefix] == editedWords[prefix]
        {
            prefix += 1
        }
        var suffix = 0
        while suffix < insertedWords.count - prefix,
            suffix < editedWords.count - prefix,
            insertedWords[insertedWords.count - 1 - suffix]
                == editedWords[editedWords.count - 1 - suffix]
        {
            suffix += 1
        }

        let spokenTokens = Array(insertedWords[prefix..<(insertedWords.count - suffix)])
        let writtenTokens = Array(editedWords[prefix..<(editedWords.count - suffix)])

        // A substitution only: pure insertions or deletions are formatting
        // choices, not vocabulary.
        guard !spokenTokens.isEmpty, !writtenTokens.isEmpty else { return nil }
        guard spokenTokens.count <= maximumPhraseWords,
            writtenTokens.count <= maximumPhraseWords
        else { return nil }

        let spoken = phrase(from: spokenTokens)
        let written = phrase(from: writtenTokens)
        guard !spoken.isEmpty, !written.isEmpty, spoken != written else { return nil }

        // Numeric content is never learned or rewritten.
        guard !containsNumericToken(spokenTokens),
            !containsNumericToken(writtenTokens)
        else { return nil }

        // The replacement must look like vocabulary — a capitalized name, a
        // term with internal structure, or a non-ASCII spelling — so grammar
        // edits ("there" → "their") are not memorized.
        guard looksLikeVocabulary(written) else { return nil }

        // Single common words are never used as a trigger: rewriting "the"
        // everywhere would corrupt every future dictation.
        if spokenTokens.count == 1, commonWords.contains(spoken.lowercased()) {
            return nil
        }

        // The replaced span must be the app's own output.
        if let insertedSpan {
            guard insertedSpan.range(of: spoken, options: [.caseInsensitive]) != nil else {
                return nil
            }
        }

        return EditLearnedCorrection(spoken: spoken, written: written)
    }

    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    /// Joins tokens and trims sentence punctuation from the phrase edges while
    /// preserving internal punctuation ("Dr. Jawad's" stays intact).
    private static func phrase(from tokens: [String]) -> String {
        let joined = tokens.joined(separator: " ")
        let edgePunctuation = CharacterSet(charactersIn: ".,;:!?\"'()[]{}")
        return joined.trimmingCharacters(in: edgePunctuation)
    }

    private static func containsNumericToken(_ tokens: [String]) -> Bool {
        tokens.contains { token in
            let stripped = token.trimmingCharacters(
                in: CharacterSet(charactersIn: ".,;:!?%$#")
            )
            guard !stripped.isEmpty else { return false }
            return stripped.allSatisfy {
                $0.isNumber || $0 == "." || $0 == "," || $0 == "/" || $0 == "-" || $0 == ":"
            }
                && stripped.contains(where: \.isNumber)
        }
    }

    /// Mirrors the "distinctive term" shape VocabularySuggester mines for:
    /// capitalized, containing non-ASCII letters, or containing structural
    /// characters like dots or hyphens inside an identifier.
    private static func looksLikeVocabulary(_ written: String) -> Bool {
        let tokens = words(of: written)
        guard !tokens.isEmpty else { return false }
        return tokens.contains { token in
            guard let first = token.first else { return false }
            if first.isUppercase { return true }
            if token.contains(where: { !$0.isASCII && $0.isLetter }) { return true }
            let interior = token.dropFirst().dropLast()
            if interior.contains(".") || interior.contains("-") || interior.contains("_") {
                return true
            }
            return false
        }
    }
}
