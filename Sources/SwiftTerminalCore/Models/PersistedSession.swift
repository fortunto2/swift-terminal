import Foundation
import SwiftData

/// SwiftData model for persisting session state across app restarts.
/// Replaces the previous UserDefaults-based PersistedSession struct.
@Model
public final class PersistedSession {
    public var serverID: UUID
    public var tmuxName: String
    public var index: Int
    public var createdAt: Date
    /// Whether this session was discovered from a pre-existing tmux session (not created by us).
    public var isDiscovered: Bool

    public init(serverID: UUID, tmuxName: String, index: Int, createdAt: Date = .now, isDiscovered: Bool = false) {
        self.serverID = serverID
        self.tmuxName = tmuxName
        self.index = index
        self.createdAt = createdAt
        self.isDiscovered = isDiscovered
    }
}
