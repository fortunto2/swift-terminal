#if canImport(UIKit)
import Foundation
import SwiftUI

/// Persisted info about a previous session for quick reconnect after app restart.
struct RecentSession: Codable, Identifiable {
    var id: UUID       // server ID
    var tmuxName: String
    var connectedAt: Date
}

/// Manages multiple concurrent SSH sessions with tab-style switching.
/// Persists recent session info for quick reconnect after app restart.
@MainActor
@Observable
public final class SessionManager {
    public private(set) var sessions: [Session] = []
    public var activeSessionID: UUID?
    private var nextIndex = 0

    // Persistence
    private static let recentsKey = "recentSessions"
    private(set) var recentServerIDs: [UUID] = []

    public init() {
        loadRecents()
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

    /// Server IDs that had recent sessions (for quick reconnect after restart).
    /// Filters out servers that already have active sessions.
    public func recentServersForReconnect(from allServers: [Server]) -> [Server] {
        let activeServerIDs = Set(sessions.map { $0.server.id })
        return recentServerIDs.compactMap { id in
            guard !activeServerIDs.contains(id) else { return nil }
            return allServers.first { $0.id == id }
        }
    }

    /// Create a new session for the given server and make it active.
    @discardableResult
    public func createSession(for server: Server) -> Session {
        let session = Session(server: server, index: nextIndex)
        nextIndex += 1
        sessions.append(session)
        activeSessionID = session.id
        saveRecents()
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

        // If we closed the active session, switch to the nearest remaining
        if activeSessionID == id {
            if sessions.isEmpty {
                activeSessionID = nil
            } else {
                let newIdx = min(idx, sessions.count - 1)
                activeSessionID = sessions[newIdx].id
            }
        }

        saveRecents()
    }

    /// Close all sessions.
    public func closeAll() {
        for session in sessions {
            Task { await session.disconnect() }
        }
        sessions.removeAll()
        activeSessionID = nil
        saveRecents()
    }

    // MARK: - Persistence (UserDefaults — recent server IDs for quick reconnect)

    private func saveRecents() {
        // Save unique server IDs of current + recent sessions (max 5)
        var ids = sessions.map { $0.server.id }
        // Append old recents that aren't already in the list
        for id in recentServerIDs where !ids.contains(id) {
            ids.append(id)
        }
        let capped = Array(ids.prefix(5))
        recentServerIDs = capped
        let strings = capped.map(\.uuidString)
        UserDefaults.standard.set(strings, forKey: Self.recentsKey)
    }

    private func loadRecents() {
        guard let strings = UserDefaults.standard.stringArray(forKey: Self.recentsKey) else { return }
        recentServerIDs = strings.compactMap { UUID(uuidString: $0) }
    }
}
#endif
