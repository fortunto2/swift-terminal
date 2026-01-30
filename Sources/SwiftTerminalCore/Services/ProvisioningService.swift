import Foundation

/// Manages VPS provisioning — runs scripts over SSH to set up a new server.
@MainActor
@Observable
public final class ProvisioningService {
    private let ssh: SSHService

    public private(set) var steps: [ProvisioningStep] = []
    public private(set) var isProvisioning = false
    public private(set) var currentFeature: ProvisioningFeature?
    public private(set) var log: [String] = []

    public init(ssh: SSHService) {
        self.ssh = ssh
    }

    /// Provision a server with the given configuration.
    public func provision(config: ProvisioningConfig) async {
        guard ssh.isConnected else {
            appendLog("❌ Not connected to any server")
            return
        }

        isProvisioning = true
        steps = config.features.map { ProvisioningStep(feature: $0) }
        log = []

        appendLog("🚀 Starting provisioning: \(config.hostname)")
        appendLog("   Features: \(config.features.map(\.displayName).joined(separator: ", "))")

        for index in steps.indices {
            let feature = steps[index].feature
            currentFeature = feature
            steps[index].status = .running

            appendLog("\n▶ \(feature.displayName)...")

            do {
                let script = ProvisioningScripts.script(
                    for: feature,
                    username: config.deployUsername,
                    sshPort: config.sshPort
                )
                let output = try await ssh.execute(script)
                appendLog(output)
                steps[index].status = .completed
                appendLog("✅ \(feature.displayName) completed")
            } catch {
                steps[index].status = .failed(error.localizedDescription)
                appendLog("❌ \(feature.displayName) failed: \(error.localizedDescription)")
            }
        }

        currentFeature = nil
        isProvisioning = false
        appendLog("\n🏁 Provisioning finished")
    }

    /// Cancel the current provisioning (best-effort).
    public func cancel() {
        isProvisioning = false
        currentFeature = nil
        appendLog("⚠️ Provisioning canceled by user")
    }

    private func appendLog(_ message: String) {
        log.append(message)
    }
}
