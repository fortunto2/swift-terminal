import Foundation
import SwiftUI
import SwiftData

/// Manages multiple concurrent SSH sessions with tab-style switching.
/// Persists session list via SwiftData so sessions auto-reconnect after app restart.
@MainActor
@Observable
public final class SessionManager {
    public internal(set) var sessions: [Session] = []
    public var activeSessionID: UUID?
    private var nextIndex = 0
    private var hasRestored = false

    // MARK: - Tmux Discovery

    /// Info about a discovered tmux session on the remote server.
    public struct TmuxSessionInfo: Identifiable, Equatable {
        /// Identified by tmux name, not a fresh UUID. The discovery task re-runs every time the
        /// terminal view reappears, so a per-struct UUID left the picker's selection pointing at
        /// a replaced array: every row drew unchecked while the toolbar still counted two, and
        /// "Open" adopted nothing. Names are unique within a tmux server, so they are the id.
        public var id: String { name }
        public let name: String
        public let windowCount: Int
        public let isAttached: Bool
        /// Whether this is one of our managed sessions (st-N pattern).
        public let isOurs: Bool
    }

    /// Discovered tmux sessions available for adoption.
    public var discoveredTmuxSessions: [TmuxSessionInfo] = []
    /// Whether the tmux picker sheet is visible.
    public var showTmuxPicker = false
    /// The server the discovered sessions belong to.
    public var tmuxPickerServer: Server?

    // MARK: - Tmux Session List (on-demand)

    /// A remote tmux session with info about whether it's already open locally.
    public struct RemoteTmuxSession: Identifiable {
        /// Same reasoning as TmuxSessionInfo.id — the name is the stable identity.
        public var id: String { name }
        public let name: String
        public let windowCount: Int
        public let isAttached: Bool
        /// ID of local Session if already open as a tab, nil if not.
        public var localSessionID: UUID?
        public var isOpen: Bool { localSessionID != nil }
    }

    /// All remote tmux sessions fetched on-demand.
    public var remoteTmuxSessions: [RemoteTmuxSession] = []
    /// Whether the tmux session list sheet is visible.
    public var showTmuxSessionList = false
    /// Whether a fetch is in progress.
    public var isFetchingTmuxSessions = false

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

                // Persisted names for this server (includes discovered sessions)
                let cachedNames = Set(
                    persisted.filter { $0.serverID == server.id }.map(\.tmuxName)
                )

                // Get remote tmux sessions
                var targetNames: [String]
                if probeConnected {
                    do {
                        let output = try await probe.execute(
                            SSHService.tmuxListNames
                        )
                        targetNames = output.split(separator: "\n")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { $0.hasPrefix("st-") || cachedNames.contains($0) }
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

                // Build a set of discovered tmux names for lookup
                let discoveredNames = Set(
                    persisted.filter { $0.serverID == server.id && $0.isDiscovered }.map(\.tmuxName)
                )

                // Create sessions for each target
                for name in targetNames {
                    // Skip if already exists
                    guard !sessions.contains(where: { $0.server.id == server.id && $0.tmuxName == name }) else { continue }

                    let session: Session
                    if discoveredNames.contains(name) {
                        // Restore as discovered session (custom tmux name)
                        session = Session(server: server, tmuxSessionName: name)
                    } else if let idx = Int(name.replacingOccurrences(of: "st-", with: "")) {
                        session = Session(server: server, index: idx)
                        if idx >= nextIndex { nextIndex = idx + 1 }
                    } else {
                        continue
                    }
                    sessions.append(session)
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
                    SSHService.tmuxListNames
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

    // MARK: - Tmux Session Discovery

    /// Discover all tmux sessions on the server (not just st-* ones).
    /// If user-created sessions are found, populates `discoveredTmuxSessions` and shows picker.
    public func discoverAllTmuxSessions(via session: Session, store: ServerStore) {
        guard session.state.isConnected else { return }
        let server = session.server

        Task {
            let infos: [TmuxSessionInfo]
            do {
                let output = try await session.sshService.execute(SSHService.tmuxListDetailed)
                infos = SSHService.TmuxListing.parse(output).map { entry in
                    TmuxSessionInfo(
                        name: entry.name,
                        windowCount: entry.windowCount,
                        isAttached: entry.isAttached,
                        isOurs: entry.name.hasPrefix("st-")
                    )
                }
            } catch {
                #if DEBUG
                print("[SessionManager] tmux discovery failed: \(error)")
                #endif
                return
            }

            // Filter to non-st-* sessions that aren't already open as tabs
            let localNames = Set(sessions.filter { $0.server.id == server.id }.map(\.tmuxName))
            let userSessions = infos.filter { !$0.isOurs && !localNames.contains($0.name) }

            guard !userSessions.isEmpty else {
                #if DEBUG
                print("[SessionManager] no user tmux sessions to discover")
                #endif
                return
            }

            #if DEBUG
            print("[SessionManager] discovered \(userSessions.count) user tmux sessions: \(userSessions.map(\.name))")
            #endif

            discoveredTmuxSessions = userSessions
            tmuxPickerServer = server
            showTmuxPicker = true
        }
    }

    /// Adopt selected discovered sessions — creates Session objects and connects them.
    public func adoptDiscoveredSessions(_ selected: [TmuxSessionInfo], using store: ServerStore) {
        guard let server = tmuxPickerServer else { return }

        let autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect") == nil
            || UserDefaults.standard.bool(forKey: "autoReconnect")

        for info in selected {
            // Skip if already exists
            guard !sessions.contains(where: { $0.server.id == server.id && $0.tmuxName == info.name }) else { continue }

            let session = Session(server: server, tmuxSessionName: info.name)
            sessions.append(session)

            session.state = .connecting
            Task {
                session.setupDisconnectHandler(using: store, autoReconnect: autoReconnect)
                await session.connect(using: store)
            }
        }

        persist()
        dismissTmuxPicker()
    }

    /// Dismiss the tmux picker without adopting.
    public func dismissTmuxPicker() {
        showTmuxPicker = false
        discoveredTmuxSessions = []
        tmuxPickerServer = nil
    }

    // MARK: - Tmux Session List Actions

    /// Fetch all tmux sessions on the remote server.
    /// Uses the existing SSH connection's exec channel (SSH2 supports multiple channels).
    public func fetchRemoteTmuxSessions(via session: Session) {
        guard session.state.isConnected else { return }
        let server = session.server
        remoteTmuxSessions = []
        isFetchingTmuxSessions = true

        Task {
            defer { isFetchingTmuxSessions = false }

            let infos: [SSHService.TmuxListing.Entry]
            do {
                let output = try await session.sshService.execute(SSHService.tmuxListDetailed)
                infos = SSHService.TmuxListing.parse(output)
            } catch {
                #if DEBUG
                print("[SessionManager] fetchRemoteTmuxSessions failed: \(error)")
                #endif
                remoteTmuxSessions = []
                return
            }

            // Build list, matching against local sessions for this server
            let localForServer = sessions.filter { $0.server.id == server.id }
            remoteTmuxSessions = infos.map { entry in
                RemoteTmuxSession(
                    name: entry.name,
                    windowCount: entry.windowCount,
                    isAttached: entry.isAttached,
                    localSessionID: localForServer.first { $0.tmuxName == entry.name }?.id
                )
            }

            #if DEBUG
            print("[SessionManager] fetched \(remoteTmuxSessions.count) remote tmux sessions")
            #endif
        }
    }

    /// Switch to a local tab that's already attached to the given tmux session.
    public func switchToTmuxSession(localID: UUID) {
        switchTo(localID)
        showTmuxSessionList = false
    }

    /// Attach to a remote tmux session by creating a new local Session tab.
    public func attachRemoteTmuxSession(name: String, server: Server, store: ServerStore) {
        // Don't duplicate
        guard !sessions.contains(where: { $0.server.id == server.id && $0.tmuxName == name }) else { return }

        let session = Session(server: server, tmuxSessionName: name)
        sessions.append(session)
        activeSessionID = session.id
        persist()

        let autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect") == nil
            || UserDefaults.standard.bool(forKey: "autoReconnect")

        session.state = .connecting
        Task {
            session.setupDisconnectHandler(using: store, autoReconnect: autoReconnect)
            await session.connect(using: store)
        }

        showTmuxSessionList = false
    }

    /// Kill a remote tmux session AND close the local tab if open.
    public func killTmuxSession(name: String, via session: Session) {
        let server = session.server

        // Kill remote tmux session
        Task {
            do {
                _ = try await session.sshService.execute(
                    SSHService.tmuxExec("kill-session -t \(name) 2>/dev/null")
                )
                #if DEBUG
                print("[SessionManager] killed remote tmux session: \(name)")
                #endif
            } catch {
                #if DEBUG
                print("[SessionManager] kill tmux session failed: \(error)")
                #endif
            }
        }

        // Close local tab if it exists
        if let localSession = sessions.first(where: { $0.server.id == server.id && $0.tmuxName == name }) {
            closeSession(localSession.id)
        }

        // Remove from the list UI
        remoteTmuxSessions.removeAll { $0.name == name }
    }

    /// Close a local tab and kill the tmux session on the server.
    public func closeAndKillSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let tmuxName = session.tmuxName

        // Kill remote tmux
        Task {
            do {
                _ = try await session.sshService.execute(
                    SSHService.tmuxExec("kill-session -t \(tmuxName) 2>/dev/null")
                )
            } catch {
                // Best effort
            }
        }

        closeSession(id)
    }

    /// Dismiss the tmux session list.
    public func dismissTmuxSessionList() {
        showTmuxSessionList = false
        remoteTmuxSessions = []
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
                createdAt: session.createdAt,
                isDiscovered: session.isDiscovered
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
