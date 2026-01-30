import Foundation
import Security

/// Wrapper around iOS Keychain for storing SSH keys and credentials.
public struct KeychainService: Sendable {
    /// Service identifier for Keychain items.
    private static let service = "com.swiftterminal"

    // MARK: - Save

    /// Save data to the Keychain.
    public static func save(key: String, data: Data) throws {
        // Delete existing item first
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Save a string to the Keychain.
    public static func save(key: String, string: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(key: key, data: data)
    }

    // MARK: - Load

    /// Load data from the Keychain.
    public static func load(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.loadFailed(status)
        }
    }

    /// Load a string from the Keychain.
    public static func loadString(key: String) throws -> String? {
        guard let data = try load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    /// Delete an item from the Keychain.
    public static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - SSH Key Operations

    /// Save a private key to the Keychain with biometric protection.
    public static func savePrivateKey(_ privateKey: String, tag: String, requireBiometrics: Bool = true) throws {
        var accessFlags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if requireBiometrics {
            accessFlags.insert(.biometryCurrentSet)
        }

        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            accessFlags,
            nil
        )

        guard let data = privateKey.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing
        try? delete(key: tag)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecValueData as String: data,
        ]

        if let access {
            query[kSecAttrAccessControl as String] = access
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Load a private key from the Keychain (may trigger biometric prompt).
    public static func loadPrivateKey(tag: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseOperationPrompt as String: "Authenticate to use SSH key",
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled:
            throw KeychainError.biometricCanceled
        default:
            throw KeychainError.loadFailed(status)
        }
    }
}

// MARK: - Errors

public enum KeychainError: LocalizedError {
    public case saveFailed(OSStatus)
    public case loadFailed(OSStatus)
    public case deleteFailed(OSStatus)
    public case encodingFailed
    public case biometricCanceled

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Failed to save to Keychain (status: \(status))"
        case .loadFailed(let status):
            "Failed to load from Keychain (status: \(status))"
        case .deleteFailed(let status):
            "Failed to delete from Keychain (status: \(status))"
        case .encodingFailed:
            "Failed to encode data"
        case .biometricCanceled:
            "Biometric authentication was canceled"
        }
    }
}
