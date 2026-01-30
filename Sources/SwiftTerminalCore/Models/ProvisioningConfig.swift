import Foundation

/// Cloud provider for VPS provisioning.
public enum CloudProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    public case hetzner
    public case digitalOcean
    public case linode
    public case vultr
    public case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hetzner: "Hetzner"
        case .digitalOcean: "DigitalOcean"
        case .linode: "Linode"
        case .vultr: "Vultr"
        case .custom: "Custom Server"
        }
    }

    var iconName: String {
        switch self {
        case .hetzner: "h.square.fill"
        case .digitalOcean: "drop.fill"
        case .linode: "l.square.fill"
        case .vultr: "v.square.fill"
        case .custom: "server.rack"
        }
    }
}

/// Feature that can be installed during provisioning.
public enum ProvisioningFeature: String, Codable, Sendable, CaseIterable, Identifiable {
    public case securityHardening
    public case claudeCode
    public case devTools
    public case docker
    public case uv
    public case bun

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .securityHardening: "Security Hardening"
        case .claudeCode: "Claude Code"
        case .devTools: "Dev Tools (ripgrep, tmux, git)"
        case .docker: "Docker"
        case .uv: "uv (Python)"
        case .bun: "Bun (JS Runtime)"
        }
    }

    var description: String {
        switch self {
        case .securityHardening: "Create deploy user, harden SSH, install fail2ban, configure UFW"
        case .claudeCode: "Install Claude Code CLI with ripgrep & tmux"
        case .devTools: "Install ripgrep, tmux, git, and other essentials"
        case .docker: "Install Docker Engine and Docker Compose"
        case .uv: "Install uv — fast Python package manager"
        case .bun: "Install Bun — fast JavaScript runtime"
        }
    }

    var systemImage: String {
        switch self {
        case .securityHardening: "shield.checkered"
        case .claudeCode: "brain"
        case .devTools: "wrench.and.screwdriver.fill"
        case .docker: "shippingbox.fill"
        case .uv: "bolt.fill"
        case .bun: "cup.and.saucer.fill"
        }
    }
}

/// Status of a provisioning step.
public enum ProvisioningStepStatus: Sendable, Equatable {
    public case pending
    public case running
    public case completed
    public case failed(String)
}

/// A single step in the provisioning process.
public struct ProvisioningStep: Identifiable, Sendable {
    let id: UUID
    let feature: ProvisioningFeature
    var status: ProvisioningStepStatus

    init(feature: ProvisioningFeature, status: ProvisioningStepStatus = .pending) {
        self.id = UUID()
        self.feature = feature
        self.status = status
    }
}

/// Configuration for provisioning a new VPS.
public struct ProvisioningConfig: Codable, Sendable {
    var provider: CloudProvider
    var region: String
    var size: String
    var hostname: String
    var features: [ProvisioningFeature]
    var deployUsername: String
    var sshPort: Int

    init(
        provider: CloudProvider = .hetzner,
        region: String = "fsn1",
        size: String = "cx22",
        hostname: String = "claude-dev",
        features: [ProvisioningFeature] = [.securityHardening, .claudeCode, .devTools],
        deployUsername: String = "deploy",
        sshPort: Int = 2222
    ) {
        self.provider = provider
        self.region = region
        self.size = size
        self.hostname = hostname
        self.features = features
        self.deployUsername = deployUsername
        self.sshPort = sshPort
    }
}

extension ProvisioningConfig {
    public static let `default` = ProvisioningConfig()

    public static let preview = ProvisioningConfig(
        provider: .hetzner,
        hostname: "my-dev-server",
        features: [.securityHardening, .claudeCode, .devTools, .docker]
    )
}
