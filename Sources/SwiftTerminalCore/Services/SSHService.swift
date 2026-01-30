import Foundation
import CryptoKit
@preconcurrency import Citadel

/// Manages SSH connections using Citadel.
@MainActor
@Observable
public final class SSHService {
    public private(set) var isConnected = false
    public private(set) var currentServer: Server?
    nonisolated(unsafe) private var client: SSHClient?

    public init() {}

    /// Connect to a server using password authentication.
    public func connect(to server: Server, password: String) async throws {
        let client = try await SSHClient.connect(
            host: server.host,
            port: server.port,
            authenticationMethod: .passwordBased(
                username: server.username,
                password: password
            ),
            hostKeyValidator: .acceptAnything(),
            reconnect: .never
        )

        self.client = client
        self.currentServer = server
        self.isConnected = true
    }

    /// Connect to a server using a private key.
    public func connect(to server: Server, privateKeyData: Data, keyType: SSHKeyType) async throws {
        let authMethod: SSHAuthenticationMethod

        switch keyType {
        case .ed25519:
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
            authMethod = .ed25519(username: server.username, privateKey: privateKey)

        case .ecdsaP256:
            let privateKey = try P256.Signing.PrivateKey(rawRepresentation: privateKeyData)
            authMethod = .p256(username: server.username, privateKey: privateKey)

        case .rsa4096:
            // RSA raw data is DER — parse via Citadel's Insecure.RSA
            throw SSHServiceError.authenticationFailed
        }

        let client = try await SSHClient.connect(
            host: server.host,
            port: server.port,
            authenticationMethod: authMethod,
            hostKeyValidator: .acceptAnything(),
            reconnect: .never
        )

        self.client = client
        self.currentServer = server
        self.isConnected = true
    }

    /// Execute a single command and return stdout as String.
    public func execute(_ command: String) async throws -> String {
        guard let client else {
            throw SSHServiceError.notConnected
        }
        let buffer = try await client.executeCommand(command)
        return String(buffer: buffer)
    }

    /// Disconnect the current session.
    public func disconnect() async {
        try? await client?.close()
        client = nil
        currentServer = nil
        isConnected = false
    }
}

// MARK: - Errors

public enum SSHServiceError: LocalizedError {
    case notConnected
    case authenticationFailed
    case connectionTimeout
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected to any server"
        case .authenticationFailed:
            "Authentication failed — check credentials or key"
        case .connectionTimeout:
            "Connection timed out"
        case .commandFailed(let detail):
            "Command failed: \(detail)"
        }
    }
}
