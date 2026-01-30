import Foundation
@preconcurrency import Citadel

/// Manages SSH connections using Citadel.
@MainActor
@Observable
final class SSHService {
    private(set) var isConnected = false
    private(set) var currentServer: Server?
    nonisolated(unsafe) private var client: SSHClient?

    /// Connect to a server using password authentication.
    func connect(to server: Server, password: String) async throws {
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
    func connect(to server: Server, privateKeyPEM: String) async throws {
        // For MVP, we use password auth as fallback
        // Real Ed25519/RSA key auth requires parsing PEM → Crypto key types
        throw SSHServiceError.authenticationFailed
    }

    /// Execute a single command and return stdout as String.
    func execute(_ command: String) async throws -> String {
        guard let client else {
            throw SSHServiceError.notConnected
        }
        let buffer = try await client.executeCommand(command)
        return String(buffer: buffer)
    }

    /// Execute a command, streaming output line-by-line.
    func executeStreaming(
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
    func disconnect() async {
        try? await client?.close()
        client = nil
        currentServer = nil
        isConnected = false
    }
}

// MARK: - Errors

enum SSHServiceError: LocalizedError {
    case notConnected
    case authenticationFailed
    case connectionTimeout
    case commandFailed(String)

    var errorDescription: String? {
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
