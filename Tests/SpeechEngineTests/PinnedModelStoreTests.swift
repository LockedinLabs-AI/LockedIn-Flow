import Foundation
import XCTest

@testable import SpeechEngine

final class PinnedModelStoreTests: XCTestCase {
    private let trustedData = Data("trusted model".utf8)
    private let trustedHash = "6d6065cea517391b0166d6a74be33c924cc416b959fa1eee6a146094195b639d"

    func testReviewedCatalogIsCompleteAndUsesImmutableRevisions() throws {
        XCTAssertEqual(PinnedModelCatalog.all.count, 3)
        XCTAssertEqual(PinnedModelCatalog.all.flatMap(\.files).count, 39)
        XCTAssertEqual(
            PinnedModelCatalog.all.flatMap(\.files).reduce(Int64(0)) { $0 + $1.byteCount },
            1_098_248_944
        )

        for model in PinnedModelCatalog.all {
            XCTAssertNoThrow(try model.validate())
            XCTAssertEqual(model.revision.count, 40)
            XCTAssertNotEqual(model.revision, "main")
        }
    }

    func testProvisioningManifestMatchesCompiledCatalog() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repository =
            testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try String(
            contentsOf: repository.appendingPathComponent("security/model-artifacts.tsv"),
            encoding: .utf8
        )
        let actual = Set(manifest.split(separator: "\n").map(String.init))
        let expected = Set(
            PinnedModelCatalog.all.flatMap { model in
                model.files.map { artifact in
                    "\(artifact.sha256)\t\(artifact.byteCount)\t\(model.localFolderName)/\(artifact.path)"
                }
            }
        )

        XCTAssertEqual(actual.count, 39)
        XCTAssertEqual(actual, expected)

        let sources = try String(
            contentsOf: repository.appendingPathComponent("security/model-sources.tsv"),
            encoding: .utf8
        )
        let actualSources = Set(
            sources.split(separator: "\n")
                .map(String.init)
                .filter { !$0.hasPrefix("#") }
        )
        let expectedSources = Set(
            PinnedModelCatalog.all.map { model in
                let selection =
                    model.id == PinnedModelCatalog.parakeetUnified.id
                    ? "optional" : "default"
                return
                    "\(model.localFolderName)\t\(model.repository)\t\(model.revision)\t\(selection)"
            }
        )
        XCTAssertEqual(actualSources, expectedSources)
    }

    func testManifestRejectsTraversalAndMutableRevision() {
        let invalid = PinnedModelDefinition(
            id: "test-model",
            repository: "LockedInLabs/test-model",
            revision: "main",
            localFolderName: "test-model",
            files: [
                PinnedModelArtifact(
                    path: "../model.bin",
                    byteCount: Int64(trustedData.count),
                    sha256: trustedHash
                )
            ]
        )

        XCTAssertThrowsError(try invalid.validate())
    }

    func testPrepareLoadsOnlyAnAlreadyProvisionedVerifiedModel() async throws {
        let root = try makeTemporaryRoot()
        let directory = try provisionTestModel(under: root)
        let store = PinnedModelStore(rootDirectory: root)

        let prepared = try await store.prepare(testModel())

        XCTAssertEqual(prepared, directory)
        XCTAssertEqual(
            try Data(contentsOf: prepared.appendingPathComponent("model.bin")), trustedData)
    }

    func testMissingModelFailsWithProvisioningGuidanceAndDoesNotCreateFiles() async throws {
        let root = try makeTemporaryRoot()
        let store = PinnedModelStore(rootDirectory: root)

        do {
            _ = try await store.prepare(testModel())
            XCTFail("Expected a provisioning error")
        } catch let error as PinnedModelStoreError {
            guard case .notProvisioned(let modelID, let expectedDirectories) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(modelID, "test-model")
            XCTAssertEqual(
                expectedDirectories.first?.standardizedFileURL.path,
                root.appendingPathComponent("test-model").standardizedFileURL.path
            )
            XCTAssertTrue(error.localizedDescription.contains("offline model bundle"))
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testHashMismatchIsRejectedWithoutModifyingProvisionedCache() async throws {
        let root = try makeTemporaryRoot()
        let activeDirectory = root.appendingPathComponent("test-model", isDirectory: true)
        try FileManager.default.createDirectory(
            at: activeDirectory,
            withIntermediateDirectories: true
        )
        let activeFile = activeDirectory.appendingPathComponent("model.bin")
        let existing = Data("existing invalid cache".utf8)
        try existing.write(to: activeFile)
        let store = PinnedModelStore(rootDirectory: root)

        do {
            _ = try await store.prepare(testModel())
            XCTFail("Expected integrity failure")
        } catch let error as PinnedModelStoreError {
            guard case .integrityFailed(let modelID, let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(modelID, "test-model")
            XCTAssertEqual(path, "model.bin")
        }

        XCTAssertEqual(try Data(contentsOf: activeFile), existing)
    }

    func testConcurrentPreparationReturnsTheSameVerifiedDirectory() async throws {
        let root = try makeTemporaryRoot()
        let directory = try provisionTestModel(under: root)
        let store = PinnedModelStore(rootDirectory: root)
        let model = testModel()

        async let first = store.prepare(model)
        async let second = store.prepare(model)
        let prepared = try await (first, second)

        XCTAssertEqual(prepared.0, directory)
        XCTAssertEqual(prepared.1, directory)
    }

    func testEarlierUserSearchRootIsPreferredAndLaterRootIsFallback() async throws {
        let firstRoot = try makeTemporaryRoot()
        let laterRoot = try makeTemporaryRoot()
        let laterDirectory = try provisionTestModel(under: laterRoot)
        let store = PinnedModelStore(userRootDirectories: [firstRoot, laterRoot])

        let preparedLaterDirectory = try await store.prepare(testModel())
        XCTAssertEqual(preparedLaterDirectory, laterDirectory)

        let firstRootWithModel = try makeTemporaryRoot()
        let secondRoot = try makeTemporaryRoot()
        let firstDirectory = try provisionTestModel(under: firstRootWithModel)
        _ = try provisionTestModel(under: secondRoot)
        let firstPreferredStore = PinnedModelStore(
            userRootDirectories: [firstRootWithModel, secondRoot]
        )

        let preparedFirstDirectory = try await firstPreferredStore.prepare(testModel())
        XCTAssertEqual(preparedFirstDirectory, firstDirectory)
    }

    func testInvalidEarlierSearchRootFailsClosedInsteadOfFallingBack() async throws {
        let firstRoot = try makeTemporaryRoot()
        let laterRoot = try makeTemporaryRoot()
        let firstDirectory = firstRoot.appendingPathComponent(
            "test-model",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: firstDirectory,
            withIntermediateDirectories: true
        )
        try Data("tampered managed model".utf8).write(
            to: firstDirectory.appendingPathComponent("model.bin")
        )
        let laterDirectory = try provisionTestModel(under: laterRoot)
        let store = PinnedModelStore(userRootDirectories: [firstRoot, laterRoot])

        do {
            _ = try await store.prepare(testModel())
            XCTFail("An invalid earlier model must not be bypassed by a later model")
        } catch let error as PinnedModelStoreError {
            guard case .integrityFailed(let modelID, let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(modelID, "test-model")
            XCTAssertEqual(path, "model.bin")
        }

        XCTAssertEqual(
            try Data(contentsOf: laterDirectory.appendingPathComponent("model.bin")),
            trustedData
        )
    }

    func testMissingSystemManagedRootFallsBackToUserEvaluationRoot() async throws {
        let parent = try makeTemporaryRoot()
        let missingManagedRoot = parent.appendingPathComponent(
            "missing-managed/Models",
            isDirectory: true
        )
        let userRoot = try makeTemporaryRoot()
        let userDirectory = try provisionTestModel(under: userRoot)
        let store = PinnedModelStore(
            managedRootDirectory: missingManagedRoot,
            userRootDirectory: userRoot
        )

        let prepared = try await store.prepare(testModel())

        XCTAssertEqual(prepared, userDirectory)
    }

    func testUserOwnedSystemManagedRootFailsClosedBeforeUserFallback() async throws {
        let managedRoot = try makeTemporaryRoot()
        _ = try provisionTestModel(under: managedRoot)
        let userRoot = try makeTemporaryRoot()
        let userDirectory = try provisionTestModel(under: userRoot)
        let store = PinnedModelStore(
            managedRootDirectory: managedRoot,
            userRootDirectory: userRoot
        )

        do {
            _ = try await store.prepare(testModel())
            XCTFail("A user-owned managed root must not be bypassed by a user model")
        } catch let error as PinnedModelStoreError {
            guard case .unsafeManagedStorage(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertFalse(path.isEmpty)
            XCTAssertTrue(error.localizedDescription.contains("root:wheel"))
        }

        XCTAssertEqual(
            try Data(contentsOf: userDirectory.appendingPathComponent("model.bin")),
            trustedData
        )
    }

    func testManagedACLInspectorRejectsRealExtendedACLEntries() throws {
        let root = try makeTemporaryRoot()
        let artifact = root.appendingPathComponent("model.bin")
        try trustedData.write(to: artifact)

        XCTAssertNoThrow(try PinnedModelStore.verifyNoExtendedACLEntries(at: root))
        XCTAssertThrowsError(
            try PinnedModelStore.verifyNoExtendedACLEntries(
                at: root.appendingPathComponent("missing")
            )
        )
        try changeACL("+a", entry: "everyone allow write", at: root)
        defer { try? changeACL("-N", at: root) }

        XCTAssertThrowsError(try PinnedModelStore.verifyNoExtendedACLEntries(at: root)) {
            guard case PinnedModelStoreError.unsafeManagedStorage(let path) = $0 else {
                return XCTFail("Unexpected error: \($0)")
            }
            XCTAssertEqual(path, root.path)
        }

        try changeACL("+a", entry: "everyone allow write", at: artifact)
        defer { try? changeACL("-N", at: artifact) }
        XCTAssertThrowsError(try PinnedModelStore.verifyNoExtendedACLEntries(at: artifact))
    }

    func testUserEvaluationRootIgnoresExtendedACLEntries() async throws {
        let root = try makeTemporaryRoot()
        let directory = try provisionTestModel(under: root)
        let artifact = directory.appendingPathComponent("model.bin")
        try changeACL("+a", entry: "everyone allow write", at: directory)
        try changeACL("+a", entry: "everyone allow write", at: artifact)
        defer {
            try? changeACL("-N", at: artifact)
            try? changeACL("-N", at: directory)
        }

        let store = PinnedModelStore(rootDirectory: root)
        let prepared = try await store.prepare(testModel())

        XCTAssertEqual(prepared, directory)
    }

    func testUnexpectedFileDirectoryAndSymlinkAreRejectedWithoutMutation() async throws {
        for contaminant in ["file", "directory", "symlink"] {
            let root = try makeTemporaryRoot()
            let active = root.appendingPathComponent("test-model", isDirectory: true)
            try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
            try trustedData.write(to: active.appendingPathComponent("model.bin"))
            switch contaminant {
            case "file":
                try Data("unexpected".utf8).write(
                    to: active.appendingPathComponent("unexpected.bin"))
            case "directory":
                try FileManager.default.createDirectory(
                    at: active.appendingPathComponent("unexpected", isDirectory: true),
                    withIntermediateDirectories: false
                )
            default:
                try FileManager.default.createSymbolicLink(
                    at: active.appendingPathComponent("unexpected-link"),
                    withDestinationURL: active.appendingPathComponent("model.bin")
                )
            }

            let originalNames = try FileManager.default.contentsOfDirectory(atPath: active.path)
                .sorted()
            let store = PinnedModelStore(rootDirectory: root)
            do {
                _ = try await store.prepare(testModel())
                XCTFail("Expected unexpected-content failure for \(contaminant)")
            } catch let error as PinnedModelStoreError {
                guard case .unexpectedContents = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: active.path).sorted(),
                originalNames
            )
        }
    }

    func testConflictingDefinitionsForOneCacheFolderAreRejected() async throws {
        let root = try makeTemporaryRoot()
        _ = try provisionTestModel(under: root)
        let store = PinnedModelStore(rootDirectory: root)
        let first = testModel()
        let conflicting = PinnedModelDefinition(
            id: "different-model",
            repository: first.repository,
            revision: String(repeating: "b", count: 40),
            localFolderName: first.localFolderName,
            files: first.files
        )

        _ = try await store.prepare(first)
        do {
            _ = try await store.prepare(conflicting)
            XCTFail("Expected conflicting manifest rejection")
        } catch let error as PinnedModelStoreError {
            guard case .invalidManifest(let reason) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("conflicting definitions"))
        }
    }

    private func testModel() -> PinnedModelDefinition {
        PinnedModelDefinition(
            id: "test-model",
            repository: "LockedInLabs/test-model",
            revision: String(repeating: "a", count: 40),
            localFolderName: "test-model",
            files: [
                PinnedModelArtifact(
                    path: "model.bin",
                    byteCount: Int64(trustedData.count),
                    sha256: trustedHash
                )
            ]
        )
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "lockedin-pinned-model-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func changeACL(_ operation: String, entry: String? = nil, at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = [operation] + (entry.map { [$0] } ?? []) + [url.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message =
                String(
                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? "unknown chmod error"
            throw NSError(
                domain: "PinnedModelStoreTests.ACL",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    @discardableResult
    private func provisionTestModel(under root: URL) throws -> URL {
        let directory = root.appendingPathComponent("test-model", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try trustedData.write(to: directory.appendingPathComponent("model.bin"))
        return directory
    }
}
