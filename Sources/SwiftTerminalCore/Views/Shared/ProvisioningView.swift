import SwiftUI

/// One-tap VPS setup wizard — select features to install, then watch progress.
/// Connects to the given server via SSH and runs provisioning scripts.
public struct ProvisioningView: View {
    let server: Server

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerStore.self) private var store

    @State private var config = ProvisioningConfig.default
    @State private var selectedFeatures: Set<ProvisioningFeature> = [
        .securityHardening, .claudeCode, .devTools
    ]
    @State private var isProvisioning = false
    @State private var sshService = SSHService()
    @State private var provisioningService: ProvisioningService?
    @State private var steps: [ProvisioningStep] = []
    @State private var logOutput: [String] = []
    @State private var connectionError: String?

    public var body: some View {
        Group {
            if isProvisioning {
                progressView
            } else {
                configurationForm
            }
        }
        .navigationTitle("Provision Server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isProvisioning ? "Close" : "Cancel") {
                    provisioningService?.cancel()
                    dismiss()
                }
            }
        }
        .onAppear {
            config.hostname = server.host
            config.deployUsername = server.username
        }
    }

    // MARK: - Configuration

    private var configurationForm: some View {
        Form {
            Section("Server") {
                LabeledContent("Host", value: server.connectionString)

                TextField("Deploy Username", text: $config.deployUsername)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                HStack {
                    Text("SSH Port")
                    Spacer()
                    TextField("Port", value: $config.sshPort, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }

            Section("Features to Install") {
                ForEach(ProvisioningFeature.allCases) { feature in
                    Toggle(isOn: Binding(
                        get: { selectedFeatures.contains(feature) },
                        set: { isOn in
                            if isOn {
                                selectedFeatures.insert(feature)
                            } else {
                                selectedFeatures.remove(feature)
                            }
                        }
                    )) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(feature.displayName)
                                Text(feature.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: feature.systemImage)
                        }
                    }
                }
            }

            if let connectionError {
                Section {
                    Label(connectionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    startProvisioning()
                } label: {
                    Label("Start Provisioning", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .disabled(selectedFeatures.isEmpty)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                EmptyView()
            } footer: {
                Text("This will connect to the server and run setup scripts. Make sure the server is reachable and you have root/sudo access.")
            }
        }
    }

    // MARK: - Progress

    private var progressView: some View {
        List {
            Section("Progress") {
                ForEach(steps) { step in
                    HStack {
                        statusIcon(for: step.status)
                        VStack(alignment: .leading) {
                            Text(step.feature.displayName)
                                .font(.headline)
                            statusText(for: step.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Log") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logOutput.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.green)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 200)
                .listRowBackground(Color.black)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIcon(for status: ProvisioningStepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func statusText(for status: ProvisioningStepStatus) -> Text {
        switch status {
        case .pending: Text("Waiting...")
        case .running: Text("Running...")
        case .completed: Text("Done")
        case .failed(let error): Text("Failed: \(error)")
        }
    }

    private func startProvisioning() {
        config.features = Array(selectedFeatures).sorted { $0.rawValue < $1.rawValue }
        steps = config.features.map { ProvisioningStep(feature: $0) }
        isProvisioning = true
        connectionError = nil
        logOutput = ["Connecting to \(server.connectionString)..."]

        Task {
            // Connect to the server
            do {
                try await connectToServer()
            } catch {
                connectionError = error.localizedDescription
                logOutput.append("Connection failed: \(error.localizedDescription)")
                isProvisioning = false
                return
            }

            logOutput.append("Connected. Starting provisioning...")

            // Create provisioning service and run
            let service = ProvisioningService(ssh: sshService)
            provisioningService = service
            await service.provision(config: config)

            // Sync service state back to our view
            steps = service.steps
            logOutput = service.log

            await sshService.disconnect()
        }
    }

    private func connectToServer() async throws {
        switch server.authMethod {
        case .password:
            // For provisioning, password auth isn't ideal — would need a prompt
            // For now, try key-based auth which is the expected flow
            throw SSHServiceError.authenticationFailed
        case .key:
            guard let keyID = server.keyID,
                  let sshKey = store.key(for: keyID) else {
                throw SSHServiceError.authenticationFailed
            }
            guard let privateKeyData = try KeychainService.load(key: sshKey.keychainTag) else {
                throw SSHServiceError.authenticationFailed
            }
            try await sshService.connect(
                to: server,
                privateKeyData: privateKeyData,
                keyType: sshKey.keyType
            )
        case .agent:
            throw SSHServiceError.authenticationFailed
        }
    }
}

#Preview {
    NavigationStack {
        ProvisioningView(server: .preview)
    }
    .environment(ServerStore())
}
