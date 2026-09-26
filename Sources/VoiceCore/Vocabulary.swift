import Foundation

/// Whole-word spoken→written replacement rules ("super base" → "Supabase").
public struct Vocabulary: Codable, Sendable, Equatable {
    public var rules: [VocabularyRule]

    private struct TrieNode {
        var children: [Character: Int] = [:]
        var ruleOrders: [Int] = []
    }

    private struct FoldedUnit {
        let value: Character
        let originalStart: String.Index
        let originalEnd: String.Index
    }

    private struct Candidate {
        let range: NSRange
        let replacement: String
        let profileScopeCount: Int?
        let ruleOrder: Int
    }

    public init(rules: [VocabularyRule] = []) {
        self.rules = rules
    }

    public func apply(to text: String) -> String {
        apply(to: text, profileID: nil)
    }

    /// Applies global rules plus rules explicitly scoped to the active profile.
    /// Passing `nil` intentionally applies global rules only.
    public func apply(to text: String, profileID: String?) -> String {
        guard !text.isEmpty, !rules.isEmpty else { return text }
        var trie = [TrieNode()]
        var hasApplicableRule = false
        for (ruleOrder, rule) in rules.enumerated() where ruleApplies(rule, to: profileID) {
            guard !rule.spoken.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let folded = Self.foldedCharacters(in: rule.spoken)
            guard !folded.isEmpty else { continue }
            hasApplicableRule = true
            var nodeIndex = 0
            for character in folded {
                if let child = trie[nodeIndex].children[character] {
                    nodeIndex = child
                } else {
                    let child = trie.count
                    trie.append(TrieNode())
                    trie[nodeIndex].children[character] = child
                    nodeIndex = child
                }
            }
            trie[nodeIndex].ruleOrders.append(ruleOrder)
        }
        guard hasApplicableRule else { return text }

        let units = Self.foldedUnits(in: text)
        var candidates: [Candidate] = []
        for start in units.indices {
            if start > units.startIndex,
                units[start - 1].originalStart == units[start].originalStart
            {
                continue
            }
            var nodeIndex = 0
            var cursor = start
            while cursor < units.endIndex,
                let child = trie[nodeIndex].children[units[cursor].value]
            {
                nodeIndex = child
                let finishesOriginalCharacter =
                    cursor + 1 == units.endIndex
                    || units[cursor + 1].originalStart != units[cursor].originalStart
                if finishesOriginalCharacter, !trie[nodeIndex].ruleOrders.isEmpty {
                    let stringRange =
                        units[start].originalStart..<units[cursor].originalEnd
                    if Self.hasTokenBoundaries(in: text, range: stringRange) {
                        for ruleOrder in trie[nodeIndex].ruleOrders {
                            let rule = rules[ruleOrder]
                            let options: String.CompareOptions =
                                rule.caseSensitive ? [] : [.caseInsensitive]
                            guard
                                text.compare(
                                    rule.spoken,
                                    options: options,
                                    range: stringRange,
                                    locale: Locale(identifier: "en_US_POSIX")
                                ) == .orderedSame
                            else { continue }
                            candidates.append(
                                Candidate(
                                    range: NSRange(stringRange, in: text),
                                    replacement: rule.written,
                                    profileScopeCount: rule.profileIDs.flatMap {
                                        $0.isEmpty ? nil : $0.count
                                    },
                                    ruleOrder: ruleOrder
                                )
                            )
                        }
                    }
                }
                cursor += 1
            }
        }

        candidates.sort {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            if $0.range.length != $1.range.length {
                return $0.range.length > $1.range.length
            }
            if $0.profileScopeCount != $1.profileScopeCount {
                switch ($0.profileScopeCount, $1.profileScopeCount) {
                case (.some(let left), .some(let right)): return left < right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): break
                }
            }
            return $0.ruleOrder < $1.ruleOrder
        }

        var selected: [Candidate] = []
        var consumedThrough = 0
        for candidate in candidates where candidate.range.location >= consumedThrough {
            selected.append(candidate)
            consumedThrough = NSMaxRange(candidate.range)
        }

        var result = text
        for candidate in selected.reversed() {
            guard let range = Range(candidate.range, in: result) else { continue }
            result.replaceSubrange(range, with: candidate.replacement)
        }
        return result
    }

    private static func foldedCharacters(in text: String) -> [Character] {
        let locale = Locale(identifier: "en_US_POSIX")
        return text.flatMap { character in
            String(character)
                .precomposedStringWithCanonicalMapping
                .folding(
                    options: [.caseInsensitive],
                    locale: locale
                )
        }
    }

    private static func foldedUnits(in text: String) -> [FoldedUnit] {
        var result: [FoldedUnit] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            for character in foldedCharacters(in: String(text[index])) {
                result.append(
                    FoldedUnit(
                        value: character,
                        originalStart: index,
                        originalEnd: next
                    )
                )
            }
            index = next
        }
        return result
    }

    private static func hasTokenBoundaries(
        in text: String,
        range: Range<String.Index>
    ) -> Bool {
        if range.lowerBound > text.startIndex {
            let previous = text.index(before: range.lowerBound)
            if isWordCharacter(text[previous]) { return false }
        }
        if range.upperBound < text.endIndex, isWordCharacter(text[range.upperBound]) {
            return false
        }
        return true
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            if scalar == "_" { return true }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                .modifierLetter, .otherLetter, .decimalNumber, .letterNumber,
                .otherNumber, .nonspacingMark, .spacingMark, .enclosingMark:
                return true
            default:
                return false
            }
        }
    }

    public func writtenHints(for profileID: String?) -> [String] {
        rules
            .filter { ruleApplies($0, to: profileID) }
            .map(\.written)
    }

    private func ruleApplies(_ rule: VocabularyRule, to profileID: String?) -> Bool {
        guard let profileIDs = rule.profileIDs, !profileIDs.isEmpty else { return true }
        guard let profileID else { return false }
        return profileIDs.contains(profileID)
    }
}
