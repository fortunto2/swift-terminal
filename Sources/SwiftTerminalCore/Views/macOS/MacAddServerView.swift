#if os(macOS)
import SwiftUI
import AppKit

/// macOS-native form for adding or editing an SSH server.
/// Uses grouped form style for a clean single-column layout.
struct MacAddServerView: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var existingServer: Server?

    @State private var name = ""
    @State private var host = ""
    @State private var port = 22
    @State private var username = "root"
    @State private var authMethod: AuthMethod = .key
    @State private var selectedKeyID: UUID?
    @State private var tags = ""
    @State private var showingProvisioningView = false

    private var isEditing: Bool { existingServer != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        port > 0 && port <= 65535
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Connection") {
                    TextField("Name", text: $name, prompt: Text("My Server"))
                    TextField("Host", text: $host, prompt: Text("192.168.1.1 or example.com"))
                        .autocorrectionDisabled()
                    TextField("Port", value: $port, format: .number)
                    TextField("Username", text: $username, prompt: Text("root"))
                        .autocorrectionDisabled()
                }

                Section("Authentication") {
                    Picker("Method", selection: $authMethod) {
                        ForEach(AuthMethod.allCases) { method in
                            Label(method.displayName, systemImage: method.systemImage)
                                .tag(method)
                        }
                    }

                    if authMethod == .key {
                        Picker("SSH Key", selection: $selectedKeyID) {
                            Text("None").tag(nil as UUID?)
                            ForEach(store.sshKeys) { key in
                                Text(key.name).tag(key.id as UUID?)
                            }
                        }
                        if store.sshKeys.isEmpty {
                            Text("No SSH keys yet. Add one in SSH Keys section.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Tags") {
                    TextField("Tags (comma-separated)", text: $tags, prompt: Text("dev, claude, prod"))
                        .autocorrectionDisabled()
                }

                if !isEditing {
                    Section {
                        Button {
                            showingProvisioningView = true
                        } label: {
                            Label("Set Up with One-Tap Provisioning", systemImage: "wand.and.stars")
                        }
                    } footer: {
                        Text("Automatically harden security, install Claude Code, and set up dev tools.")
                    }
                }
            }
            .formStyle(.grouped)

            // Bottom bar with Cancel / Save
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Add Server") {
                    saveServer()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 380)
        .navigationTitle(isEditing ? "Edit Server" : "Add Server")
        .onAppear {
            if let server = existingServer {
                name = server.name
                host = server.host
                port = server.port
                username = server.username
                authMethod = server.authMethod
                selectedKeyID = server.keyID
                tags = server.tags.joined(separator: ", ")
            }
        }
        .sheet(isPresented: $showingProvisioningView) {
            NavigationStack {
                ProvisioningView(server: Server(
                    name: name.isEmpty ? host : name,
                    host: host,
                    port: port,
                    username: username,
                    authMethod: authMethod,
                    keyID: selectedKeyID
                ))
            }
            .frame(minWidth: 520, minHeight: 500)
        }
    }

    private func saveServer() {
        let parsedTags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let server = Server(
            id: existingServer?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            port: port,
            username: username.trimmingCharacters(in: .whitespaces),
            authMethod: authMethod,
            keyID: selectedKeyID,
            tags: parsedTags,
            createdAt: existingServer?.createdAt ?? .now
        )

        if isEditing {
            store.updateServer(server)
        } else {
            store.addServer(server)
        }
    }
}
#endif
