import Foundation
import SwiftUI
import SwiftTerm
import QuartzCore

#if DEBUG
private func stLog(_ msg: String) {
    print("[session] \(msg)")
}
#else
@inline(__always) private func stLog(_ msg: String) {}
#endif

/// Connection lifecycle state for a session.
public enum SessionState: Sendable {
    case connecting
    case connected
    case disconnected
    case reconnecting(attempt: Int)
    case failed(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .reconnecting(let n): "Reconnecting (\(n))..."
        case .failed(let msg): "Failed: \(msg)"
        }
    }

    public var color: SwiftUI.Color {
        switch self {
        case .connecting: .yellow
        case .connected: .green
        case .disconnected: .gray
        case .reconnecting: .orange
        case .failed: .red
        }
    }
}

/// A single SSH terminal session tied to a server.
@MainActor
@Observable
public final class Session: Identifiable {
    public let id: UUID
    public let server: Server
    public let sshService: SSHService
    public var state: SessionState = .connecting
    public let tmuxName: String
    public var createdAt = Date.now
    public var lastActivity = Date.now
    /// Whether this session was discovered from an existing tmux session (not created by us).
    public var isDiscovered: Bool
    public var activeForwards: [ActivePortForward] = []
    var reconnectTask: Task<Void, Never>?

    /// Reusable SwiftTerm UIView — kept alive across SwiftUI view updates.
    public var terminalView: SwiftTerm.TerminalView?

    /// Whether the shell has been started and onOutput is wired.
    /// Prevents double-starting on tab switches.
    public var shellStarted = false

    public init(server: Server, index: Int) {
        self.id = UUID()
        self.server = server
        self.sshService = SSHService()
        self.tmuxName = "st-\(index)"
        self.isDiscovered = false
        stLog("init session \(tmuxName) for \(server.name)")
    }

    /// Init for discovered (pre-existing) tmux sessions with custom names.
    public init(server: Server, tmuxSessionName: String) {
        self.id = UUID()
        self.server = server
        self.sshService = SSHService()
        self.tmuxName = tmuxSessionName
        self.isDiscovered = true
        stLog("init discovered session \(tmuxName) for \(server.name)")
    }

    // MARK: - Connect

    public func connect(using store: ServerStore) async {
        stLog("\(tmuxName) connect() authMethod=\(server.authMethod)")
        state = .connecting

        switch server.authMethod {
        case .password:
            // Password requires UI prompt — handled by the view layer
            break
        case .key:
            await connectWithKey(using: store)
        case .agent:
            state = .failed("SSH Agent not yet supported")
        }
    }

    public func connectWithPassword(_ password: String) async {
        stLog("\(tmuxName) connectWithPassword")
        state = .connecting
        do {
            try await sshService.connect(to: server, password: password)
            state = .connected
            lastActivity = .now
            stLog("\(tmuxName) password auth OK")
        } catch {
            stLog("\(tmuxName) password auth FAIL: \(error)")
            state = .failed(error.localizedDescription)
        }
    }

    private func connectWithKey(using store: ServerStore) async {
        guard let keyID = server.keyID,
              let sshKey = store.key(for: keyID) else {
            stLog("\(tmuxName) no SSH key assigned")
            state = .failed("No SSH key assigned to this server")
            return
        }

        do {
            guard let privateKeyData = try KeychainService.load(key: sshKey.keychainTag) else {
                stLog("\(tmuxName) key not in keychain")
                state = .failed("Private key not found in Keychain")
                return
            }

            try await sshService.connect(
                to: server,
                privateKeyData: privateKeyData,
                keyType: sshKey.keyType
            )
            state = .connected
            lastActivity = .now
            stLog("\(tmuxName) key auth OK")
        } catch {
            stLog("\(tmuxName) key auth FAIL: \(error)")
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Shell lifecycle

    /// Start shell + wire onOutput to the cached terminalView.
    /// Called from TerminalViewRepresentable.makeUIView on first creation,
    /// and from reconnect after SSH re-established.
    public func startShellIfNeeded() {
        guard !shellStarted else {
            stLog("\(tmuxName) startShellIfNeeded: ALREADY STARTED, skipping")
            return
        }
        guard let tv = terminalView else {
            stLog("\(tmuxName) startShellIfNeeded: no terminalView!")
            return
        }
        guard sshService.isConnected else {
            stLog("\(tmuxName) startShellIfNeeded: not connected")
            return
        }

        let cols = tv.getTerminal().cols
        let rows = tv.getTerminal().rows
        stLog("\(tmuxName) startShell cols=\(cols) rows=\(rows)")

        // Mark as started FIRST to prevent double-start races
        shellStarted = true

        // Wire output → terminal feed
        sshService.onOutput = { [weak tv] data in
            let bytes = Array(data)
            DispatchQueue.main.async {
                guard let tv else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                tv.feed(byteArray: ArraySlice(bytes))
                CATransaction.commit()
            }
        }

        sshService.startShell(cols: cols, rows: rows)

        // tmux attach after shell has time to initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if self.isDiscovered {
                self.sendTmuxAttachExisting()
            } else {
                self.sendTmuxAttach()
            }
        }
    }

    /// Restart shell after reconnect — re-wires onOutput, starts new PTY,
    /// then attaches to existing tmux session.
    public func restartShellAfterReconnect() {
        guard let tv = terminalView else {
            stLog("\(tmuxName) restartShell: no terminalView!")
            return
        }
        guard sshService.isConnected else {
            stLog("\(tmuxName) restartShell: not connected")
            return
        }

        let cols = tv.getTerminal().cols
        let rows = tv.getTerminal().rows
        stLog("\(tmuxName) restartShell cols=\(cols) rows=\(rows)")

        // Re-wire output → terminal
        sshService.onOutput = { [weak tv] data in
            let bytes = Array(data)
            DispatchQueue.main.async {
                guard let tv else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                tv.feed(byteArray: ArraySlice(bytes))
                CATransaction.commit()
            }
        }

        sshService.startShell(cols: cols, rows: rows)
        shellStarted = true

        // Re-attach to tmux (session should still be alive on server)
        // Always use sendTmuxReattach (new-session -A) — works for both st-* and discovered.
        // This handles the case where the session was killed while disconnected.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendTmuxReattach()
        }

        // Re-start auto-forwards
        startAutoForwards()
    }

    // MARK: - Auto-tmux

    private var isTmuxEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoTmux") == nil
            || UserDefaults.standard.bool(forKey: "autoTmux")
    }

    /// Full install-check script — only used on first connection to a server.
    public static let tmuxInstallScript = """
        if ! command -v tmux >/dev/null 2>&1; then \
        echo '[st] tmux not found, installing...'; \
        if command -v apt-get >/dev/null 2>&1; then sudo apt-get update -qq && sudo apt-get install -y -qq tmux; \
        elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y -q tmux; \
        elif command -v yum >/dev/null 2>&1; then sudo yum install -y -q tmux; \
        elif command -v apk >/dev/null 2>&1; then sudo apk add --quiet tmux; \
        elif command -v brew >/dev/null 2>&1; then brew install tmux; \
        elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --noconfirm tmux; \
        else echo '[st] cannot install tmux: unknown package manager'; fi; \
        fi
        """

    /// Build the tmux command, with install check only on first connection to this server.
    private func tmuxCommand(_ tmuxCmd: String, store: ServerStore?) -> String {
        if server.tmuxVerified == true {
            return tmuxCmd
        }
        // Mark as verified and persist
        if let store {
            var updated = server
            updated.tmuxVerified = true
            store.updateServer(updated)
        }
        return "\(Session.tmuxInstallScript); \(tmuxCmd)"
    }

    private var tmuxAttached = false

    public func sendTmuxAttach(store: ServerStore? = nil) {
        guard isTmuxEnabled else {
            stLog("\(tmuxName) tmux disabled, skip attach")
            return
        }
        guard !tmuxAttached else {
            stLog("\(tmuxName) sendTmuxAttach: ALREADY ATTACHED, skipping")
            return
        }
        tmuxAttached = true
        let tmuxCmd = "tmux new-session -A -s \(tmuxName) \\; set mouse on \\; set remain-on-exit on"
        stLog("\(tmuxName) sendTmuxAttach: \(tmuxCmd)")
        let cmd = tmuxCommand(tmuxCmd, store: store)
        sshService.shellWriter.write(Data((cmd + "\n").utf8))
    }

    public func sendTmuxReattach(store: ServerStore? = nil) {
        guard isTmuxEnabled else {
            stLog("\(tmuxName) tmux disabled, skip reattach")
            return
        }
        tmuxAttached = true
        stLog("\(tmuxName) sendTmuxReattach")
        // Use new-session -A (create-or-attach) for both st-* and discovered sessions.
        // This handles the case where the tmux session was killed while we were disconnected.
        let cmd = tmuxCommand(
            "tmux new-session -A -s \(tmuxName) \\; set mouse on \\; set remain-on-exit on",
            store: store
        )
        sshService.shellWriter.write(Data((cmd + "\n").utf8))
    }

    /// Attach to a pre-existing (discovered) tmux session — uses attach-session, not new-session.
    public func sendTmuxAttachExisting() {
        guard isTmuxEnabled else {
            stLog("\(tmuxName) tmux disabled, skip attach existing")
            return
        }
        guard !tmuxAttached else {
            stLog("\(tmuxName) sendTmuxAttachExisting: ALREADY ATTACHED, skipping")
            return
        }
        tmuxAttached = true
        let cmd = "tmux new-session -A -s \(tmuxName) \\; set mouse on"
        stLog("\(tmuxName) sendTmuxAttachExisting: \(cmd)")
        sshService.shellWriter.write(Data((cmd + "\n").utf8))
    }

    // MARK: - Reconnect

    public func startAutoReconnect(using store: ServerStore) {
        reconnectTask?.cancel()
        var attempt = 0
        stLog("\(tmuxName) startAutoReconnect")
        reconnectTask = Task { [weak self] in
            let maxAttempts = 15
            while attempt < maxAttempts, !Task.isCancelled {
                attempt += 1
                self?.state = .reconnecting(attempt: attempt)
                stLog("\(self?.tmuxName ?? "?") reconnect attempt \(attempt)")

                // Exponential backoff capped at 30s: 1, 2, 4, 8, 16, 30, 30, ...
                let backoff = min(pow(2.0, Double(attempt - 1)), 30.0)
                let delay = UInt64(backoff) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { return }

                await self?.sshService.disconnect()
                self?.shellStarted = false
                self?.tmuxAttached = false

                do {
                    try await self?.reconnectSSH(using: store)
                    stLog("\(self?.tmuxName ?? "?") reconnect SSH OK, restarting shell")
                    self?.state = .connected
                    self?.lastActivity = .now
                    // Critical: restart shell + re-wire output after reconnect
                    self?.restartShellAfterReconnect()
                    return
                } catch {
                    stLog("\(self?.tmuxName ?? "?") reconnect attempt \(attempt) FAIL: \(error)")
                }
            }

            if !Task.isCancelled {
                self?.state = .failed("Reconnect failed after \(maxAttempts) attempts")
            }
        }
    }

    private func reconnectSSH(using store: ServerStore) async throws {
        switch server.authMethod {
        case .key:
            guard let keyID = server.keyID,
                  let sshKey = store.key(for: keyID),
                  let privateKeyData = try KeychainService.load(key: sshKey.keychainTag) else {
                throw SSHServiceError.authenticationFailed
            }
            try await sshService.connect(
                to: server,
                privateKeyData: privateKeyData,
                keyType: sshKey.keyType
            )
        default:
            throw SSHServiceError.authenticationFailed
        }
    }

    // MARK: - Disconnect Handler

    public func setupDisconnectHandler(using store: ServerStore, autoReconnect: Bool) {
        sshService.onDisconnect = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                stLog("\(self.tmuxName) onDisconnect fired, state=\(self.state), autoReconnect=\(autoReconnect)")
                // Only react if we were connected (not if already disconnecting/failed)
                guard self.state.isConnected || {
                    if case .reconnecting = self.state { return true }
                    return false
                }() else { return }
                self.shellStarted = false
                self.tmuxAttached = false
                if autoReconnect {
                    self.startAutoReconnect(using: store)
                } else {
                    self.state = .failed("Connection lost")
                }
            }
        }
    }

    // MARK: - Port Forwards

    public func startForward(_ config: PortForwardConfig) {
        let service = sshService
        let task = Task<Void, Never> {
            do {
                switch config.type {
                case .local:
                    try await service.startLocalForward(
                        localPort: config.localPort,
                        remoteHost: config.remoteHost,
                        remotePort: config.remotePort
                    )
                case .remote:
                    try await service.startRemoteForward(
                        remotePort: config.remotePort,
                        localHost: config.remoteHost,
                        localPort: config.localPort
                    )
                }
            } catch {
                // Forward failed
            }
        }
        let active = ActivePortForward(config: config, task: task)
        activeForwards.append(active)
    }

    public func stopForward(_ id: UUID) {
        if let idx = activeForwards.firstIndex(where: { $0.id == id }) {
            activeForwards[idx].stop()
            activeForwards.remove(at: idx)
        }
    }

    public func startAutoForwards() {
        for config in server.portForwards where config.autoStart {
            if !activeForwards.contains(where: { $0.config.id == config.id }) {
                startForward(config)
            }
        }
    }

    // MARK: - Cleanup

    public func disconnect() async {
        stLog("\(tmuxName) disconnect()")
        reconnectTask?.cancel()
        reconnectTask = nil
        for fwd in activeForwards { fwd.stop() }
        activeForwards.removeAll()
        shellStarted = false
        tmuxAttached = false
        await sshService.disconnect()
        state = .disconnected
    }
}
