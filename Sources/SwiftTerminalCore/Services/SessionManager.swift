import Foundation
import SwiftUI

/// Persisted snapshot of a session — saved to UserDefaults, restored on app launch.
private struct PersistedSession: Codable {
    var serverID: UUID
    var tmuxName: String
    var index: Int
}

/// Manages multiple concurrent SSH sessions with tab-style switching.
/// Persists session list so sessions auto-reconnect after app restart.
@MainActor
@Observable
public final class SessionManager {
    public private(set) var sessions: [Session] = []
    public var activeSessionID: UUID?
    private var nextIndex = 0
    private var hasRestored = false

    private static let storageKey = "persistedSessions"
    private static let indexKey = "sessionNextIndex"

    public init() {}

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

    /// Call once after ServerStore is available (e.g. from ServerListView.onAppear).
    /// Recreates Session objects from persisted data and auto-connects them.
    public func restoreSessionsIfNeeded(from store: ServerStore) {
        guard !hasRestored else { return }
        hasRestored = true

        nextIndex = UserDefaults.standard.integer(forKey: Self.indexKey)

        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let persisted = try? JSONDecoder().decode([PersistedSession].self, from: data),
              !persisted.isEmpty else { return }

        for p in persisted {
            guard let server = store.servers.first(where: { $0.id == p.serverID }) else { continue }
            // Create session with the saved tmux name and index
            let session = Session(server: server, index: p.index)
            sessions.append(session)
        }

        // Activate first restored session
        if let first = sessions.first {
            activeSessionID = first.id
        }

        // Auto-connect all restored sessions
        for session in sessions {
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

    /// Close and clean up a session.
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

    // MARK: - Persistence

    private func persist() {
        let persisted = sessions.map { session in
            PersistedSession(
                serverID: session.server.id,
                tmuxName: session.tmuxName,
                index: Int(session.tmuxName.replacingOccurrences(of: "st-", with: "")) ?? 0
            )
        }
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        UserDefaults.standard.set(nextIndex, forKey: Self.indexKey)
    }
}
