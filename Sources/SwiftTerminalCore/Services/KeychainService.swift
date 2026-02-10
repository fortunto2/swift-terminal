import Foundation
import Security
import LocalAuthentication

/// Wrapper around iOS Keychain for storing SSH keys and credentials.
/// Keys are synced via iCloud Keychain across devices sharing the same Apple ID.
public struct KeychainService: Sendable {
    /// Service identifier for Keychain items.
    private static let service = "com.swiftterminal"

    /// Suffix for local biometric-protected copies of keys.
    private static let localBiometricSuffix = ".local"

    /// Whether biometric protection is enabled in user settings.
    static var isBiometricsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "requireBiometrics")
    }

    // MARK: - Save

    /// Save data to the Keychain with iCloud sync.
    public static func save(key: String, data: Data) throws {
        // Delete existing item first
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true,
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
    /// Tries local biometric copy first (iOS), then falls back to synced copy.
    /// When biometrics are OFF, tries silent read and auto-migrates biometric items.
    public static func load(key: String) throws -> Data? {
        #if os(iOS)
        // Try local biometric copy first
        let localKey = key + localBiometricSuffix
        if isBiometricsEnabled {
            let localQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: localKey,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]

            var localResult: AnyObject?
            let localStatus = SecItemCopyMatching(localQuery as CFDictionary, &localResult)

            if localStatus == errSecSuccess, let data = localResult as? Data {
                return data
            }
            // If local copy not found, fall through to synced copy
        }

        if !isBiometricsEnabled {
            // Try silent read of synced copy (no biometric UI)
            let silentQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecAttrSynchronizable as String: true,
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
                // Also check for old non-synced items that need migration
                return try loadLegacy(key: key)
            }

            // Item exists but requires auth — migrate: read with biometrics, re-save without
            let authQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: localKey,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseOperationPrompt as String: "Migrate SSH key (one-time)",
            ]

            var authResult: AnyObject?
            let authStatus = SecItemCopyMatching(authQuery as CFDictionary, &authResult)

            if authStatus == errSecSuccess, let data = authResult as? Data {
                // Re-save as synced without biometric ACL, remove local copy
                try? savePrivateKey(data, tag: key, requireBiometrics: false)
                return data
            }
            if authStatus == errSecItemNotFound {
                return try loadLegacy(key: key)
            }
            if authStatus == errSecUserCanceled { throw KeychainError.biometricCanceled }
            throw KeychainError.loadFailed(authStatus)
        }
        #endif

        // Synced copy — standard read (macOS or iOS fallback)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
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
        case errSecAuthFailed:
            // -25293: iCloud Keychain item arrived but can't be read
            // (access group mismatch, auth context unavailable, or device not yet trusted).
            // Try non-synced legacy item as fallback.
            return try loadLegacy(key: key)
        default:
            throw KeychainError.loadFailed(status)
        }
    }

    /// Load a string from the Keychain.
    public static func loadString(key: String) throws -> String? {
        guard let data = try load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Try loading from legacy non-synced keychain (pre-iCloud migration).
    private static func loadLegacy(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            if let data = result as? Data {
                // Migrate to synced keychain
                try? save(key: key, data: data)
                // Delete legacy item
                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key,
                    kSecAttrSynchronizable as String: false,
                ]
                SecItemDelete(deleteQuery as CFDictionary)
                return data
            }
            return nil
        case errSecItemNotFound:
            return nil
        default:
            return nil
        }
    }

    // MARK: - Delete

    /// Delete an item from the Keychain (both synced and local biometric copies).
    public static func delete(key: String) throws {
        // Delete synced copy (kSecAttrSynchronizableAny matches both synced and non-synced)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }

        // Also delete local biometric copy if it exists
        let localKey = key + localBiometricSuffix
        let localQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: localKey,
        ]
        SecItemDelete(localQuery as CFDictionary)
    }

    // MARK: - SSH Key Operations

    /// Save a private key (Data) to the Keychain, optionally with biometric protection.
    /// Always saves a synced copy for iCloud transfer.
    /// On iOS with biometrics: also saves a local biometric-protected copy.
    /// On macOS: always uses plain synced Keychain (no biometrics).
    public static func savePrivateKey(_ privateKeyData: Data, tag: String, requireBiometrics: Bool? = nil) throws {
        let requireBiometrics = requireBiometrics ?? isBiometricsEnabled

        // Always save synced copy (no biometrics) for iCloud transfer
        try? delete(key: tag)

        let syncedQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecValueData as String: privateKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true,
        ]

        let syncedStatus = SecItemAdd(syncedQuery as CFDictionary, nil)
        guard syncedStatus == errSecSuccess else {
            throw KeychainError.saveFailed(syncedStatus)
        }

        #if os(iOS)
        if requireBiometrics {
            // Also save local biometric-protected copy for runtime access
            let localTag = tag + localBiometricSuffix
            let localDeleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: localTag,
            ]
            SecItemDelete(localDeleteQuery as CFDictionary)

            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryCurrentSet],
                nil
            )

            var localQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: localTag,
                kSecValueData as String: privateKeyData,
            ]

            if let access {
                localQuery[kSecAttrAccessControl as String] = access
            }

            let localStatus = SecItemAdd(localQuery as CFDictionary, nil)
            // Non-fatal if local biometric save fails — synced copy is primary
            if localStatus != errSecSuccess {
                print("Warning: Failed to save local biometric copy (status: \(localStatus))")
            }
        }
        #endif
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
