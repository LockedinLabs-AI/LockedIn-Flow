import CryptoKit
import Darwin
import Foundation
import VoiceCore

struct PinnedModelArtifact: Equatable, Sendable {
    let path: String
    let byteCount: Int64
    let sha256: String
}

struct PinnedModelDefinition: Equatable, Sendable {
    let id: String
    let repository: String
    let revision: String
    let localFolderName: String
    let files: [PinnedModelArtifact]

    func validate() throws {
        let repositoryParts = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard repositoryParts.count == 2,
            repositoryParts.allSatisfy({ Self.isSafeIdentifier(String($0)) })
        else {
            throw PinnedModelStoreError.invalidManifest("invalid repository for \(id)")
        }
        guard revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            throw PinnedModelStoreError.invalidManifest("invalid revision for \(id)")
        }
        guard Self.isSafeIdentifier(id), Self.isSafeIdentifier(localFolderName), !files.isEmpty
        else {
            throw PinnedModelStoreError.invalidManifest("invalid model identity for \(id)")
        }

        var paths = Set<String>()
        for file in files {
            let parts = file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !file.path.hasPrefix("/"), !file.path.contains("\\"),
                parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                file.byteCount >= 0,
                file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                paths.insert(file.path).inserted
            else {
                throw PinnedModelStoreError.invalidManifest("invalid artifact in \(id)")
            }
        }
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
            && value != "."
            && value != ".."
    }
}

enum PinnedModelCatalog {
    static let parakeetTDT = PinnedModelDefinition(
        id: "parakeet-tdt-v3-int8",
        repository: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        revision: "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe",
        localFolderName: "parakeet-tdt-0.6b-v3",
        files: [
            a(
                "Decoder.mlmodelc/analytics/coremldata.bin", 243,
                "4238c4e81ecd0dc94bd7dfbb60f7e2cc824107c1ffe0387b8607b72833dba350"),
            a(
                "Decoder.mlmodelc/coremldata.bin", 554,
                "18647af085d87bd8f3121c8a9b4d4564c1ede038dab63d295b4e745cf2d7fb99"),
            a(
                "Decoder.mlmodelc/metadata.json", 3_427,
                "a39e93cd8371b8ded92635c7804fcd0590f0d1dd9415c6d19a0484be073077d9"),
            a(
                "Decoder.mlmodelc/model.mil", 13_110,
                "ef2a0a281695398a62fde86ac269c68f73d5b578d7ed3b31f2ba91a2d1ea1f35"),
            a(
                "Decoder.mlmodelc/weights/weight.bin", 23_604_992,
                "48adf0f0d47c406c8253d4f7fef967436a39da14f5a65e66d5a4b407be355d41"),
            a(
                "Encoder.mlmodelc/analytics/coremldata.bin", 243,
                "42e638870d73f26b332918a3496ce36793fbb413a81cbd3d16ba01328637a105"),
            a(
                "Encoder.mlmodelc/coremldata.bin", 485,
                "d48034a167a82e88fc3df64f60af963ab3983538271175b8319e7d5720a0fb86"),
            a(
                "Encoder.mlmodelc/metadata.json", 2_921,
                "da24da9cca943fb29d7fa8e376d57fca7cb3aa08ca51b956b0b0e56813f087e9"),
            a(
                "Encoder.mlmodelc/model.mil", 959_769,
                "ed7b19156ca29fa7dfd6891deb9fda4b0e8893f68597c985d135736546a43808"),
            a(
                "Encoder.mlmodelc/weights/weight.bin", 445_187_200,
                "e2020f323703477a5b21d7c2d282c403e371afb5962e79877e3033e73ba6f421"),
            a(
                "JointDecisionv3.mlmodelc/analytics/coremldata.bin", 243,
                "26def4bf73dd56d29dee21c8ef97cb8969e62f6120ed1adc91e46828e2737b6c"),
            a(
                "JointDecisionv3.mlmodelc/coremldata.bin", 521,
                "f5fc08b741400f0088492c9e839418b1e18522f19cba28d361dd030c5f398342"),
            a(
                "JointDecisionv3.mlmodelc/metadata.json", 3_453,
                "d9307211b9a37e0f0ac260c7660b1571a3de25841035cfdf9b58fd40425f890f"),
            a(
                "JointDecisionv3.mlmodelc/model.mil", 11_775,
                "be60732943389a047175111a83f8839f3eb39d4803adafa828a0871b2f39818d"),
            a(
                "JointDecisionv3.mlmodelc/weights/weight.bin", 12_642_764,
                "4e0e63d840032f7f07ddb1d64446051166281e5491bf22da8a945c41f6eedb3e"),
            a(
                "parakeet_vocab.json", 151_122,
                "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"),
            a(
                "Preprocessor.mlmodelc/analytics/coremldata.bin", 243,
                "c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d"),
            a(
                "Preprocessor.mlmodelc/coremldata.bin", 486,
                "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d"),
            a(
                "Preprocessor.mlmodelc/metadata.json", 2_841,
                "2a98699e22d279dd37fa1d238aeb1c6db1df0d6fad687775324157689d8f3acf"),
            a(
                "Preprocessor.mlmodelc/model.mil", 28_181,
                "4b8518a956450fec57f06c2a21bdffc26973f7f1fa6842fb38fe917f896b6b93"),
            a(
                "Preprocessor.mlmodelc/weights/weight.bin", 491_072,
                "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea"),
        ]
    )

    static let parakeetUnified = PinnedModelDefinition(
        id: "parakeet-unified-en-offline-int8",
        repository: "FluidInference/parakeet-unified-en-0.6b-coreml",
        revision: "4252711f6f060f9a2f91e5f081a806d7f45eebd8",
        localFolderName: "parakeet-unified-en-0.6b",
        files: [
            a(
                "parakeet_unified_decoder.mlmodelc/analytics/coremldata.bin", 243,
                "9ae70f6559989f88b856b326e59315798f9f0d08207a19fcc2dd3287a30088a5"),
            a(
                "parakeet_unified_decoder.mlmodelc/coremldata.bin", 560,
                "ce99c4488840fc463d59f8d4d6d2a9e8ceae8138ead51e3c265dde4d2ba4a0e9"),
            a(
                "parakeet_unified_decoder.mlmodelc/model.mil", 13_102,
                "6e60965b89c93943aa2be2d991c2461108145851fde05e1d048223a32d4cb20d"),
            a(
                "parakeet_unified_decoder.mlmodelc/weights/weight.bin", 14_429_952,
                "96f990461a5986d5e7309ad1a0f36084fbf0f4b28aec35948f8b8d0dcbf8599e"),
            a(
                "parakeet_unified_encoder_int8.mlmodelc/analytics/coremldata.bin", 243,
                "57e116a9d5765e39c0cdf754137ab744ddae34d9c6d68a5fdcad6600ae3a7b6b"),
            a(
                "parakeet_unified_encoder_int8.mlmodelc/coremldata.bin", 492,
                "54f533d30343d5e62b324a0691e4c262a6768b07b6e88e7aa14c617a2baba8a3"),
            a(
                "parakeet_unified_encoder_int8.mlmodelc/model.mil", 1_110_902,
                "c1c5d71c6cbf4d35bba08458746bde3640da7b1b444e1229a269393a58222c10"),
            a(
                "parakeet_unified_encoder_int8.mlmodelc/weights/weight.bin", 595_051_904,
                "f984b81590a4deae041ae20fbab8981c2d2a5b528b2ac81fae81c432633535c6"),
            a(
                "parakeet_unified_joint_decision_single_step.mlmodelc/analytics/coremldata.bin",
                243, "163877ad14af97ec4107cd854fd1c6d336ee5d40ad25a657cc764fb763f452f5"),
            a(
                "parakeet_unified_joint_decision_single_step.mlmodelc/coremldata.bin", 556,
                "68a081570a48b52ec9379e153bd56748a5408a50be16767601563f231eaeff03"),
            a(
                "parakeet_unified_joint_decision_single_step.mlmodelc/model.mil", 9_611,
                "03c21096090bcd0b71c896c5ae0eb815db31a91c6676f572a7868eee4299abe3"),
            a(
                "parakeet_unified_joint_decision_single_step.mlmodelc/weights/weight.bin",
                3_446_978, "06831afa6d1beb0c0b10350ebf7886bc37638e951d14e738d7e06fbd2a05012f"),
            a(
                "vocab.json", 15_088,
                "e1a7bff4f5df133c0f4ad47b8e43c96f6bf1865d99126a4c4725ef51d0108bec"),
        ]
    )

    static let sileroVAD = PinnedModelDefinition(
        id: "silero-vad-v6.2.1",
        repository: "FluidInference/silero-vad-coreml",
        revision: "b419383c55c110e2c9271fa6ee0ea83d03c70d96",
        localFolderName: "silero-vad",
        files: [
            a(
                "silero-vad-unified-256ms-v6.2.1.mlmodelc/analytics/coremldata.bin", 243,
                "8067594eb3126ab8318af507f0c00cabfed40d5fedb8a0ee5075dd02e903d909"),
            a(
                "silero-vad-unified-256ms-v6.2.1.mlmodelc/coremldata.bin", 625,
                "7db35a4fd995222a7fb0129713473b15d1462572ab4a2e5e4d56bcaad9e40f41"),
            a(
                "silero-vad-unified-256ms-v6.2.1.mlmodelc/metadata.json", 3_335,
                "2740be542c611e1ba358e1849b4e265c65cdf0b17192767e1e5de86a31ac94d6"),
            a(
                "silero-vad-unified-256ms-v6.2.1.mlmodelc/model.mil", 176_918,
                "c6a9d1bf22d413265da0a07a1d14151c3ea2fad296b3aa5859275b33ef1c3270"),
            a(
                "silero-vad-unified-256ms-v6.2.1.mlmodelc/weights/weight.bin", 882_304,
                "53ecc8b5081146140ab654c89109cf001f2183abddd7a2411c5081feeffff063"),
        ]
    )

    static let all = [parakeetTDT, parakeetUnified, sileroVAD]

    private static func a(_ path: String, _ byteCount: Int64, _ sha256: String)
        -> PinnedModelArtifact
    {
        PinnedModelArtifact(path: path, byteCount: byteCount, sha256: sha256)
    }
}

enum PinnedModelStoreError: LocalizedError {
    case invalidManifest(String)
    case notProvisioned(modelID: String, expectedDirectories: [URL])
    case integrityFailed(modelID: String, path: String)
    case unexpectedContents(String)
    case unsafeManagedStorage(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest(let reason):
            return "The reviewed speech-model manifest is invalid: \(reason)."
        case .notProvisioned(let modelID, let expectedDirectories):
            let locations = expectedDirectories.map(Self.displayPath).joined(separator: " or ")
            return
                "The reviewed on-device speech model \(modelID) is not provisioned at \(locations). Install the offline model bundle, or ask your administrator to provision it, then verify the model again."
        case .integrityFailed(let modelID, let path):
            return
                "Speech-model verification failed for \(modelID)/\(path). Re-provision the reviewed offline model bundle before trying again."
        case .unexpectedContents(let modelID):
            return
                "The speech-model cache for \(modelID) does not match the reviewed manifest. Re-provision the offline model bundle before trying again."
        case .unsafeManagedStorage(let path):
            return
                "The managed speech-model storage at \(path) is not a root:wheel, read-only-to-users system tree. Ask your administrator to reinstall and verify the managed model package."
        }
    }

    private static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

actor PinnedModelStore {
    private enum RootTrust: Equatable {
        case user
        case managedSystem
    }

    private struct SearchRoot {
        let directory: URL
        let trust: RootTrust
    }

    private struct SecurityMetadata {
        let type: FileAttributeType
        let ownerID: UInt32
        let groupID: UInt32
        let permissions: Int
    }

    static let shared = PinnedModelStore(
        managedRootDirectory: AppPaths.managedSpeechModelsDirectory,
        userRootDirectory: AppPaths.speechModelsDirectory
    )

    private let searchRoots: [SearchRoot]
    private var verifiedThisProcess: [String: (PinnedModelDefinition, URL)] = [:]

    init(rootDirectory: URL) {
        self.searchRoots = [SearchRoot(directory: rootDirectory, trust: .user)]
    }

    init(userRootDirectories: [URL]) {
        precondition(!userRootDirectories.isEmpty)
        self.searchRoots = userRootDirectories.map { SearchRoot(directory: $0, trust: .user) }
    }

    init(managedRootDirectory: URL, userRootDirectory: URL) {
        self.searchRoots = [
            SearchRoot(directory: managedRootDirectory, trust: .managedSystem),
            SearchRoot(directory: userRootDirectory, trust: .user),
        ]
    }

    func prepare(_ model: PinnedModelDefinition) async throws -> URL {
        try model.validate()
        if let verified = verifiedThisProcess[model.localFolderName] {
            guard verified.0 == model else {
                throw PinnedModelStoreError.invalidManifest(
                    "conflicting definitions target \(model.localFolderName)")
            }
            return verified.1
        }

        let candidates = searchRoots.map {
            $0.directory.appendingPathComponent(model.localFolderName, isDirectory: true)
        }
        for root in searchRoots {
            if root.trust == .managedSystem {
                guard let metadata = try Self.securityMetadata(at: root.directory) else {
                    continue
                }
                try Self.verifyManagedSearchRoot(root.directory, metadata: metadata)
            }

            let destination = root.directory.appendingPathComponent(
                model.localFolderName,
                isDirectory: true
            )
            guard let metadata = try Self.securityMetadata(at: destination) else {
                continue
            }
            guard metadata.type == .typeDirectory else {
                throw PinnedModelStoreError.unexpectedContents(model.id)
            }

            try Self.verifyDirectory(
                destination,
                against: model,
                requiresManagedMetadata: root.trust == .managedSystem
            )
            verifiedThisProcess[model.localFolderName] = (model, destination)
            return destination
        }
        throw PinnedModelStoreError.notProvisioned(
            modelID: model.id,
            expectedDirectories: candidates
        )
    }

    private static func verifyDirectory(
        _ directory: URL,
        against model: PinnedModelDefinition,
        requiresManagedMetadata: Bool
    ) throws {
        let fileManager = FileManager.default
        guard let directoryMetadata = try securityMetadata(at: directory),
            directoryMetadata.type == .typeDirectory
        else {
            throw PinnedModelStoreError.unexpectedContents(model.id)
        }
        if requiresManagedMetadata {
            try verifyManagedTreeItem(directory, metadata: directoryMetadata, expectedMode: 0o755)
        }
        let rootValues = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootValues.isSymbolicLink != true else {
            throw PinnedModelStoreError.unexpectedContents(model.id)
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        var enumerationFailed = false
        guard
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [],
                errorHandler: { _, _ in
                    enumerationFailed = true
                    return false
                }
            )
        else {
            throw PinnedModelStoreError.unexpectedContents(model.id)
        }
        var actualPaths = Set<String>()
        var actualDirectories = Set<String>()
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                throw PinnedModelStoreError.unexpectedContents(model.id)
            }
            if values.isRegularFile == true {
                if requiresManagedMetadata {
                    guard let metadata = try securityMetadata(at: item) else {
                        throw PinnedModelStoreError.unexpectedContents(model.id)
                    }
                    try verifyManagedTreeItem(item, metadata: metadata, expectedMode: 0o644)
                }
                actualPaths.insert(relativePath(of: item, under: directory))
            } else if values.isDirectory == true {
                if requiresManagedMetadata {
                    guard let metadata = try securityMetadata(at: item) else {
                        throw PinnedModelStoreError.unexpectedContents(model.id)
                    }
                    try verifyManagedTreeItem(item, metadata: metadata, expectedMode: 0o755)
                }
                actualDirectories.insert(relativePath(of: item, under: directory))
            } else {
                throw PinnedModelStoreError.unexpectedContents(model.id)
            }
        }
        var expectedDirectories = Set<String>()
        for artifact in model.files {
            let components = artifact.path.split(separator: "/").dropLast()
            var path = ""
            for component in components {
                path = path.isEmpty ? String(component) : "\(path)/\(component)"
                expectedDirectories.insert(path)
            }
        }
        guard !enumerationFailed,
            actualPaths == Set(model.files.map(\.path)),
            actualDirectories == expectedDirectories
        else {
            throw PinnedModelStoreError.unexpectedContents(model.id)
        }
        for artifact in model.files {
            try verify(
                artifact,
                at: directory.appendingPathComponent(artifact.path),
                modelID: model.id
            )
        }
    }

    private static func verify(
        _ artifact: PinnedModelArtifact,
        at url: URL,
        modelID: String
    ) throws {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values.isRegularFile == true,
            values.isSymbolicLink != true,
            Int64(values.fileSize ?? -1) == artifact.byteCount,
            try sha256(at: url) == artifact.sha256
        else {
            throw PinnedModelStoreError.integrityFailed(modelID: modelID, path: artifact.path)
        }
    }

    private static func relativePath(of item: URL, under root: URL) -> String {
        String(item.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    private static func verifyManagedSearchRoot(
        _ directory: URL,
        metadata: SecurityMetadata
    ) throws {
        guard directory.isFileURL, directory.path.hasPrefix("/") else {
            throw PinnedModelStoreError.unsafeManagedStorage(directory.path)
        }

        let standardized = directory.standardizedFileURL
        let appOwnedDirectory = standardized.deletingLastPathComponent().standardizedFileURL
        var ancestor = URL(fileURLWithPath: "/", isDirectory: true)
        let components = standardized.pathComponents.dropFirst()
        var ancestors = [ancestor]
        for component in components {
            ancestor.appendPathComponent(component, isDirectory: true)
            ancestors.append(ancestor)
        }

        for item in ancestors.dropLast() {
            guard let ancestorMetadata = try securityMetadata(at: item),
                ancestorMetadata.type == .typeDirectory,
                ancestorMetadata.ownerID == 0,
                ancestorMetadata.permissions & 0o022 == 0
            else {
                throw PinnedModelStoreError.unsafeManagedStorage(item.path)
            }
            try verifyNoExtendedACLEntries(at: item)
            if item.standardizedFileURL == appOwnedDirectory {
                guard ancestorMetadata.groupID == 0,
                    ancestorMetadata.permissions == 0o755
                else {
                    throw PinnedModelStoreError.unsafeManagedStorage(item.path)
                }
            }
        }
        guard metadata.type == .typeDirectory else {
            throw PinnedModelStoreError.unsafeManagedStorage(standardized.path)
        }
        try verifyManagedTreeItem(standardized, metadata: metadata, expectedMode: 0o755)
    }

    private static func verifyManagedTreeItem(
        _ url: URL,
        metadata: SecurityMetadata,
        expectedMode: Int
    ) throws {
        guard metadata.ownerID == 0,
            metadata.groupID == 0,
            metadata.permissions == expectedMode
        else {
            throw PinnedModelStoreError.unsafeManagedStorage(url.path)
        }
        try verifyNoExtendedACLEntries(at: url)
    }

    /// Reject all extended ACL entries on the fixed system-managed trust path.
    /// User evaluation roots never call this check and remain governed by their
    /// exact-content verification boundary.
    static func verifyNoExtendedACLEntries(at url: URL) throws {
        guard url.isFileURL else {
            throw PinnedModelStoreError.unsafeManagedStorage(url.path)
        }

        let hasEntries: Bool = try url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw PinnedModelStoreError.unsafeManagedStorage(url.path)
            }

            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard descriptor >= 0 else {
                throw PinnedModelStoreError.unsafeManagedStorage(url.path)
            }
            defer { close(descriptor) }

            errno = 0
            guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
                // On macOS, ENOENT is returned when an open object has no
                // extended ACL. Every other inspection failure is unsafe.
                if errno == ENOENT {
                    return false
                }
                throw PinnedModelStoreError.unsafeManagedStorage(url.path)
            }
            defer { acl_free(UnsafeMutableRawPointer(acl)) }

            var entry: acl_entry_t?
            errno = 0
            guard acl_get_entry(acl, ACL_FIRST_ENTRY.rawValue, &entry) == 0,
                entry != nil
            else {
                throw PinnedModelStoreError.unsafeManagedStorage(url.path)
            }
            return true
        }

        if hasEntries {
            throw PinnedModelStoreError.unsafeManagedStorage(url.path)
        }
    }

    private static func securityMetadata(at url: URL) throws -> SecurityMetadata? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain
                && (cocoaError.code == NSFileNoSuchFileError
                    || cocoaError.code == NSFileReadNoSuchFileError)
            {
                return nil
            }
            throw error
        }

        guard let type = attributes[.type] as? FileAttributeType,
            let owner = attributes[.ownerAccountID] as? NSNumber,
            let group = attributes[.groupOwnerAccountID] as? NSNumber,
            let permissions = attributes[.posixPermissions] as? NSNumber
        else {
            throw PinnedModelStoreError.unsafeManagedStorage(url.path)
        }
        return SecurityMetadata(
            type: type,
            ownerID: owner.uint32Value,
            groupID: group.uint32Value,
            permissions: permissions.intValue
        )
    }

    private static func sha256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

}
