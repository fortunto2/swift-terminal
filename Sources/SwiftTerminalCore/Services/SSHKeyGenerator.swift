import Foundation
import CryptoKit

/// Generates real SSH key pairs using CryptoKit.
public struct SSHKeyGenerator: Sendable {

    /// Result of key generation.
    public struct GeneratedKey: Sendable {
        public let publicKeyOpenSSH: String
        public let privateKeyRaw: Data
        public let fingerprint: String
    }

    /// Generate an SSH key pair of the given type.
    public static func generate(type: SSHKeyType, comment: String) throws -> GeneratedKey {
        switch type {
        case .ed25519:
            return generateEd25519(comment: comment)
        case .ecdsaP256:
            return generateECDSAP256(comment: comment)
        case .rsa4096:
            return try generateRSA(comment: comment)
        }
    }

    // MARK: - Ed25519

    private static func generateEd25519(comment: String) -> GeneratedKey {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyBytes = privateKey.publicKey.rawRepresentation

        let blob = encodeSSHBlob(type: "ssh-ed25519", keyData: [publicKeyBytes])
        let publicKeyOpenSSH = "ssh-ed25519 \(blob.base64EncodedString()) \(comment)"
        let fingerprint = sshFingerprint(blob: blob)

        return GeneratedKey(
            publicKeyOpenSSH: publicKeyOpenSSH,
            privateKeyRaw: privateKey.rawRepresentation,
            fingerprint: fingerprint
        )
    }

    // MARK: - ECDSA P-256

    private static func generateECDSAP256(comment: String) -> GeneratedKey {
        let privateKey = P256.Signing.PrivateKey()
        let publicKeyBytes = privateKey.publicKey.x963Representation

        let blob = encodeSSHBlob(
            type: "ecdsa-sha2-nistp256",
            keyData: [Data("nistp256".utf8), publicKeyBytes]
        )
        let publicKeyOpenSSH = "ecdsa-sha2-nistp256 \(blob.base64EncodedString()) \(comment)"
        let fingerprint = sshFingerprint(blob: blob)

        return GeneratedKey(
            publicKeyOpenSSH: publicKeyOpenSSH,
            privateKeyRaw: privateKey.rawRepresentation,
            fingerprint: fingerprint
        )
    }

    // MARK: - RSA

    private static func generateRSA(comment: String) throws -> GeneratedKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 4096,
        ]

        var error: Unmanaged<CFError>?
        guard let privateSecKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw SSHKeyGeneratorError.rsaGenerationFailed(
                error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            )
        }

        guard let publicSecKey = SecKeyCopyPublicKey(privateSecKey) else {
            throw SSHKeyGeneratorError.rsaGenerationFailed("Failed to extract public key")
        }

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicSecKey, &error) as Data? else {
            throw SSHKeyGeneratorError.rsaGenerationFailed("Failed to export public key")
        }

        // Parse RSA public key DER: sequence of (modulus, exponent)
        let (modulus, exponent) = try parseRSAPublicKeyDER(publicKeyData)

        let blob = encodeSSHBlob(type: "ssh-rsa", keyData: [exponent, modulus])
        let publicKeyOpenSSH = "ssh-rsa \(blob.base64EncodedString()) \(comment)"
        let fingerprint = sshFingerprint(blob: blob)

        guard let privateKeyData = SecKeyCopyExternalRepresentation(privateSecKey, &error) as Data? else {
            throw SSHKeyGeneratorError.rsaGenerationFailed("Failed to export private key")
        }

        return GeneratedKey(
            publicKeyOpenSSH: publicKeyOpenSSH,
            privateKeyRaw: privateKeyData,
            fingerprint: fingerprint
        )
    }

    // MARK: - SSH Wire Format

    /// Encode an SSH public key blob: [string type][string data1][string data2]...
    private static func encodeSSHBlob(type: String, keyData: [Data]) -> Data {
        var blob = Data()
        blob.appendSSHString(type)
        for data in keyData {
            blob.appendSSHBytes(data)
        }
        return blob
    }

    /// SHA256 fingerprint in OpenSSH format: SHA256:<base64-no-padding>
    private static func sshFingerprint(blob: Data) -> String {
        let hash = SHA256.hash(data: blob)
        let base64 = Data(hash).base64EncodedString()
        // Remove trailing '=' padding to match OpenSSH format
        let trimmed = base64.replacingOccurrences(of: "=", with: "")
        return "SHA256:\(trimmed)"
    }

    // MARK: - RSA DER Parsing

    /// Parse PKCS#1 RSA public key (DER) into (modulus, exponent).
    private static func parseRSAPublicKeyDER(_ data: Data) throws -> (Data, Data) {
        var index = 0

        // SEQUENCE
        guard data[index] == 0x30 else {
            throw SSHKeyGeneratorError.rsaGenerationFailed("Invalid DER: expected SEQUENCE")
        }
        index += 1
        _ = try readDERLength(data, index: &index)

        // INTEGER (modulus)
        guard data[index] == 0x02 else {
            throw SSHKeyGeneratorError.rsaGenerationFailed("Invalid DER: expected INTEGER for modulus")
        }
        index += 1
        let modLen = try readDERLength(data, index: &index)
        let modulus = data[index..<(index + modLen)]
        index += modLen

        // INTEGER (exponent)
        guard data[index] == 0x02 else {
            throw SSHKeyGeneratorError.rsaGenerationFailed("Invalid DER: expected INTEGER for exponent")
        }
        index += 1
        let expLen = try readDERLength(data, index: &index)
        let exponent = data[index..<(index + expLen)]

        return (Data(modulus), Data(exponent))
    }

    private static func readDERLength(_ data: Data, index: inout Int) throws -> Int {
        let first = data[index]
        index += 1

        if first < 0x80 {
            return Int(first)
        }

        let numBytes = Int(first & 0x7F)
        guard numBytes <= 4 else {
            throw SSHKeyGeneratorError.rsaGenerationFailed("DER length too large")
        }

        var length = 0
        for _ in 0..<numBytes {
            length = (length << 8) | Int(data[index])
            index += 1
        }
        return length
    }
}

// MARK: - Data SSH Extensions

private extension Data {
    mutating func appendSSHString(_ string: String) {
        let bytes = Data(string.utf8)
        appendSSHBytes(bytes)
    }

    mutating func appendSSHBytes(_ bytes: Data) {
        var length = UInt32(bytes.count).bigEndian
        append(Data(bytes: &length, count: 4))
        append(bytes)
    }
}

// MARK: - Errors

public enum SSHKeyGeneratorError: LocalizedError {
    case rsaGenerationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .rsaGenerationFailed(let reason):
            "RSA key generation failed: \(reason)"
        }
    }
}
