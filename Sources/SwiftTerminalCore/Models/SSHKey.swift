import Foundation

/// Type of SSH key.
public enum SSHKeyType: String, Codable, Sendable, CaseIterable, Identifiable {
    public case ed25519
    public case rsa4096
    public case ecdsaP256

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ed25519: "Ed25519"
        case .rsa4096: "RSA 4096"
        case .ecdsaP256: "ECDSA P-256"
        }
    }

    var algorithmName: String {
        switch self {
        case .ed25519: "ssh-ed25519"
        case .rsa4096: "ssh-rsa"
        case .ecdsaP256: "ecdsa-sha2-nistp256"
        }
    }
}

/// An SSH key pair. Private key is stored in Keychain; only metadata is persisted here.
public struct SSHKey: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
    var keyType: SSHKeyType
    var publicKey: String
    var fingerprint: String
    var createdAt: Date
    /// Keychain item identifier for the private key.
    var keychainTag: String

    init(
        id: UUID = UUID(),
        name: String,
        keyType: SSHKeyType = .ed25519,
        publicKey: String,
        fingerprint: String = "",
        createdAt: Date = .now,
        keychainTag: String? = nil
    ) {
        self.id = id
        self.name = name
        self.keyType = keyType
        self.publicKey = publicKey
        self.fingerprint = fingerprint
        self.createdAt = createdAt
        self.keychainTag = keychainTag ?? "com.swiftterminal.key.\(id.uuidString)"
    }
}

extension SSHKey {
    public static let preview = SSHKey(
        name: "Default Key",
        keyType: .ed25519,
        publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@device",
        fingerprint: "SHA256:abc123..."
    )
}
