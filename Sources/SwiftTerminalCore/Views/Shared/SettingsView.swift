import SwiftUI

/// App settings — appearance, defaults, about.
public struct SettingsView: View {
    public init() {}
    @Environment(\.dismiss) private var dismiss

    @AppStorage("defaultPort") private var defaultPort = 22
    @AppStorage("defaultUsername") private var defaultUsername = "root"
    @AppStorage("terminalFontSize") private var terminalFontSize = 14.0
    @AppStorage("requireBiometrics") private var requireBiometrics = false
    @AppStorage("requireLockScreen") private var requireLockScreen = false
    @AppStorage("autoReconnect") private var autoReconnect = true
    @AppStorage("autoTmux") private var autoTmux = true

    public var body: some View {
        Form {
            Section {
                HStack {
                    Text("Default Port")
                    Spacer()
                    TextField("Port", value: $defaultPort, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                TextField("Default Username", text: $defaultUsername)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Toggle("Auto-Reconnect", isOn: $autoReconnect)
                Toggle("Auto-tmux Sessions", isOn: $autoTmux)
            } header: {
                Text("Connection Defaults")
            } footer: {
                Text("Auto-tmux wraps each shell in a tmux session for persistence when the app goes to background.")
            }

            Section("Terminal") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Text("\(Int(terminalFontSize)) pt")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $terminalFontSize, in: 10...24, step: 1) {
                    Text("Font Size")
                }
            }

            Section {
                Toggle("Lock Screen on Launch", isOn: $requireLockScreen)
                Toggle("Require Biometrics for Keys", isOn: $requireBiometrics)
            } header: {
                Text("Security")
            } footer: {
                Text("Lock Screen requires Face ID / Touch ID when opening the app. Biometrics for Keys protects SSH private key access.")
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("Swift", value: "6.1")
                LabeledContent("Build", value: "MVP")

                Link(destination: URL(string: "https://github.com/fortunto2/swift-terminal")!) {
                    Label("GitHub Repository", systemImage: "link")
                }
            }

            Section {
                Button(role: .destructive) {
                    resetDefaults()
                } label: {
                    Label("Reset All Settings", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func resetDefaults() {
        defaultPort = 22
        defaultUsername = "root"
        terminalFontSize = 14.0
        requireBiometrics = false
        requireLockScreen = false
        autoReconnect = true
        autoTmux = true
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
