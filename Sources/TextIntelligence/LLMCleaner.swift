import Foundation
import VoiceCore

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Local LLM transcript cleanup. Provider order:
/// 1. Apple FoundationModels (macOS 26+, on-device Apple Intelligence — zero download)
/// 2. Rules cleanup (always available)
///
/// Hard guardrails: the LLM may only fix form, never content. Short utterances skip
/// the LLM entirely for speed. Any failure or implausible output falls back to rules.
public struct LLMCleaner: TextCleaning {
    /// One- and two-word utterances are already handled well by deterministic
    /// rules. Longer prose gets the contextual pass when Apple Intelligence is
    /// available so grammar and spelling are not limited to long dictations.
    public static let shortUtteranceWordLimit = 2

    private let rules: RulesCleaner
    /// The user's personal vocabulary (written forms) — biases cleanup toward their
    /// real terminology even when ASR mis-hears it ("kimik" → "Kimi K3").
    private let vocabularyHints: [String]

    public init(interpretSpokenPunctuation: Bool = true, vocabularyHints: [String] = []) {
        self.rules = RulesCleaner(interpretSpokenPunctuation: interpretSpokenPunctuation)
        self.vocabularyHints = Array(vocabularyHints.prefix(40))
    }

    public static var isLLMAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    public static var availabilityDescription: String {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                switch SystemLanguageModel.default.availability {
                case .available:
                    return "Apple Intelligence (on-device)"
                case .unavailable(.deviceNotEligible):
                    return "Unavailable: device not eligible"
                case .unavailable(.appleIntelligenceNotEnabled):
                    return "Unavailable: Apple Intelligence is off"
                case .unavailable(.modelNotReady):
                    return "Unavailable: model not ready"
                case .unavailable:
                    return "Unavailable"
                }
            }
        #endif
        return "Rules cleanup only"
    }

    public func clean(_ raw: String, profile: AppProfile) async throws -> String {
        let rulesOutput = try await rules.clean(raw, profile: profile)

        let wordCount = raw.split(separator: " ").count
        guard wordCount > Self.shortUtteranceWordLimit else { return rulesOutput }
        guard profile.formatting != .raw, profile.formatting != .code else { return rulesOutput }

        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), Self.isLLMAvailable {
                do {
                    // Give the model the deterministic result instead of the raw
                    // transcript. Fillers and spoken punctuation are already resolved,
                    // leaving the contextual pass focused on grammar and formatting.
                    let llmOutput = try await llmClean(rulesOutput, profile: profile)
                    if passesSanityCheck(input: rulesOutput, output: llmOutput) {
                        return llmOutput
                    }
                    FlowLog.error("llm cleanup failed sanity check — using rules output")
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    FlowLog.error(
                        "llm cleanup failed — using rules output code=\(errorCode: error)")
                }
            }
        #endif
        return rulesOutput
    }

    #if canImport(FoundationModels)
        @available(macOS 26.0, *)
        private func llmClean(_ raw: String, profile: AppProfile) async throws -> String {
            let toneInstruction: String
            switch profile.formatting {
            case .professional:
                toneInstruction =
                    "Use clear, professional phrasing suitable for \(profile.name.lowercased()) contexts."
            case .casual:
                toneInstruction =
                    "Keep it conversational and natural — contractions are fine, short sentences, no stiff formality."
            default:
                toneInstruction = "Keep the tone natural."
            }
            let vocabularyInstruction =
                vocabularyHints.isEmpty
                ? ""
                : "\n        - The user's personal vocabulary — always use these exact spellings when you hear something similar: \(vocabularyHints.joined(separator: ", "))."
            let instructions = """
                You are a transcript cleanup engine inside a privacy-first dictation app.
                Rules you must follow absolutely:
                - Fix spelling, punctuation, capitalization, obvious grammar errors and formatting.
                - Remove residual verbal fillers, stutters, and abandoned false starts only when the intended sentence remains unambiguous.
                - Break prose into readable sentences and paragraphs when the spoken structure clearly supports it.
                - Correct contextually obvious homophones, but preserve names, product terms, numbers, and technical identifiers unless the supplied vocabulary resolves them.
                - NEVER add facts, names, numbers, or claims that were not spoken.
                - NEVER remove meaning or change intent. Preserve the speaker's voice.
                - \(toneInstruction)\(vocabularyInstruction)
                - Return ONLY the cleaned text. No commentary, no preamble, no quotes.
                """
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: raw)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    #endif

    /// Reject LLM output that is empty or implausibly divergent in size.
    func passesSanityCheck(input: String, output: String) -> Bool {
        guard !output.isEmpty else { return false }
        guard output.count >= input.count / 4 else { return false }
        guard output.count <= max(input.count * 3, input.count + 200) else { return false }
        guard protectedAnchors(in: input) == protectedAnchors(in: output) else { return false }

        let inputTokens = lexicalTokens(in: input)
        let outputTokens = lexicalTokens(in: output)
        guard !inputTokens.isEmpty, !outputTokens.isEmpty else { return false }
        guard inputTokens.first == outputTokens.first else { return false }
        guard
            isOrderedSubsequence(
                sentenceInitialTokens(in: input),
                of: outputTokens
            )
        else { return false }

        let overlap = longestCommonSubsequenceLength(inputTokens, outputTokens)
        let inputCoverage = Double(overlap) / Double(inputTokens.count)
        let outputCoverage = Double(overlap) / Double(outputTokens.count)
        guard inputCoverage >= 0.60, outputCoverage >= 0.60 else { return false }
        return true
    }

    /// Ordered overlap prevents a rewrite from passing merely because it
    /// contains the same bag of words in a meaning-changing order.
    private func longestCommonSubsequenceLength(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: rhs.count + 1)
        for left in lhs {
            var current = Array(repeating: 0, count: rhs.count + 1)
            for (index, right) in rhs.enumerated() {
                current[index + 1] =
                    left == right
                    ? previous[index] + 1
                    : max(previous[index + 1], current[index])
            }
            previous = current
        }
        return previous[rhs.count]
    }

    /// Sentence-opening words include proper names that ordinary capitalization
    /// cannot distinguish from prose. Requiring the input sequence to survive
    /// protects names such as "Sam" while still allowing the model to introduce
    /// additional sentence breaks for readability.
    private func sentenceInitialTokens(in text: String) -> [String] {
        text.split(whereSeparator: { ".!?\n".contains($0) }).compactMap {
            lexicalTokens(in: String($0)).first
        }
    }

    private func isOrderedSubsequence(_ required: [String], of available: [String]) -> Bool {
        guard !required.isEmpty else { return true }
        var requiredIndex = 0
        for token in available where token == required[requiredIndex] {
            requiredIndex += 1
            if requiredIndex == required.count { return true }
        }
        return false
    }

    private func lexicalTokens(in text: String) -> [String] {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)?"#
            )
        else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range, in: text) else { return nil }
            return text[range].lowercased()
        }
    }

    /// Names, numbers, acronyms, product-style casing, emails, URLs, and tokens
    /// containing digits must survive contextual cleanup exactly. This is a
    /// conservative guard against same-length hallucinations that a size check
    /// alone cannot detect.
    private func protectedAnchors(in text: String) -> [String] {
        let patterns = [
            #"https?://[^\s]+"#,
            #"[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}"#,
            #"(?<![\p{L}\p{N}_])(?:[$€£])?\d[\d,]*(?:\.\d+)?%?(?![\p{L}\p{N}_])"#,
            #"\b[A-Z]{2,}\b"#,
            #"\b[\p{L}_]*\d[\p{L}\p{N}_]*\b"#,
            #"\b[\p{L}]*[a-z][A-Z][\p{L}\p{N}]*\b"#,
        ]

        var anchors: [(location: Int, length: Int, value: String)] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                anchors.append((match.range.location, match.range.length, String(text[range])))
            }
        }

        // A title-cased token in the middle of a sentence is likely a proper
        // name. Sentence-initial capitalization from the rules pass is excluded.
        guard let wordRegex = try? NSRegularExpression(pattern: #"\b[\p{Lu}][\p{Ll}]+\b"#) else {
            return
                anchors
                .sorted(by: Self.anchorComesBefore)
                .map(\.value)
        }
        for match in wordRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let prefix = text[..<range.lowerBound]
            let previous = prefix.last(where: { !$0.isWhitespace })
            if let previous, !".!?\n".contains(previous) {
                anchors.append((match.range.location, match.range.length, String(text[range])))
            }
        }
        return
            anchors
            .sorted(by: Self.anchorComesBefore)
            .map(\.value)
    }

    private static func anchorComesBefore(
        _ lhs: (location: Int, length: Int, value: String),
        _ rhs: (location: Int, length: Int, value: String)
    ) -> Bool {
        if lhs.location != rhs.location { return lhs.location < rhs.location }
        if lhs.length != rhs.length { return lhs.length > rhs.length }
        return lhs.value < rhs.value
    }
}
