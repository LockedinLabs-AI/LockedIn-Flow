import Foundation
import VoiceCore

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Turns a meeting transcript into a structured note (title, summary, key
/// points, action items) using the on-device language model.
/// Guardrails: never invent content; a too-short transcript is an honest error,
/// not a fabricated summary.
public struct MeetingSummarizer: Sendable {
    public enum SummarizerError: Error, LocalizedError {
        case transcriptTooShort
        case llmUnavailable
        case malformedOutput

        public var errorDescription: String? {
            switch self {
            case .transcriptTooShort:
                return "The meeting was too short to summarize — try at least 30 seconds."
            case .llmUnavailable: return "Meeting summaries need the on-device model (macOS 26+)."
            case .malformedOutput:
                return "The summary came back malformed — the raw transcript is saved."
            }
        }
    }

    public init() {}

    public var isAvailable: Bool { LLMCleaner.isLLMAvailable }

    public func summarize(transcript: String, durationSeconds: TimeInterval) async throws
        -> MeetingNote
    {
        let words = transcript.split(separator: " ").count
        guard words >= 40 else { throw SummarizerError.transcriptTooShort }

        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), isAvailable {
                let instructions = """
                    You are a meeting-notes engine inside a privacy-first app.
                    Rules you must follow absolutely:
                    - Produce notes ONLY from the transcript provided. Never invent facts, names, decisions, or action items.
                    - If something is unclear, leave it out.
                    - Respond in EXACTLY this format, nothing else:
                    TITLE: <short neutral title>
                    SUMMARY: <2-4 sentences>
                    POINTS:
                    - <key point 1>
                    - <key point 2>
                    ACTIONS:
                    - <action item 1, or NONE if there are no clear owners/tasks>
                    """
                let session = LanguageModelSession(instructions: instructions)
                let minutes = Int((durationSeconds / 60).rounded())
                let response = try await session.respond(
                    to: "Transcript (\(minutes) min):\n\n\(transcript)")
                guard let note = MeetingSummarizer.parse(response.content) else {
                    throw SummarizerError.malformedOutput
                }
                return note
            }
        #endif
        throw SummarizerError.llmUnavailable
    }

    /// Parses the strict TITLE/SUMMARY/POINTS/ACTIONS format. Returns nil on malformed output.
    static func parse(_ text: String) -> MeetingNote? {
        var title = ""
        var summary = ""
        var points: [String] = []
        var actions: [String] = []
        var section = ""

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("TITLE:") {
                title = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                section = "title"
            } else if trimmed.hasPrefix("SUMMARY:") {
                summary = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                section = "summary"
            } else if trimmed.hasPrefix("POINTS:") {
                section = "points"
            } else if trimmed.hasPrefix("ACTIONS:") {
                section = "actions"
            } else if trimmed.hasPrefix("-") {
                let item = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                guard !item.isEmpty else { continue }
                if section == "points" { points.append(item) }
                if section == "actions", item.uppercased() != "NONE" { actions.append(item) }
            } else if section == "summary", !trimmed.isEmpty {
                summary += (summary.isEmpty ? "" : " ") + trimmed
            }
        }

        guard !title.isEmpty, !summary.isEmpty else { return nil }
        return MeetingNote(title: title, summary: summary, keyPoints: points, actionItems: actions)
    }
}
