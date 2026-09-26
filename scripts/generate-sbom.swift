import CryptoKit
import Foundation

private struct SBOMError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct PackageResolved: Decodable {
    struct Pin: Decodable {
        struct State: Decodable {
            let revision: String?
            let version: String?
        }

        let identity: String
        let kind: String
        let location: String
        let state: State
    }

    let originHash: String?
    let pins: [Pin]
}

private struct LicenseSpec: Decodable {
    let id: String?
    let name: String?
}

private struct Inventory: Decodable {
    struct SwiftPackage: Decodable {
        let identity: String
        let name: String
        let group: String
        let description: String
        let expectedLocation: String
        let license: LicenseSpec
    }

    struct VendoredComponent: Decodable {
        let bomRef: String
        let name: String
        let group: String
        let version: String
        let description: String
        let sourcePath: String
        let licensePath: String
        let sourceURL: String
        let license: LicenseSpec
        let modificationNote: String
    }

    struct RuntimeComponent: Decodable {
        let bomRef: String
        let type: String
        let name: String
        let group: String
        let scope: String
        let description: String
        let sourceURL: String
        let referenceType: String
        let dependencyParent: String
        let provisioning: String
        let versionStatus: String
        let artifactHashStatus: String
        let license: LicenseSpec
    }

    let schemaVersion: Int
    let swiftPackages: [SwiftPackage]
    let vendoredComponents: [VendoredComponent]
    let runtimeComponents: [RuntimeComponent]
}

private struct Options {
    let root: URL
    let output: URL
    let sourceRevision: String
    let sourceState: String
    let serialNumber: String
}

private let allowedComponentTypes: Set<String> = [
    "application", "framework", "library", "machine-learning-model",
]
private let allowedScopes: Set<String> = ["required", "optional", "excluded"]
private let allowedReferenceTypes: Set<String> = ["documentation", "model-card"]

private func stderr(_ message: String) {
    let data = Data((message + "\n").utf8)
    try? FileHandle.standardError.write(contentsOf: data)
}

private func parseOptions() throws -> Options {
    var values: [String: String] = [:]
    var index = 1
    let arguments = CommandLine.arguments
    while index < arguments.count {
        let key = arguments[index]
        guard key.hasPrefix("--"), index + 1 < arguments.count else {
            throw SBOMError("invalid command arguments")
        }
        guard values[key] == nil else {
            throw SBOMError("duplicate command option: \(key)")
        }
        values[key] = arguments[index + 1]
        index += 2
    }

    let allowed = Set([
        "--root", "--output", "--source-revision", "--source-state", "--serial-number",
    ])
    guard Set(values.keys).isSubset(of: allowed) else {
        throw SBOMError("unsupported command option")
    }
    guard let root = values["--root"],
        let output = values["--output"],
        let sourceRevision = values["--source-revision"],
        let sourceState = values["--source-state"]
    else {
        throw SBOMError("required options: --root --output --source-revision --source-state")
    }
    guard sourceRevision.range(of: "^[0-9a-f]{40,64}$", options: .regularExpression) != nil else {
        throw SBOMError("source revision must be a lowercase hexadecimal commit identifier")
    }
    guard ["clean", "modified"].contains(sourceState) else {
        throw SBOMError("source state must be clean or modified")
    }
    // Each generated BOM gets a distinct RFC 4122 identity. An explicit identity
    // is useful only when reproducing a previously generated document or fixture.
    let serialNumber = values["--serial-number"] ?? "urn:uuid:\(UUID().uuidString.lowercased())"
    guard
        serialNumber.range(
            of:
                "^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
            options: .regularExpression
        ) != nil
    else {
        throw SBOMError("serial number must be a lowercase RFC 4122 UUID URN")
    }
    return Options(
        root: URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL,
        output: URL(fileURLWithPath: output).standardizedFileURL,
        sourceRevision: sourceRevision,
        sourceState: sourceState,
        serialNumber: serialNumber
    )
}

private func readData(_ relativePath: String, root: URL) throws -> Data {
    let url = try safeURL(relativePath, root: root)
    do {
        return try Data(contentsOf: url)
    } catch {
        throw SBOMError("cannot read required repository evidence: \(relativePath)")
    }
}

private func decodeJSON<T: Decodable>(
    _ type: T.Type,
    relativePath: String,
    root: URL
) throws -> T {
    let data = try readData(relativePath, root: root)
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw SBOMError("invalid JSON repository evidence: \(relativePath)")
    }
}

private func safeURL(_ relativePath: String, root: URL) throws -> URL {
    guard !relativePath.isEmpty,
        !relativePath.hasPrefix("/"),
        !relativePath.split(separator: "/").contains("..")
    else {
        throw SBOMError("inventory paths must be repository-relative")
    }
    let result = root.appendingPathComponent(relativePath).standardizedFileURL
    guard result.path == root.path || result.path.hasPrefix(root.path + "/") else {
        throw SBOMError("inventory path escaped repository root")
    }
    return result
}

private func requirePublicHTTPS(_ value: String, label: String) throws {
    guard let url = URL(string: value),
        url.scheme == "https",
        url.host != nil,
        url.user == nil,
        url.password == nil,
        url.query == nil,
        url.fragment == nil
    else {
        throw SBOMError(
            "\(label) must be a public HTTPS URL without credentials, query parameters, or fragments"
        )
    }
}

private func licenseChoice(_ specification: LicenseSpec) throws -> [[String: Any]] {
    switch (specification.id, specification.name) {
    case let (.some(id), nil) where !id.isEmpty:
        return [["license": ["id": id]]]
    case let (nil, .some(name)) where !name.isEmpty:
        return [["license": ["name": name]]]
    default:
        throw SBOMError("each inventory license must contain exactly one non-empty id or name")
    }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Canonical digest of a vendored source tree. Paths are repository-relative,
/// sorted bytewise, and separated from file bytes with NUL. Symlinks are
/// refused so generation cannot traverse outside the declared component.
private func sourceTreeSHA256(relativePath: String, root: URL) throws -> String {
    let directory = try safeURL(relativePath, root: root)
    guard
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
    else {
        throw SBOMError("cannot enumerate vendored component: \(relativePath)")
    }

    var files: [(relative: String, url: URL)] = []
    for case let url as URL in enumerator {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch {
            throw SBOMError("cannot inspect vendored component: \(relativePath)")
        }
        guard values.isSymbolicLink != true else {
            throw SBOMError("vendored component contains a symbolic link: \(relativePath)")
        }
        guard values.isRegularFile == true else { continue }
        let directoryComponents = directory.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > directoryComponents.count,
            Array(fileComponents.prefix(directoryComponents.count)) == directoryComponents
        else {
            throw SBOMError("vendored component enumeration escaped its root")
        }
        files.append(
            (fileComponents.dropFirst(directoryComponents.count).joined(separator: "/"), url))
    }
    guard !files.isEmpty else {
        throw SBOMError("vendored component has no source files: \(relativePath)")
    }

    var hasher = SHA256()
    for file in files.sorted(by: { $0.relative.utf8.lexicographicallyPrecedes($1.relative.utf8) }) {
        hasher.update(data: Data(file.relative.utf8))
        hasher.update(data: Data([0]))
        do {
            hasher.update(data: try Data(contentsOf: file.url))
        } catch {
            throw SBOMError("cannot hash vendored component: \(relativePath)")
        }
        hasher.update(data: Data([0]))
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func readInfoPlist(root: URL) throws -> [String: Any] {
    let data = try readData("Info.plist", root: root)
    do {
        guard
            let object = try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        else {
            throw SBOMError("Info.plist must contain a dictionary")
        }
        return object
    } catch let error as SBOMError {
        throw error
    } catch {
        throw SBOMError("invalid Info.plist repository evidence")
    }
}

private func requiredPlistString(_ key: String, from plist: [String: Any]) throws -> String {
    guard let value = plist[key] as? String,
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        throw SBOMError("Info.plist is missing required value: \(key)")
    }
    return value
}

private func property(_ name: String, _ value: String) -> [String: String] {
    ["name": name, "value": value]
}

private func generate(options: Options) throws -> Data {
    let inventory = try decodeJSON(
        Inventory.self,
        relativePath: "security/sbom-components.json",
        root: options.root
    )
    guard inventory.schemaVersion == 1 else {
        throw SBOMError("unsupported SBOM inventory schema version")
    }

    let resolved = try decodeJSON(
        PackageResolved.self,
        relativePath: "Package.resolved",
        root: options.root
    )
    let plist = try readInfoPlist(root: options.root)
    let appName = try requiredPlistString("CFBundleDisplayName", from: plist)
    let bundleID = try requiredPlistString("CFBundleIdentifier", from: plist)
    let appVersion = try requiredPlistString("CFBundleShortVersionString", from: plist)
    let buildNumber = try requiredPlistString("CFBundleVersion", from: plist)
    let rootRef = "pkg:generic/\(bundleID)@\(appVersion)?build=\(buildNumber)"

    var inventoryPackages: [String: Inventory.SwiftPackage] = [:]
    for package in inventory.swiftPackages {
        guard inventoryPackages[package.identity] == nil else {
            throw SBOMError(
                "SBOM inventory contains duplicate Swift package identity: \(package.identity)")
        }
        inventoryPackages[package.identity] = package
    }
    var resolvedPackages: [String: PackageResolved.Pin] = [:]
    for pin in resolved.pins {
        guard resolvedPackages[pin.identity] == nil else {
            throw SBOMError(
                "Package.resolved contains duplicate Swift package identity: \(pin.identity)")
        }
        resolvedPackages[pin.identity] = pin
    }

    let unknownPins = Set(resolvedPackages.keys).subtracting(inventoryPackages.keys).sorted()
    guard unknownPins.isEmpty else {
        throw SBOMError(
            "Package.resolved contains uninventoryed Swift package: \(unknownPins.joined(separator: ", "))"
        )
    }
    let missingPins = Set(inventoryPackages.keys).subtracting(resolvedPackages.keys).sorted()
    guard missingPins.isEmpty else {
        throw SBOMError(
            "SBOM inventory package is absent from Package.resolved: \(missingPins.joined(separator: ", "))"
        )
    }

    var components: [[String: Any]] = []
    var refsByIdentity: [String: String] = [:]
    for identity in inventoryPackages.keys.sorted() {
        guard let specification = inventoryPackages[identity],
            let pin = resolvedPackages[identity]
        else { continue }
        try requirePublicHTTPS(specification.expectedLocation, label: "Swift package location")
        guard pin.location == specification.expectedLocation else {
            throw SBOMError(
                "Package.resolved location does not match reviewed inventory: \(identity)")
        }
        guard pin.kind == "remoteSourceControl" else {
            throw SBOMError("unsupported Swift package source kind: \(identity)")
        }
        guard let version = pin.state.version, !version.isEmpty,
            let revision = pin.state.revision,
            revision.range(of: "^[0-9a-f]{40,64}$", options: .regularExpression) != nil
        else {
            throw SBOMError("Swift package is not pinned to a version and commit: \(identity)")
        }
        let ref = "pkg:github/\(specification.group)/\(specification.name)@\(version)"
        refsByIdentity[identity] = ref
        components.append([
            "type": "library",
            "bom-ref": ref,
            "group": specification.group,
            "name": specification.name,
            "version": version,
            "description": specification.description,
            "scope": "required",
            "purl": ref,
            "licenses": try licenseChoice(specification.license),
            "externalReferences": [["type": "vcs", "url": specification.expectedLocation]],
            "properties": [
                property("com.lockedinflow.component.provisioning", "compiled-in"),
                property("com.lockedinflow.component.version-status", "pinned"),
                property("com.lockedinflow.swiftpm.revision", revision),
            ].sorted { $0["name"]! < $1["name"]! },
        ])
    }

    var applicationDependencies = Array(refsByIdentity.values)
    for component in inventory.vendoredComponents {
        try requirePublicHTTPS(component.sourceURL, label: "vendored component source")
        let treeHash = try sourceTreeSHA256(relativePath: component.sourcePath, root: options.root)
        let licenseHash = sha256(try readData(component.licensePath, root: options.root))
        components.append([
            "type": "library",
            "bom-ref": component.bomRef,
            "group": component.group,
            "name": component.name,
            "version": component.version,
            "description": component.description,
            "scope": "required",
            "purl": component.bomRef,
            "licenses": try licenseChoice(component.license),
            "externalReferences": [["type": "vcs", "url": component.sourceURL]],
            "pedigree": ["notes": component.modificationNote],
            "properties": [
                property("com.lockedinflow.component.provisioning", "vendored-source"),
                property("com.lockedinflow.component.version-status", "declared-upstream-version"),
                property("com.lockedinflow.license.sha256", licenseHash),
                property("com.lockedinflow.source-tree.sha256", treeHash),
                property(
                    "com.lockedinflow.source-tree.hash-algorithm",
                    "sorted-relative-path-nul-file-bytes-nul"),
            ].sorted { $0["name"]! < $1["name"]! },
        ])
        applicationDependencies.append(component.bomRef)
    }

    var dependenciesByParent: [String: [String]] = [:]
    for component in inventory.runtimeComponents {
        guard allowedComponentTypes.contains(component.type),
            allowedScopes.contains(component.scope),
            allowedReferenceTypes.contains(component.referenceType)
        else {
            throw SBOMError(
                "runtime component contains an unsupported CycloneDX value: \(component.bomRef)")
        }
        try requirePublicHTTPS(component.sourceURL, label: "runtime component source")
        components.append([
            "type": component.type,
            "bom-ref": component.bomRef,
            "group": component.group,
            "name": component.name,
            "description": component.description,
            "scope": component.scope,
            "licenses": try licenseChoice(component.license),
            "externalReferences": [["type": component.referenceType, "url": component.sourceURL]],
            "properties": [
                property("com.lockedinflow.component.provisioning", component.provisioning),
                property("com.lockedinflow.component.version-status", component.versionStatus),
                property(
                    "com.lockedinflow.component.artifact-hash-status", component.artifactHashStatus),
            ].sorted { $0["name"]! < $1["name"]! },
        ])
        if component.dependencyParent == "application" {
            applicationDependencies.append(component.bomRef)
        } else if let parentRef = refsByIdentity[component.dependencyParent] {
            dependenciesByParent[parentRef, default: []].append(component.bomRef)
        } else {
            throw SBOMError(
                "runtime component references an unknown dependency parent: \(component.bomRef)")
        }
    }

    components.sort {
        (($0["bom-ref"] as? String) ?? "") < (($1["bom-ref"] as? String) ?? "")
    }
    let componentRefs = components.compactMap { $0["bom-ref"] as? String }
    guard Set(componentRefs).count == componentRefs.count else {
        throw SBOMError("SBOM inventory produces duplicate component references")
    }

    var dependencies: [[String: Any]] = [
        [
            "ref": rootRef,
            "dependsOn": Array(Set(applicationDependencies)).sorted(),
        ]
    ]
    for ref in componentRefs {
        dependencies.append([
            "ref": ref,
            "dependsOn": Array(Set(dependenciesByParent[ref] ?? [])).sorted(),
        ])
    }
    dependencies.sort {
        (($0["ref"] as? String) ?? "") < (($1["ref"] as? String) ?? "")
    }

    var metadataProperties = [
        property(
            "com.lockedinflow.inventory.completeness",
            "runtime-model-files-sha256-pinned-platform-libraries-excluded"
        ),
        property("com.lockedinflow.inventory.profile", "mac-app-build-v1"),
        property("com.lockedinflow.source.revision", options.sourceRevision),
        property("com.lockedinflow.source.state", options.sourceState),
    ]
    if let originHash = resolved.originHash, !originHash.isEmpty {
        metadataProperties.append(property("com.lockedinflow.swiftpm.origin-hash", originHash))
    }
    metadataProperties.sort { $0["name"]! < $1["name"]! }

    let document: [String: Any] = [
        "$schema": "https://cyclonedx.org/schema/bom-1.6.schema.json",
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": options.serialNumber,
        "version": 1,
        "metadata": [
            "lifecycles": [["phase": "build"]],
            "component": [
                "type": "application",
                "bom-ref": rootRef,
                "name": appName,
                "version": appVersion,
                "purl": rootRef,
                "licenses": [
                    [
                        "license": ["id": "MIT"]
                    ]
                ],
                "properties": [
                    property("com.lockedinflow.app.build-number", buildNumber),
                    property("com.lockedinflow.app.bundle-identifier", bundleID),
                ],
            ],
            "properties": metadataProperties,
        ],
        "components": components,
        "dependencies": dependencies,
        "compositions": [
            [
                "aggregate": "incomplete",
                "assemblies": [rootRef],
                "dependencies": componentRefs,
            ]
        ],
    ]

    guard JSONSerialization.isValidJSONObject(document) else {
        throw SBOMError("generated SBOM is not valid JSON")
    }
    var output = try JSONSerialization.data(
        withJSONObject: document,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    output.append(0x0A)
    return output
}

do {
    let options = try parseOptions()
    let output = try generate(options: options)
    do {
        try FileManager.default.createDirectory(
            at: options.output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try output.write(to: options.output, options: .atomic)
    } catch {
        throw SBOMError("cannot write SBOM output")
    }
    print("SBOM-GENERATED")
} catch let error as SBOMError {
    stderr("SBOM-ERROR: \(error.description)")
    exit(1)
} catch {
    stderr("SBOM-ERROR: unexpected generation failure")
    exit(1)
}
