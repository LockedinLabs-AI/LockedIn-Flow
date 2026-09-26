import Foundation
import VoiceCore

/// Rules-based transcript cleanup: spoken punctuation, filler removal,
/// capitalization, whitespace normalization, terminal punctuation.
/// This is the always-available local cleanup; the LLM cleanup layer (P3)
/// conforms to the same `TextCleaning` protocol.
public struct TranscriptCleaner: Sendable {
    public var interpretSpokenPunctuation: Bool
    public var removeFillers: Bool

    public init(interpretSpokenPunctuation: Bool = true, removeFillers: Bool = true) {
        self.interpretSpokenPunctuation = interpretSpokenPunctuation
        self.removeFillers = removeFillers
    }

    /// Longest phrase first so "new paragraph" wins over "new".
    static let punctuationPhrases: [(phrase: [String], symbol: String)] = [
        (["new", "paragraph"], "\n\n"),
        (["bullet", "point"], "\n- "),
        (["new", "line"], "\n"),
        (["question", "mark"], "?"),
        (["exclamation", "point"], "!"),
        (["exclamation", "mark"], "!"),
        (["open", "parenthesis"], "("),
        (["close", "parenthesis"], ")"),
        (["open", "paren"], "("),
        (["close", "paren"], ")"),
        (["full", "stop"], "."),
        (["em", "dash"], "—"),
        (["semi", "colon"], ";"),
        (["semicolon"], ";"),
        (["percent", "sign"], "%"),
        (["dollar", "sign"], "$"),
        (["at", "sign"], "@"),
        (["colon"], ":"),
        (["comma"], ","),
        (["period"], "."),
        (["ellipsis"], "…"),
        (["hyphen"], "-"),
        (["dash"], "—"),
    ]

    static let closers: Set<String> = [",", ".", "?", "!", ";", ":", ")", "]", "%", "…"]
    static let joiners: Set<String> = ["-", "—"]

    /// Short function words commonly repeated while a speaker is finding their
    /// next phrase. Content words are intentionally excluded so emphasis such as
    /// "very very important" remains intact.
    static let hesitationRepeatWords = [
        "i", "we", "you", "they", "he", "she", "it",
        "a", "an", "the", "to", "and", "but",
    ]

    /// Repeated phrases are only collapsed when they begin like a likely spoken
    /// restart. This deliberately excludes content-led spans such as proper
    /// names ("New York") and emphasis ("very important").
    static let likelyFalseStartLeadWords: Set<String> = [
        "i", "we", "you", "they", "he", "she", "it",
        "a", "an", "the", "to", "and", "but", "please",
        "let", "lets", "let's", "can", "could", "should", "would", "will",
        "do", "does", "did", "is", "are", "was", "were",
        "send", "make", "need", "want", "think", "this", "that",
        "there", "here", "my", "our", "your",
    ]

    /// Conservative corrections for forms that are overwhelmingly transcription
    /// or spelling errors. Ambiguous forms such as "its", "well", "ill", and
    /// "were" are deliberately omitted.
    static let commonCorrections: [String: String] = [
        "i": "I",
        "im": "I'm",
        "ive": "I've",
        "youre": "you're",
        "theyre": "they're",
        "weve": "we've",
        "youve": "you've",
        "theyve": "they've",
        "dont": "don't",
        "doesnt": "doesn't",
        "didnt": "didn't",
        "cant": "can't",
        "couldnt": "couldn't",
        "shouldnt": "shouldn't",
        "wouldnt": "wouldn't",
        "wont": "won't",
        "isnt": "isn't",
        "arent": "aren't",
        "wasnt": "wasn't",
        "werent": "weren't",
        "hasnt": "hasn't",
        "havent": "haven't",
        "hadnt": "hadn't",
        "thats": "that's",
        "whats": "what's",
        "heres": "here's",
        "theres": "there's",
        "teh": "the",
        "adn": "and",
        "alot": "a lot",
        "becuase": "because",
        "definately": "definitely",
        "occured": "occurred",
        "recieve": "receive",
        "seperate": "separate",
        "wierd": "weird",
    ]

    public func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if interpretSpokenPunctuation { text = applySpokenPunctuation(to: text) }
        if removeFillers { text = removeFillerWords(from: text) }
        text = normalizeWhitespace(text)
        // Turning both interpretation options off is the explicit literal path.
        // Preserve its words exactly as spoken while retaining the existing basic
        // whitespace, capitalization, and terminal-punctuation behavior.
        if interpretSpokenPunctuation || removeFillers {
            text = applySafeClauseRestarts(to: text)
            text = removeImmediateRepeatedPhrases(from: text)
            text = removeRepeatedHesitations(from: text)
            text = correctCommonErrors(in: text)
            text = normalizeWhitespace(text)
        }
        text = capitalizeSentences(text)
        text = ensureTerminalPunctuation(text)
        return text
    }

    func applySpokenPunctuation(to text: String) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var output = ""
        var i = 0

        func appendSymbol(_ symbol: String) {
            if symbol.hasPrefix("\n") {
                output = output.trimmingCharacters(in: CharacterSet(charactersIn: " "))
                output += symbol
            } else if Self.closers.contains(symbol) || Self.joiners.contains(symbol) {
                output = output.trimmingCharacters(in: CharacterSet(charactersIn: " "))
                output += symbol + " "
            } else if symbol == "(" {
                if !output.isEmpty, !output.hasSuffix(" "), !output.hasSuffix("\n") {
                    output += " "
                }
                output += symbol
            } else if symbol == ")" {
                output = output.trimmingCharacters(in: CharacterSet(charactersIn: " "))
                output += ") "
            } else {
                output += symbol + " "
            }
        }

        while i < tokens.count {
            var matched = false
            for entry in Self.punctuationPhrases {
                let count = entry.phrase.count
                guard i + count <= tokens.count else { continue }
                let slice = tokens[i..<(i + count)].map {
                    $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?"))
                }
                if slice == entry.phrase {
                    appendSymbol(entry.symbol)
                    i += count
                    matched = true
                    break
                }
            }
            if !matched {
                if !output.isEmpty, !output.hasSuffix(" "), !output.hasSuffix("\n"),
                    !output.hasSuffix("(")
                {
                    output += " "
                }
                output += tokens[i]
                i += 1
            }
        }
        return output
    }

    func removeFillerWords(from text: String) -> String {
        // Covers lengthened and mixed filler spellings such as "ummm", "uhhh",
        // "ahh", "ermm", and "errmm", without matching inside content words or
        // meaningful compounds such as "uh-oh". Nearby pause punctuation is
        // removed with the filler so it cannot be stranded in the final prose.
        let pattern =
            #"(?:[ \t]*([,;:—])[ \t]*)?(?<![-'’])\b(u+h*m+|u+h+|a+h+|e+r+m+)\b(?![-'’])(?:[ \t]*([,;:—]+|\.{2,}|…+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                let fillerRange = Range(match.range(at: 2), in: result)
            else { continue }
            let filler = String(result[fillerRange])
            // Preserve deliberate two-letter all-caps tokens such as the
            // ampere-hour unit "AH" and identifiers such as "UM". Lengthened
            // forms such as "ERMM" remain unambiguously filler speech.
            if filler.count == 2, filler == filler.uppercased() { continue }

            let leading = Range(match.range(at: 1), in: result).map { String(result[$0]) }
            let trailing = Range(match.range(at: 3), in: result).map { String(result[$0]) }
            let replacement: String
            if leading == ";" || leading == ":" {
                // These separators usually encode an intentional clause
                // boundary, including when produced by a spoken command.
                replacement = "\(leading!) "
            } else if leading == "—", trailing != "—" {
                // Preserve a single clause-separating dash; paired dashes
                // around a filler are hesitation punctuation and can disappear.
                replacement = "— "
            } else {
                replacement = " "
            }
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    func removeRepeatedHesitations(from text: String) -> String {
        let words = Self.hesitationRepeatWords
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern = #"\b("# + words + #")\b(?:[ \t]*[,—-]?[ \t]+\1\b)+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else {
            return text
        }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                let wordRange = Range(match.range(at: 1), in: result)
            else { continue }
            let word = String(result[wordRange])
            if word.count > 1, word == word.uppercased() { continue }
            result.replaceSubrange(fullRange, with: word)
        }
        return result
    }

    /// Removes an immediately repeated phrase when the repetition is strong
    /// evidence of a false start: both copies contain at least two words, at
    /// least two distinct words, plain word spacing, and no sentence boundary.
    ///
    /// Keeping this separate from `removeRepeatedHesitations` is intentional.
    /// A sequence such as "very very" is emphasis, not a duplicated phrase,
    /// and all-caps spans are often identifiers rather than prose.
    func removeImmediateRepeatedPhrases(from text: String) -> String {
        var result = text
        while let range = firstImmediateRepeatedPhrase(in: result) {
            result.removeSubrange(range)
        }
        return result
    }

    /// Applies an explicit full-clause restart only when "scratch that" is
    /// followed by a recognizably parallel replacement. For example,
    /// "send it Thursday scratch that send it Friday" has the shared stem
    /// "send it" and a changed ending on each side. Short corrections such as
    /// "Thursday scratch that Friday" remain verbatim because deleting their
    /// context would require guessing.
    func applySafeClauseRestarts(to text: String) -> String {
        var result = text
        while let range = firstSafeClauseRestart(in: result) {
            result.removeSubrange(range)
        }
        return result
    }

    private struct SpeechWord {
        let text: String
        let range: Range<String.Index>

        var comparisonKey: String {
            text.lowercased()
        }

        var isAllCapsIdentifier: Bool {
            guard text.count > 1,
                text.rangeOfCharacter(from: .letters) != nil
            else { return false }
            return text == text.uppercased() && text != text.lowercased()
        }

        var isTitleCasedWord: Bool {
            let letters = text.filter(\.isLetter)
            guard let first = letters.first, first.isUppercase else { return false }
            return letters.dropFirst().allSatisfy(\.isLowercase)
        }
    }

    private func speechWords(in text: String) -> [SpeechWord] {
        // Apostrophes stay inside a word so contractions compare as a unit.
        let pattern = #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            match in
            guard let range = Range(match.range, in: text) else { return nil }
            return SpeechWord(text: String(text[range]), range: range)
        }
    }

    private func firstImmediateRepeatedPhrase(in text: String) -> Range<String.Index>? {
        let words = speechWords(in: text)
        guard words.count >= 4 else { return nil }

        for start in words.indices {
            let availablePhraseLength = (words.count - start) / 2
            let maximumPhraseLength = min(12, availablePhraseLength)
            guard maximumPhraseLength >= 2 else { continue }

            // Prefer the most complete repeated span at a given position.
            for length in stride(from: maximumPhraseLength, through: 2, by: -1) {
                let secondStart = start + length
                let first = words[start..<(start + length)]
                let second = words[secondStart..<(secondStart + length)]

                guard zip(first, second).allSatisfy({ $0.comparisonKey == $1.comparisonKey }) else {
                    continue
                }
                guard Set(first.map(\.comparisonKey)).count >= 2 else {
                    // Do not reinterpret repeated single-word emphasis as a
                    // multi-word phrase merely because it occurs four times.
                    continue
                }
                guard let leadWord = first.first?.comparisonKey,
                    Self.likelyFalseStartLeadWords.contains(leadWord)
                else {
                    continue
                }
                guard !first.contains(where: \.isAllCapsIdentifier),
                    !second.contains(where: \.isAllCapsIdentifier)
                else {
                    continue
                }
                guard !first.allSatisfy(\.isTitleCasedWord),
                    !second.allSatisfy(\.isTitleCasedWord)
                else {
                    continue
                }
                guard
                    hasOnlyHorizontalWhitespace(
                        betweenWords: start..<(start + length),
                        words: words,
                        in: text),
                    hasOnlyHorizontalWhitespace(
                        betweenWords: secondStart..<(secondStart + length),
                        words: words,
                        in: text)
                else {
                    continue
                }

                let boundary = text[
                    words[start + length - 1].range.upperBound..<words[secondStart].range.lowerBound
                ]
                guard isWeakRepeatBoundary(boundary) else { continue }

                // Drop the abandoned first copy and its weak pause punctuation,
                // retaining the restarted copy and everything after it.
                return words[start].range.lowerBound..<words[secondStart].range.lowerBound
            }
        }
        return nil
    }

    private func firstSafeClauseRestart(in text: String) -> Range<String.Index>? {
        let words = speechWords(in: text)
        guard words.count >= 8 else { return nil }

        for markerStart in 1..<(words.count - 2) {
            guard words[markerStart].comparisonKey == "scratch",
                words[markerStart + 1].comparisonKey == "that",
                hasOnlyHorizontalWhitespace(
                    text[
                        words[markerStart].range
                            .upperBound..<words[markerStart + 1].range.lowerBound]
                )
            else { continue }

            let rightStart = markerStart + 2
            let beforeMarker = text[
                words[markerStart - 1].range.upperBound..<words[markerStart].range.lowerBound]
            let afterMarker = text[
                words[markerStart + 1].range.upperBound..<words[rightStart].range.lowerBound]
            guard isWeakRepeatBoundary(beforeMarker),
                isWeakRepeatBoundary(afterMarker)
            else { continue }

            var leftCandidateStart = markerStart - 1
            while leftCandidateStart > 0 {
                let gap = text[
                    words[leftCandidateStart - 1].range
                        .upperBound..<words[leftCandidateStart].range.lowerBound]
                if containsStrongSentenceBoundary(gap) { break }
                leftCandidateStart -= 1
            }

            var rightEnd = rightStart + 1
            while rightEnd < words.count {
                let gap = text[
                    words[rightEnd - 1].range.upperBound..<words[rightEnd].range.lowerBound]
                if containsStrongSentenceBoundary(gap) { break }
                rightEnd += 1
            }

            var bestStart: Int?
            var bestSharedStemLength = 0
            for proposedStart in leftCandidateStart..<markerStart {
                var shared = 0
                while proposedStart + shared < markerStart,
                    rightStart + shared < rightEnd,
                    words[proposedStart + shared].comparisonKey
                        == words[rightStart + shared].comparisonKey
                {
                    shared += 1
                }

                // Both versions need a meaningful shared stem and at least one
                // changed word. This rejects terse or ambiguous corrections.
                guard shared >= 2,
                    proposedStart + shared < markerStart,
                    rightStart + shared < rightEnd
                else { continue }
                let comparedWords =
                    words[proposedStart..<markerStart] + words[rightStart..<rightEnd]
                guard !comparedWords.contains(where: \.isAllCapsIdentifier) else { continue }

                if shared > bestSharedStemLength {
                    bestStart = proposedStart
                    bestSharedStemLength = shared
                }
            }

            if let bestStart {
                return words[bestStart].range.lowerBound..<words[rightStart].range.lowerBound
            }
        }
        return nil
    }

    private func hasOnlyHorizontalWhitespace(
        betweenWords range: Range<Int>,
        words: [SpeechWord],
        in text: String
    ) -> Bool {
        guard range.count > 1 else { return true }
        for index in range.lowerBound..<(range.upperBound - 1) {
            let gap = text[words[index].range.upperBound..<words[index + 1].range.lowerBound]
            if !hasOnlyHorizontalWhitespace(gap) { return false }
        }
        return true
    }

    private func hasOnlyHorizontalWhitespace(_ text: Substring) -> Bool {
        !text.isEmpty
            && !text.contains("\n")
            && !text.contains("\r")
            && text.allSatisfy(\.isWhitespace)
    }

    private func isWeakRepeatBoundary(_ text: Substring) -> Bool {
        var hasWhitespace = false
        for character in text {
            if character.isWhitespace {
                guard character != "\n", character != "\r" else { return false }
                hasWhitespace = true
            } else if !",-–—".contains(character) {
                return false
            }
        }
        return hasWhitespace
    }

    private func containsStrongSentenceBoundary(_ text: Substring) -> Bool {
        text.contains { ".!?;:…\n\r".contains($0) }
    }

    func correctCommonErrors(in text: String) -> String {
        let words = Self.commonCorrections.keys
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        guard
            let regex = try? NSRegularExpression(
                pattern: #"\b("# + words + #")\b"#,
                options: [.caseInsensitive]
            )
        else {
            return text
        }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let original = String(result[range])
            // All-caps tokens are commonly identifiers or units. Do not turn
            // "IM" into "I'M" or "WONT" into prose.
            if original.count > 1, original == original.uppercased() { continue }
            guard let corrected = Self.commonCorrections[original.lowercased()] else { continue }
            result.replaceSubrange(range, with: correction(corrected, matchingCaseOf: original))
        }
        return result
    }

    private func correction(_ corrected: String, matchingCaseOf original: String) -> String {
        if original.first?.isUppercase == true, corrected != "I" {
            return corrected.prefix(1).uppercased() + corrected.dropFirst()
        }
        return corrected
    }

    func normalizeWhitespace(_ text: String) -> String {
        var result = text
        // Collapse horizontal whitespace (including non-breaking spaces) but
        // preserve newlines and paragraph breaks.
        if let regex = try? NSRegularExpression(pattern: #"(?:[\p{Zs}\t])+"#) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }
        for (pattern, replacement) in [
            (" +([,.;:!?%\\])…])", "$1"),  // no space before closing punctuation
            ("([\\[(]) +", "$1"),  // no space after opening delimiters
            ("([,;:!?])(?=[\\p{L}])", "$1 "),  // add a missing separator after punctuation
            ("([,;:])(?:\\s*[,;:])+", "$1"),  // collapse separators stranded by removed fillers
            ("^[,;:]+\\s*", ""),  // remove a leading separator stranded by a filler
            ("\\n +", "\n"),  // no leading spaces on new lines
            (" +\\n", "\n"),  // no trailing spaces before newlines
            ("\\n{3,}", "\n\n"),  // max one blank line
        ] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func capitalizeSentences(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var capitalizeNext = true
        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(Character(character.uppercased()))
                capitalizeNext = false
            } else {
                result.append(character)
                if character.isLetter || character.isNumber { capitalizeNext = false }
            }
            if ".!?".contains(character) || character == "\n" {
                capitalizeNext = true
            }
        }
        return result
    }

    func ensureTerminalPunctuation(_ text: String) -> String {
        guard let last = text.last else { return text }
        if ".!?…".contains(last) { return text }
        if ",;:".contains(last) {
            return text.dropLast().trimmingCharacters(in: .whitespaces) + "."
        }
        if "\"”".contains(last) {
            let body = text.dropLast()
            guard let bodyLast = body.last else { return text }
            if ".!?…".contains(bodyLast) { return text }
            if ",;:".contains(bodyLast) {
                return body.dropLast().trimmingCharacters(in: .whitespaces) + ".\(last)"
            }
            return body + ".\(last)"
        }
        if "')]".contains(last), text.dropLast().last.map({ ".!?…".contains($0) }) == true {
            return text
        }
        return text + "."
    }
}

/// Anything that turns a raw transcript into final text.
public protocol TextCleaning: Sendable {
    func clean(_ raw: String, profile: AppProfile) async throws -> String
}

public struct RulesCleaner: TextCleaning {
    private let cleaner: TranscriptCleaner
    private let codeProcessor = CodeDictationProcessor()

    public init(interpretSpokenPunctuation: Bool = true, removeFillers: Bool = true) {
        self.cleaner = TranscriptCleaner(
            interpretSpokenPunctuation: interpretSpokenPunctuation,
            removeFillers: removeFillers
        )
    }

    public func clean(_ raw: String, profile: AppProfile) async throws -> String {
        switch profile.formatting {
        case .raw:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        case .code:
            return codeProcessor.process(raw)
        case .light, .casual, .professional:
            // "professional"/"casual" gain the LLM tone pass when available; rules are the floor.
            return cleaner.clean(raw)
        }
    }
}
