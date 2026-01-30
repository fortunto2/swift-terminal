import Foundation
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
        let settings = SSHClientSettings(
            host: server.host,
            port: server.port,
            authenticationMethod: {
                .passwordBased(username: server.username, password: password)
            },
            hostKeyValidator: .acceptAnything()
        )

        let client = try await SSHClient.connect(to: settings)
        self.client = client
        self.currentServer = server
        self.isConnected = true
    }

    /// Connect to a server using a private key (Ed25519).
    public func connect(to server: Server, privateKeyPEM: String) async throws {
        // For MVP, we use password auth as fallback
        // Real Ed25519/RSA key auth requires parsing PEM → Crypto key types
        throw SSHServiceError.authenticationFailed
    }

    /// Execute a single command and return stdout as String.
    public func execute(_ command: String) async throws -> String {
        guard let client else {
            throw SSHServiceError.notConnected
        }
        let buffer = try await client.executeCommand(command)
        return String(buffer: buffer)
    }

    /// Execute a command, streaming output line-by-line.
    public func executeStreaming(
        _ command: String,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let client else {
            throw SSHServiceError.notConnected
        }
        let buffer = try await client.executeCommand(command)
        let result = String(buffer: buffer)
        for line in result.components(separatedBy: "\n") {
            onOutput(line)
        }
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
            "Authentication failed — check credentials"
        case .connectionTimeout:
            "Connection timed out"
        case .commandFailed(let detail):
            "Command failed: \(detail)"
        }
    }
}
