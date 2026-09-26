import Foundation
import VoiceCore

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Optional output translation: transcribe in the speaker's language, then
/// translate locally (Apple FoundationModels) before insertion.
/// Off by default — dictation behavior is unchanged unless the user opts in.
public struct LLMTranslator: Sendable {
    public enum TargetLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
        case off
        case english
        case spanish
        case french
        case german
        case portuguese
        case hindi
        case arabic
        case chinese

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .off: return "Off"
            case .english: return "English"
            case .spanish: return "Spanish (Español)"
            case .french: return "French (Français)"
            case .german: return "German (Deutsch)"
            case .portuguese: return "Portuguese (Português)"
            case .hindi: return "Hindi (हिन्दी)"
            case .arabic: return "Arabic (العربية)"
            case .chinese: return "Chinese (中文)"
            }
        }
    }

    public init() {}

    public static var isAvailable: Bool {
        LLMCleaner.isLLMAvailable
    }

    /// Translates text to the target language. If the text is already in the
    /// target language, it is returned unchanged (the model is instructed to
    /// pass it through, preserving the original wording).
    public func translate(_ text: String, to language: TargetLanguage) async throws -> String {
        guard language != .off else { return text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), LLMCleaner.isLLMAvailable {
                let languageName =
                    language.displayName.components(separatedBy: " ").first ?? "English"
                let instructions = """
                    You are a translation engine inside a privacy-first dictation app.
                    Rules you must follow absolutely:
                    - Translate the user's text into \(languageName).
                    - If the text is already in \(languageName), return it unchanged.
                    - Preserve meaning, names, numbers, and formatting exactly.
                    - NEVER add content, commentary, explanations, or quotes.
                    - Return ONLY the \(languageName) text.
                    """
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: text)
                let translated = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return translated.isEmpty ? text : translated
            }
        #endif
        // No local LLM available — return the original rather than failing the dictation.
        return text
    }
}
