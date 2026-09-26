import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// AES-GCM encryption for local files, with the symmetric key stored in the macOS Keychain.
/// Keychain access is configured to fail without authentication UI. Persistent writes
/// fail closed when the durable key is unavailable; the app never creates ciphertext
/// with a process-ephemeral key that would become unreadable after restart.
public enum SecureStore {
    public enum StoreError: Error {
        case keychain(OSStatus)
        case encryptionFailed
        case decryptionFailed
    }

    private static let service = AppBuildIdentity.keychainService
    private static let account = "local-storage-key"

    #if DEBUG
        /// Synthetic test key, excluded entirely from release compilation.
        private static let testKeyData = Data((0..<32).map { UInt8($0 &* 7 &+ 11) })
    #endif

    public static func encryptionKey() throws -> SymmetricKey {
        #if DEBUG
            // Tests must never touch the real Keychain: signature changes (ad-hoc ↔
            // Developer ID) turn SecItemCopyMatching into a GUI prompt, which hangs
            // headless runners. Under XCTest use a process-ephemeral key instead.
            if NSClassFromString("XCTestCase") != nil {
                return SymmetricKey(data: testKeyData)
            }
        #endif
        if let existing = try loadKey() { return existing }
        return try createKey()
    }

    private static func createKey() throws -> SymmetricKey {
        var keyData = Data(count: 32)
        let status = keyData.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Another caller may have won the creation race. Re-read without
            // authentication UI instead of deleting an item we cannot access.
            guard let existing = try loadKey() else {
                throw StoreError.keychain(addStatus)
            }
            return existing
        } else if addStatus != errSecSuccess {
            throw StoreError.keychain(addStatus)
        }
        return SymmetricKey(data: keyData)
    }

    private static func loadKey() throws -> SymmetricKey? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw StoreError.keychain(status)
        }
        return SymmetricKey(data: data)
    }

    public static func encrypt(_ data: Data) throws -> Data {
        let key = try encryptionKey()
        guard let sealed = try? AES.GCM.seal(data, using: key), let combined = sealed.combined
        else {
            throw StoreError.encryptionFailed
        }
        return combined
    }

    public static func decrypt(_ data: Data) throws -> Data {
        let key = try encryptionKey()
        guard let box = try? AES.GCM.SealedBox(combined: data),
            let plain = try? AES.GCM.open(box, using: key)
        else {
            throw StoreError.decryptionFailed
        }
        return plain
    }

    public static func writeEncrypted(_ data: Data, to url: URL) throws {
        let encrypted = try encrypt(data)
        try encrypted.write(to: url, options: .atomic)
    }

    public static func readEncrypted(from url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decrypt(data)
    }
}
