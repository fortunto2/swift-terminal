import Foundation

/// Authentication method for SSH connections.
public enum AuthMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case password
    case key
    case agent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .password: "Password"
        case .key: "SSH Key"
        case .agent: "SSH Agent"
        }
    }

    public var systemImage: String {
        switch self {
        case .password: "lock.fill"
        case .key: "key.fill"
        case .agent: "person.badge.key.fill"
        }
    }
}

/// A saved SSH server configuration.
public struct Server: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var authMethod: AuthMethod
    public var keyID: UUID?
    public var tags: [String]
    public var createdAt: Date
    public var lastConnected: Date?
    public var portForwards: [PortForwardConfig]
    /// Whether tmux has been verified/installed on this server.
    /// nil = not checked yet (old data or new server).
    public var tmuxVerified: Bool?

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String = "root",
        authMethod: AuthMethod = .key,
        keyID: UUID? = nil,
        tags: [String] = [],
        createdAt: Date = .now,
        lastConnected: Date? = nil,
        portForwards: [PortForwardConfig] = [],
        tmuxVerified: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.keyID = keyID
        self.tags = tags
        self.createdAt = createdAt
        self.lastConnected = lastConnected
        self.portForwards = portForwards
        self.tmuxVerified = tmuxVerified
    }
}

extension Server {
    /// Display string for the connection (user@host:port).
    public var connectionString: String {
        if port == 22 {
            "\(username)@\(host)"
        } else {
            "\(username)@\(host):\(port)"
        }
    }

    /// Sample servers for previews and testing.
    public static let preview = Server(
        name: "Dev Server",
        host: "192.168.1.100",
        username: "deploy",
        tags: ["dev", "claude"]
    )

    public static let previewList: [Server] = [
        Server(name: "Production", host: "prod.example.com", port: 2222, username: "deploy", tags: ["prod"]),
        Server(name: "Staging", host: "staging.example.com", username: "deploy", tags: ["staging"]),
        Server(name: "Dev Box", host: "192.168.1.50", username: "deploy", tags: ["dev", "claude"]),
    ]
}
