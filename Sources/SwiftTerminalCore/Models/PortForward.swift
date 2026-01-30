import Foundation

/// Direction of a port forward.
public enum ForwardType: String, Codable, Sendable, CaseIterable, Identifiable {
    /// -L localPort:remoteHost:remotePort
    case local
    /// -R remotePort:localHost:localPort
    case remote

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .local: "Local (-L)"
        case .remote: "Remote (-R)"
        }
    }

    public var systemImage: String {
        switch self {
        case .local: "arrow.right"
        case .remote: "arrow.left"
        }
    }
}

/// Saved port forward configuration attached to a server.
public struct PortForwardConfig: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var type: ForwardType
    public var localPort: Int
    public var remoteHost: String
    public var remotePort: Int
    public var label: String
    public var autoStart: Bool

    public init(
        id: UUID = UUID(),
        type: ForwardType = .local,
        localPort: Int = 3000,
        remoteHost: String = "127.0.0.1",
        remotePort: Int = 3000,
        label: String = "",
        autoStart: Bool = false
    ) {
        self.id = id
        self.type = type
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.label = label
        self.autoStart = autoStart
    }

    /// Human-readable description like "L 3000 -> 127.0.0.1:3000"
    public var summary: String {
        switch type {
        case .local:
            "L \(localPort) \u{2192} \(remoteHost):\(remotePort)"
        case .remote:
            "R \(remotePort) \u{2192} \(remoteHost):\(localPort)"
        }
    }
}

/// Runtime state for an active port forward.
@MainActor
public final class ActivePortForward: Identifiable, Observable {
    public let id: UUID
    public let config: PortForwardConfig
    public var task: Task<Void, Never>
    public var isActive: Bool

    public init(config: PortForwardConfig, task: Task<Void, Never>) {
        self.id = config.id
        self.config = config
        self.task = task
        self.isActive = true
    }

    public func stop() {
        task.cancel()
        isActive = false
    }
}
