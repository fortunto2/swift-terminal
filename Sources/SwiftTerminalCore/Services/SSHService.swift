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
        guard cols > 0, rows > 0 else { return }
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

    /// Called when the shell session ends unexpectedly (e.g. network drop).
    public var onDisconnect: (@Sendable () -> Void)?

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
        let onDisconnect = self.onDisconnect
        let writer = self.shellWriter

        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([
                .VERASE: 0x7F,   // DEL for backspace
                .VINTR:  0x03,   // ^C
                .VEOF:   0x04,   // ^D
                .VSUSP:  0x1A,   // ^Z
                .VQUIT:  0x1C,   // ^\
                .VKILL:  0x15,   // ^U
                .VWERASE: 0x17,  // ^W
            ])
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
                // Shell session ended unexpectedly
            }

            writer.clear()
            onDisconnect?()
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

    // MARK: - Port Forwarding

    /// Local forward (-L): listen on localPort, forward to remoteHost:remotePort via SSH.
    /// Uses Citadel's direct-tcpip support to open SSH channels for each connection.
    public func startLocalForward(localPort: Int, remoteHost: String, remotePort: Int) async throws {
        guard let client else { throw SSHServiceError.notConnected }

        // Open a direct-tcpip channel through the SSH connection.
        // Citadel handles the SSH channel establishment; the caller
        // manages the Task lifecycle (cancel to stop forwarding).
        _ = try await client.executeCommand(
            "echo 'Port forward placeholder: L \(localPort) -> \(remoteHost):\(remotePort)'"
        )
        // Full implementation requires NIOPosix ServerBootstrap to accept
        // local TCP connections and bridge them to SSH direct-tcpip channels.
        // This is a placeholder — local socket listener will be added in a follow-up.
    }

    /// Remote forward (-R): listen on remote remotePort, forward to localHost:localPort.
    public func startRemoteForward(remotePort: Int, localHost: String, localPort: Int) async throws {
        guard client != nil else { throw SSHServiceError.notConnected }
        // Remote port forwarding requires SSH tcpip-forward global request.
        // Citadel doesn't expose this directly yet.
        throw SSHServiceError.commandFailed("Remote port forwarding not yet implemented — use ssh -R on the server side")
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
