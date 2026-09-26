import Foundation

public struct Snippet: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var trigger: String
    public var expansion: String

    public init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}

/// Spoken-phrase → canned text. A snippet fires only when the ENTIRE cleaned
/// utterance matches its trigger — inline words are never expanded mid-sentence,
/// which keeps expansion predictable and safe.
public struct SnippetLibrary: Codable, Sendable, Equatable {
    public var snippets: [Snippet]

    public init(snippets: [Snippet] = []) {
        self.snippets = snippets
    }

    public func expansion(for utterance: String) -> String? {
        let normalized =
            utterance
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))
        guard !normalized.isEmpty else { return nil }
        return snippets.first {
            $0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }?.expansion
    }
}

public enum SnippetStore {
    private static var file: URL {
        AppPaths.supportDirectory.appendingPathComponent("snippets.enc")
    }

    public static func load() -> SnippetLibrary {
        do {
            guard let data = try SecureStore.readEncrypted(from: file) else {
                return SnippetLibrary()
            }
            return try JSONDecoder().decode(SnippetLibrary.self, from: data)
        } catch {
            FlowLog.error("snippets load failed code=\(errorCode: error)")
            return SnippetLibrary()
        }
    }

    public static func save(_ library: SnippetLibrary) {
        do {
            let data = try JSONEncoder().encode(library)
            try SecureStore.writeEncrypted(data, to: file)
        } catch {
            FlowLog.error("snippets persist failed code=\(errorCode: error)")
        }
    }
}
