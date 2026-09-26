import XCTest
@testable import VoiceCore

final class CommunityBuildIdentityTests: XCTestCase {
    func testCommunityBuildUsesIsolatedRuntimeIdentity() {
        XCTAssertEqual(AppBuildIdentity.supportDirectoryName, "LockedInFlowCommunity")
        XCTAssertEqual(AppBuildIdentity.keychainService, "ai.lockedin.flow.community")
        XCTAssertEqual(AppBuildIdentity.logSubsystem, "ai.lockedin.flow.community")
    }

    func testPersistentEncryptionFailsClosedWithoutAnEphemeralProductionKey() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repository =
            testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent("Sources/VoiceCore/SecureStore.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("ephemeralKey"))
        XCTAssertTrue(source.contains("interactionNotAllowed = true"))
        XCTAssertTrue(source.contains("kSecUseAuthenticationContext"))
        XCTAssertTrue(source.contains("return try createKey()"))
    }
}
