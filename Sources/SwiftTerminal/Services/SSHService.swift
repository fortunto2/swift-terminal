import Foundation
import Citadel
import NIOSSH

/// Manages SSH connections using Citadel.
@MainActor
@Observable
final class SSHService {
    private(set) var isConnected = false
    private(set) var currentServer: Server?
    private var client: SSHClient?

    /// Connect to a server using password authentication.
    func connect(to server: Server, password: String) async throws {
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
    func connect(to server: Server, privateKey: String, passphrase: String? = nil) async throws {
        let authMethod: SSHAuthenticationMethod = .rsa(
            username: server.username,
            privateKey: .init(sshRsa: privateKey)
        )

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

    /// Execute a single command and return stdout.
    func execute(_ command: String) async throws -> String {
        guard let client else {
            throw SSHServiceError.notConnected
        }
        let output = try await client.executeCommand(command)
        let result = String(buffer: output)
        return result
    }

    /// Execute a command, streaming output line-by-line.
    func executeStreaming(
        _ command: String,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let client else {
            throw SSHServiceError.notConnected
        }
        // For MVP, execute and return full output
        let output = try await client.executeCommand(command)
        let result = String(buffer: output)
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
