import Foundation
import Security
import LocalAuthentication

/// Wrapper around iOS Keychain for storing SSH keys and credentials.
public struct KeychainService: Sendable {
    /// Service identifier for Keychain items.
    private static let service = "com.swiftterminal"

    /// Whether biometric protection is enabled in user settings.
    static var isBiometricsEnabled: Bool {
        // AppStorage default is true, so nil → true
        UserDefaults.standard.object(forKey: "requireBiometrics") == nil
            || UserDefaults.standard.bool(forKey: "requireBiometrics")
    }

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
    /// Respects the biometrics setting: when OFF, tries silent read first,
    /// and auto-migrates biometric-protected items to plain storage.
    public static func load(key: String) throws -> Data? {
        #if os(iOS)
        if !isBiometricsEnabled {
            // Try silent read (no biometric UI)
            let silentQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
            ]

            var silentResult: AnyObject?
            let silentStatus = SecItemCopyMatching(silentQuery as CFDictionary, &silentResult)

            if silentStatus == errSecSuccess, let data = silentResult as? Data {
                return data
            }
            if silentStatus == errSecItemNotFound {
                return nil
            }

            // Item exists but requires auth — migrate: read with biometrics, re-save without
            let authQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseOperationPrompt as String: "Migrate SSH key (one-time)",
            ]

            var authResult: AnyObject?
            let authStatus = SecItemCopyMatching(authQuery as CFDictionary, &authResult)

            if authStatus == errSecSuccess, let data = authResult as? Data {
                // Re-save without biometric ACL
                try? savePrivateKey(data, tag: key, requireBiometrics: false)
                return data
            }
            if authStatus == errSecItemNotFound { return nil }
            if authStatus == errSecUserCanceled { throw KeychainError.biometricCanceled }
            throw KeychainError.loadFailed(authStatus)
        }
        #endif

        // Biometrics ON or macOS — standard read
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

    /// Save a private key (Data) to the Keychain, optionally with biometric protection.
    /// On macOS, always uses plain Keychain (no biometrics).
    /// When `requireBiometrics` is nil, reads from the user's Settings toggle.
    public static func savePrivateKey(_ privateKeyData: Data, tag: String, requireBiometrics: Bool? = nil) throws {
        let requireBiometrics = requireBiometrics ?? isBiometricsEnabled
        // Delete existing
        try? delete(key: tag)

        #if os(iOS)
        if requireBiometrics {
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryCurrentSet],
                nil
            )

            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: tag,
                kSecValueData as String: privateKeyData,
            ]

            if let access {
                query[kSecAttrAccessControl as String] = access
            }

            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.saveFailed(status)
            }
            return
        }
        #endif

        // Plain Keychain save (macOS always, iOS when biometrics not required)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecValueData as String: privateKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Save a private key (String) to the Keychain, optionally with biometric protection.
    public static func savePrivateKey(_ privateKey: String, tag: String, requireBiometrics: Bool? = nil) throws {
        guard let data = privateKey.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try savePrivateKey(data, tag: tag, requireBiometrics: requireBiometrics)
    }

    /// Load a private key as String from the Keychain.
    public static func loadPrivateKey(tag: String) throws -> String? {
        guard let data = try load(key: tag) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Errors

public enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed
    case biometricCanceled

    public var errorDescription: String? {
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
