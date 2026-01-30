import Foundation
import CryptoKit
@preconcurrency import Citadel
@preconcurrency import NIOSSH
import NIOCore

/// Thread-safe writer wrapper for shell input.
public final class ShellWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var _writer: TTYStdinWriter?

    init() {}

    func set(_ writer: TTYStdinWriter) {
        lock.withLock { _writer = writer }
    }

    func clear() {
        lock.withLock { _writer = nil }
    }

    public func write(_ data: Data) {
        let writer = lock.withLock { _writer }
        guard let writer else { return }
        Task {
            try? await writer.write(ByteBuffer(data: data))
        }
    }

    public func resize(cols: Int, rows: Int) {
        let writer = lock.withLock { _writer }
        guard let writer else { return }
        Task {
            try? await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
        }
    }
}

/// Manages SSH connections using Citadel.
@MainActor
@Observable
public final class SSHService {
    public private(set) var isConnected = false
    public private(set) var currentServer: Server?
    public let shellWriter = ShellWriter()
    nonisolated(unsafe) private var client: SSHClient?
    private var shellTask: Task<Void, Never>?

    /// Called when shell output arrives. Set before starting shell.
    public var onOutput: (@Sendable (Data) -> Void)?

    public init() {}

    // MARK: - Connect

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

    // MARK: - Interactive Shell

    public func startShell(cols: Int, rows: Int) {
        guard let client else { return }

        let onOutput = self.onOutput
        let writer = self.shellWriter

        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )

        shellTask = Task.detached {
            do {
                try await client.withPTY(ptyRequest) { inbound, outbound in
                    writer.set(outbound)

                    for try await output in inbound {
                        let bytes: Data
                        switch output {
                        case .stdout(let buffer):
                            bytes = Data(buffer: buffer)
                        case .stderr(let buffer):
                            bytes = Data(buffer: buffer)
                        }
                        onOutput?(bytes)
                    }
                }
            } catch {
                // Shell session ended
            }

            writer.clear()
        }
    }

    public func execute(_ command: String) async throws -> String {
        guard let client else {
            throw SSHServiceError.notConnected
        }
        let buffer = try await client.executeCommand(command)
        return String(buffer: buffer)
    }

    public func disconnect() async {
        shellTask?.cancel()
        shellTask = nil
        shellWriter.clear()
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
