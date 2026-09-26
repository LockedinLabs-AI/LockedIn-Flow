import Foundation

/// High-level states of the dictation pipeline, surfaced in the menu bar and overlay.
public enum PipelineState: String, Sendable, Equatable {
    case idle
    case preparing  // verify and load a provisioned model
    case ready
    case recording
    case transcribing
    case processing  // cleanup / formatting
    case inserting
    case done
    case failed
}

public enum FormattingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case raw
    case light
    case casual
    case professional
    case code

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .raw: return "Raw transcript"
        case .light: return "Light cleanup"
        case .casual: return "Casual"
        case .professional: return "Professional"
        case .code: return "Code"
        }
    }
}

public struct VocabularyRule: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var spoken: String
    public var written: String
    public var caseSensitive: Bool
    /// `nil` means the rule is global. A non-empty list limits the rule to
    /// explicit profiles so context-specific terms do not rewrite unrelated
    /// dictation.
    public var profileIDs: [String]?
    /// Optional stable origin for reversible, first-party starter packs.
    /// User-created and legacy rules remain `nil`.
    public var sourceID: String?

    public init(
        id: UUID = UUID(),
        spoken: String,
        written: String,
        caseSensitive: Bool = false,
        profileIDs: [String]? = nil,
        sourceID: String? = nil
    ) {
        self.id = id
        self.spoken = spoken
        self.written = written
        self.caseSensitive = caseSensitive
        self.profileIDs = profileIDs
        self.sourceID = sourceID
    }
}

/// Behavior profile selected by the foreground application.
public struct AppProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var bundleIdentifiers: [String]
    public var formatting: FormattingMode
    public var cleanupEnabled: Bool
    public var vocabulary: [VocabularyRule]

    public init(
        id: String,
        name: String,
        bundleIdentifiers: [String],
        formatting: FormattingMode,
        cleanupEnabled: Bool = true,
        vocabulary: [VocabularyRule] = []
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.formatting = formatting
        self.cleanupEnabled = cleanupEnabled
        self.vocabulary = vocabulary
    }

    public static let general = AppProfile(
        id: "general", name: "General", bundleIdentifiers: [], formatting: .light
    )

    public static let email = AppProfile(
        id: "email", name: "Email",
        bundleIdentifiers: ["com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail"],
        formatting: .professional
    )

    public static let coding = AppProfile(
        id: "coding", name: "Coding",
        bundleIdentifiers: [
            "com.microsoft.VSCode", "com.apple.dt.Xcode", "dev.zed.Zed",
            "com.todesktop.230313mzl4w4u92", "com.apple.Terminal", "com.googlecode.iterm2",
            "com.jetbrains.intellij", "com.sublimetext.4",
        ],
        formatting: .code
    )

    /// Chat and messaging apps use a conversational tone while email remains
    /// professional.
    public static let chat = AppProfile(
        id: "chat", name: "Chat",
        bundleIdentifiers: [
            "com.tinyspeck.slackmacgap", "com.microsoft.teams", "com.microsoft.teams2",
            "com.hnc.Discord", "com.apple.MobileSMS", "org.whispersystems.signal-desktop",
            "us.zoom.xos", "com.facebook.archon", "net.whatsapp.WhatsApp",
        ],
        formatting: .casual
    )

    public static let builtIn: [AppProfile] = [.general, .email, .chat, .coding]

    public static func profile(forBundleID bundleID: String?) -> AppProfile {
        guard let bundleID else { return .general }
        return builtIn.first { $0.bundleIdentifiers.contains(bundleID) } ?? .general
    }
}

public struct Transcript: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var raw: String
    public var final: String
    public var audioDuration: TimeInterval
    public var modelID: String
    public var profileID: String
    public var targetAppBundleID: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        raw: String,
        final: String,
        audioDuration: TimeInterval,
        modelID: String,
        profileID: String,
        targetAppBundleID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.raw = raw
        self.final = final
        self.audioDuration = audioDuration
        self.modelID = modelID
        self.profileID = profileID
        self.targetAppBundleID = targetAppBundleID
    }
}

public enum RetentionPolicy: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case sessionOnly
    case oneHour
    case oneDay
    case sevenDays
    case thirtyDays
    case forever

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Do not retain"
        case .sessionOnly: return "Until app quits"
        case .oneHour: return "One hour"
        case .oneDay: return "One day"
        case .sevenDays: return "Seven days"
        case .thirtyDays: return "Thirty days"
        case .forever: return "Keep indefinitely"
        }
    }

    /// Cutoff date before which entries should be purged. `nil` means keep everything.
    public func cutoff(now: Date = Date()) -> Date? {
        switch self {
        case .off, .sessionOnly, .forever: return nil
        case .oneHour: return now.addingTimeInterval(-3600)
        case .oneDay: return now.addingTimeInterval(-86_400)
        case .sevenDays: return now.addingTimeInterval(-604_800)
        case .thirtyDays: return now.addingTimeInterval(-2_592_000)
        }
    }

    public var persistsAcrossLaunches: Bool {
        switch self {
        case .off, .sessionOnly: return false
        default: return true
        }
    }
}
