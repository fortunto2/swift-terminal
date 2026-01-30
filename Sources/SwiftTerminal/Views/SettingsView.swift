import SwiftUI

/// App settings — appearance, defaults, about.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("defaultPort") private var defaultPort = 22
    @AppStorage("defaultUsername") private var defaultUsername = "root"
    @AppStorage("terminalFontSize") private var terminalFontSize = 14.0
    @AppStorage("requireBiometrics") private var requireBiometrics = true
    @AppStorage("autoReconnect") private var autoReconnect = true

    var body: some View {
        Form {
            Section("Connection Defaults") {
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
                Toggle("Require Biometrics for Keys", isOn: $requireBiometrics)
            } header: {
                Text("Security")
            } footer: {
                Text("When enabled, Face ID or Touch ID is required to use SSH private keys.")
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
        requireBiometrics = true
        autoReconnect = true
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
