import Foundation

public enum SpokenCommand: String, Equatable, Sendable {
    case cancel
    case undoLast
    case deleteLastSentence
}

/// Matches *whole-utterance* control phrases only — a command is never triggered
/// by words appearing inside a longer dictation. That keeps false positives at zero.
public struct SpokenCommandParser: Sendable {
    public init() {}

    public func command(for utterance: String) -> SpokenCommand? {
        let trimmed =
            utterance
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))
        switch trimmed {
        case "cancel", "cancel that", "scratch that", "never mind", "nevermind":
            return .cancel
        case "undo", "undo that", "undo last", "undo last insertion":
            return .undoLast
        case "delete that", "delete last sentence", "delete the last sentence":
            return .deleteLastSentence
        default:
            return nil
        }
    }
}
