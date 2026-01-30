import Foundation
import SwiftUI
import SwiftData

/// Manages multiple concurrent SSH sessions with tab-style switching.
/// Persists session list via SwiftData so sessions auto-reconnect after app restart.
@MainActor
@Observable
public final class SessionManager {
    public private(set) var sessions: [Session] = []
    public var activeSessionID: UUID?
    private var nextIndex = 0
    private var hasRestored = false

    private var modelContext: ModelContext?

    public init() {}

    /// Set the SwiftData model context (called from view layer after modelContainer is available).
    public func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    /// The currently visible session.
    public var activeSession: Session? {
        guard let id = activeSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    /// Number of connected sessions.
    public var connectedCount: Int {
        sessions.filter { $0.state.isConnected }.count
    }

    /// Sessions for a specific server.
    public func activeSessions(for server: Server) -> [Session] {
        sessions.filter { $0.server.id == server.id && $0.state.isConnected }
    }

    /// Whether any session exists for the given server (regardless of state).
    public func hasSessions(for server: Server) -> Bool {
        sessions.contains { $0.server.id == server.id }
    }

    // MARK: - Restore persisted sessions

    /// Call once after ServerStore is available (e.g. from MacMainView.onAppear).
    /// Flow per server:
    /// 1. SSH connect (probe) to check server tmux state
    /// 2. Build session list from server tmux (source of truth)
    /// 3. Connect all sessions
    public func restoreSessionsIfNeeded(from store: ServerStore) {
        guard !hasRestored else { return }
        hasRestored = true

        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<PersistedSession>(
            sortBy: [SortDescriptor(\.index)]
        )
        guard let persisted = try? context.fetch(descriptor),
              !persisted.isEmpty else { return }

        nextIndex = (persisted.map(\.index).max() ?? 0) + 1

        // Group by server
        var serverGroups: [UUID: Server] = [:]
        for p in persisted {
            guard let server = store.servers.first(where: { $0.id == p.serverID }) else { continue }
            serverGroups[server.id] = server
        }

        let autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect") == nil
            || UserDefaults.standard.bool(forKey: "autoReconnect")

        for (_, server) in serverGroups {
            // Create a temporary probe to query server
            let probe = SSHService()

            Task {
                // Try to connect probe
                var probeConnected = false
                do {
                    if server.authMethod == .key,
                       let keyID = server.keyID,
                       let sshKey = store.key(for: keyID),
                       let privateKeyData = try KeychainService.load(key: sshKey.keychainTag) {
                        try await probe.connect(to: server, privateKeyData: privateKeyData, keyType: sshKey.keyType)
                        probeConnected = true
                    }
                } catch {
                    #if DEBUG
                    print("[SessionManager] probe connect failed: \(error)")
                    #endif
                }

                // Get remote tmux sessions
                var targetNames: [String]
                if probeConnected {
                    do {
                        let output = try await probe.execute(
                            "tmux list-sessions -F '#{session_name}' 2>/dev/null"
                        )
                        targetNames = output.split(separator: "\n")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { $0.hasPrefix("st-") }
                            .sorted()
                        #if DEBUG
                        print("[SessionManager] server tmux for \(server.name): \(targetNames)")
                        #endif
                    } catch {
                        // tmux not running — fall back to cache
                        targetNames = persisted
                            .filter { $0.serverID == server.id }
                            .map(\.tmuxName)
                            .sorted()
                        #if DEBUG
                        print("[SessionManager] tmux query failed, using cache: \(targetNames)")
                        #endif
                    }
                    await probe.disconnect()
                } else {
                    // Can't connect — fall back to cache
                    targetNames = persisted
                        .filter { $0.serverID == server.id }
                        .map(\.tmuxName)
                        .sorted()
                }

                // If server has no tmux at all, use cache (they'll be created on attach)
                if targetNames.isEmpty {
                    targetNames = persisted
                        .filter { $0.serverID == server.id }
                        .map(\.tmuxName)
                        .sorted()
                }

                #if DEBUG
                print("[SessionManager] restoring sessions: \(targetNames)")
                #endif

                // Create sessions for each target
                for name in targetNames {
                    guard let idx = Int(name.replacingOccurrences(of: "st-", with: "")) else { continue }
                    // Skip if already exists
                    guard !sessions.contains(where: { $0.server.id == server.id && $0.tmuxName == name }) else { continue }

                    let session = Session(server: server, index: idx)
                    sessions.append(session)
                    if idx >= nextIndex { nextIndex = idx + 1 }
                    session.state = .connecting

                    Task {
                        session.setupDisconnectHandler(using: store, autoReconnect: autoReconnect)
                        await session.connect(using: store)
                    }
                }

                if activeSessionID == nil, let first = sessions.first {
                    activeSessionID = first.id
                }

                syncedServerIDs.insert(server.id)
                persist()
            }
        }
    }

    // MARK: - Session lifecycle

    /// Create a new session for the given server and make it active.
    @discardableResult
    public func createSession(for server: Server) -> Session {
        let session = Session(server: server, index: nextIndex)
        nextIndex += 1
        sessions.append(session)
        activeSessionID = session.id
        persist()
        return session
    }

    /// Switch the active tab.
    public func switchTo(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
    }

    /// Disconnect a session but keep it in the list for reconnecting later.
    public func disconnectSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        Task {
            await session.disconnect()
        }
    }

    /// Reconnect a previously disconnected session.
    public func reconnectSession(_ id: UUID, using store: ServerStore) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        guard !session.state.isConnected else { return }
        session.state = .connecting
        Task {
            session.setupDisconnectHandler(
                using: store,
                autoReconnect: UserDefaults.standard.object(forKey: "autoReconnect") == nil
                    || UserDefaults.standard.bool(forKey: "autoReconnect")
            )
            await session.connect(using: store)
        }
    }

    /// Close and remove a session entirely.
    public func closeSession(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[idx]

        Task {
            await session.disconnect()
        }

        sessions.remove(at: idx)

        if activeSessionID == id {
            if sessions.isEmpty {
                activeSessionID = nil
            } else {
                let newIdx = min(idx, sessions.count - 1)
                activeSessionID = sessions[newIdx].id
            }
        }

        persist()
    }

    /// Close all sessions.
    public func closeAll() {
        for session in sessions {
            Task { await session.disconnect() }
        }
        sessions.removeAll()
        activeSessionID = nil
        persist()
    }

    // MARK: - Tmux Sync

    /// After a session connects, sync local tabs with actual tmux sessions on the server.
    /// Server is source of truth:
    /// - Adopt orphaned `st-*` tmux sessions not in our list
    /// - Remove local sessions whose tmux no longer exists on server
    /// Runs once per server per app launch.
    private var syncedServerIDs: Set<UUID> = []

    public func syncRemoteTmuxSessions(via session: Session, store: ServerStore) {
        guard session.state.isConnected else { return }
        let server = session.server

        // Only sync once per server per launch
        guard !syncedServerIDs.contains(server.id) else { return }
        syncedServerIDs.insert(server.id)

        Task {
            let remoteNames: Set<String>
            do {
                let output = try await session.sshService.execute(
                    "tmux list-sessions -F '#{session_name}' 2>/dev/null"
                )
                remoteNames = Set(
                    output
                        .split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { $0.hasPrefix("st-") }
                )
            } catch {
                #if DEBUG
                print("[SessionManager] tmux sync failed: \(error)")
                #endif
                return
            }

            #if DEBUG
            print("[SessionManager] remote tmux sessions: \(remoteNames.sorted())")
            #endif

            let localForServer = sessions.filter { $0.server.id == server.id }
            let localNames = Set(localForServer.map(\.tmuxName))
            var changed = false

            // 1. Remove local sessions whose tmux doesn't exist on server
            let orphanedLocal = localForServer.filter { !remoteNames.contains($0.tmuxName) }
            for orphan in orphanedLocal {
                #if DEBUG
                print("[SessionManager] pruning local session \(orphan.tmuxName) — not on server")
                #endif
                if let idx = sessions.firstIndex(where: { $0.id == orphan.id }) {
                    Task { await orphan.disconnect() }
                    sessions.remove(at: idx)
                    if activeSessionID == orphan.id {
                        activeSessionID = sessions.first?.id
                    }
                    changed = true
                }
            }

            // 2. Adopt remote tmux sessions not in our local list
            for name in remoteNames.sorted() {
                guard !localNames.contains(name) else { continue }
                guard let idx = Int(name.replacingOccurrences(of: "st-", with: "")) else { continue }

                #if DEBUG
                print("[SessionManager] adopting orphaned tmux: \(name) on \(server.name)")
                #endif

                let newSession = Session(server: server, index: idx)
                sessions.append(newSession)
                changed = true

                if idx >= nextIndex {
                    nextIndex = idx + 1
                }

                newSession.state = .connecting
                Task {
                    newSession.setupDisconnectHandler(
                        using: store,
                        autoReconnect: UserDefaults.standard.object(forKey: "autoReconnect") == nil
                            || UserDefaults.standard.bool(forKey: "autoReconnect")
                    )
                    await newSession.connect(using: store)
                }
            }

            if changed {
                persist()
            }
        }
    }

    // MARK: - Persistence (SwiftData)

    private func persist() {
        guard let context = modelContext else {
            #if DEBUG
            print("[SessionManager] persist() skipped — no modelContext")
            #endif
            return
        }

        // Delete all existing persisted sessions
        let descriptor = FetchDescriptor<PersistedSession>()
        if let existing = try? context.fetch(descriptor) {
            for item in existing {
                context.delete(item)
            }
        }

        // Insert current sessions
        for session in sessions {
            let persisted = PersistedSession(
                serverID: session.server.id,
                tmuxName: session.tmuxName,
                index: Int(session.tmuxName.replacingOccurrences(of: "st-", with: "")) ?? 0,
                createdAt: session.createdAt
            )
            context.insert(persisted)
        }

        do {
            try context.save()
            #if DEBUG
            print("[SessionManager] persisted \(sessions.count) sessions")
            #endif
        } catch {
            #if DEBUG
            print("[SessionManager] persist save error: \(error)")
            #endif
        }
    }
}
