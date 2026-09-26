import Foundation

enum AppBuildIdentity {
    static let supportDirectoryName = "LockedInFlowCommunity"
    static let keychainService = "ai.lockedin.flow.community"
    static let logSubsystem = "ai.lockedin.flow.community"
}

enum AppRuntime {
    static let isRunningTests: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()

    static let userDefaults: UserDefaults = {
        guard isRunningTests else { return .standard }
        let suiteName = "ai.lockedin.flow.tests.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }()
}

public enum AppPaths {
    public static let supportDirectory: URL = {
        let dir: URL
        if AppRuntime.isRunningTests {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "LockedInFlowTests-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            dir = base.appendingPathComponent(
                AppBuildIdentity.supportDirectoryName,
                isDirectory: true
            )
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    public static var historyFile: URL { supportDirectory.appendingPathComponent("history.enc") }
    public static var recoveryFile: URL { supportDirectory.appendingPathComponent("recovery.enc") }
    public static var vocabularyFile: URL {
        supportDirectory.appendingPathComponent("vocabulary.enc")
    }
    public static var fluidAudioDirectory: URL {
        supportDirectory.appendingPathComponent("FluidAudio", isDirectory: true)
    }
    public static var speechModelsDirectory: URL {
        fluidAudioDirectory.appendingPathComponent("Models", isDirectory: true)
    }
    /// Root-owned model packages may provision this fixed location through MDM.
    /// The application never creates or modifies it.
    public static let managedSpeechModelsDirectory = URL(
        fileURLWithPath: "/Library/Application Support/LockedIn Flow/Models",
        isDirectory: true
    )
    public static var speechModelSearchDirectories: [URL] {
        [managedSpeechModelsDirectory, speechModelsDirectory]
    }
    public static var diagnosticsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
