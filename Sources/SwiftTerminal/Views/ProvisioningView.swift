import SwiftUI

/// One-tap VPS setup wizard — select features to install, then watch progress.
struct ProvisioningView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var config = ProvisioningConfig.default
    @State private var selectedFeatures: Set<ProvisioningFeature> = [
        .securityHardening, .claudeCode, .devTools
    ]
    @State private var isProvisioning = false
    @State private var steps: [ProvisioningStep] = []
    @State private var logOutput: [String] = []

    var body: some View {
        Group {
            if isProvisioning {
                progressView
            } else {
                configurationForm
            }
        }
        .navigationTitle("Provision Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isProvisioning ? "Close" : "Cancel") {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Configuration

    private var configurationForm: some View {
        Form {
            Section("Server") {
                TextField("Hostname", text: $config.hostname)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                TextField("Deploy Username", text: $config.deployUsername)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack {
                    Text("SSH Port")
                    Spacer()
                    TextField("Port", value: $config.sshPort, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .keyboardType(.numberPad)
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
            } footer: {
                Text("This will run setup scripts on the connected server. Make sure you're connected as root.")
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

    private func statusIcon(for status: ProvisioningStepStatus) -> some View {
        Group {
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
        logOutput = ["🚀 Provisioning started..."]

        // In real implementation, this would use ProvisioningService with an SSH connection.
        // For MVP, simulate progress.
        Task {
            for index in steps.indices {
                steps[index].status = .running
                logOutput.append("▶ Running \(steps[index].feature.displayName)...")
                try? await Task.sleep(for: .seconds(1))
                steps[index].status = .completed
                logOutput.append("✅ \(steps[index].feature.displayName) complete")
            }
            logOutput.append("\n🏁 All done!")
        }
    }
}

#Preview {
    NavigationStack {
        ProvisioningView()
    }
}
