#if os(iOS)
import SwiftUI

/// Form for adding or editing an SSH server.
public struct AddServerView: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// If set, we're editing an existing server.
    var existingServer: Server?

    @State private var name = ""
    @State private var host = ""
    @State private var port = 22
    /// Empty, with "root" as the prompt and as the fallback on save. It used to hold the literal
    /// string "root" while also showing it as a placeholder, so typing a username appended to it
    /// and produced "rootdeploy".
    @State private var username = ""
    @State private var authMethod: AuthMethod = .key
    @State private var selectedKeyID: UUID?
    @State private var tags = ""
    @State private var showingProvisioningView = false
    @State private var tmuxReinstallQueued = false

    private var isEditing: Bool { existingServer != nil }

    /// Only the host is genuinely required — a name defaults to the host and a username to root,
    /// so adding the first server is one field instead of three.
    private var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        port > 0 && port <= 65535
    }

    private var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? host.trimmingCharacters(in: .whitespaces) : trimmed
    }

    private var resolvedUsername: String {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "root" : trimmed
    }

    public var body: some View {
        Form {
            Section("Connection") {
                TextField("Name", text: $name, prompt: Text("My Server"))
                TextField("Host", text: $host, prompt: Text("192.168.1.1 or example.com"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    // No .textContentType(.URL): it makes iOS offer a Paste/AutoFill bubble for
                    // saved website logins, which has nothing to offer an SSH host and parks
                    // itself on top of the Port field.
                    .textInputAutocapitalization(.never)
                    #endif
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", value: $port, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                TextField("Username", text: $username, prompt: Text("root"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
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
                        Text("No SSH keys yet. Add one in Key Management.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Tags") {
                TextField("Tags (comma-separated)", text: $tags, prompt: Text("dev, claude, prod"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            if isEditing {
                Section {
                    Button {
                        if var server = existingServer {
                            server.tmuxVerified = nil
                            store.updateServer(server)
                        }
                        tmuxReinstallQueued = true
                    } label: {
                        Label(
                            tmuxReinstallQueued ? "Will install on next connect" : "Reinstall tmux",
                            systemImage: tmuxReinstallQueued ? "checkmark.circle" : "terminal"
                        )
                    }
                    .disabled(tmuxReinstallQueued)
                } footer: {
                    Text("Runs the tmux install check on next connection to this server.")
                }
            }

            if !isEditing {
                Section {
                    Button {
                        showingProvisioningView = true
                    } label: {
                        Label("Set Up with One-Tap Provisioning", systemImage: "wand.and.stars")
                    }
                } header: {
                    EmptyView()
                } footer: {
                    Text("Automatically harden security, install Claude Code, and set up dev tools.")
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Server" : "Add Server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add") {
                    saveServer()
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            if let server = existingServer {
                name = server.name
                host = server.host
                port = server.port
                username = server.username
                authMethod = server.authMethod
                selectedKeyID = server.keyID
                tags = server.tags.joined(separator: ", ")
            } else {
                // Auto-select first available key for new servers
                selectedKeyID = store.sshKeys.first?.id
            }
        }
        .sheet(isPresented: $showingProvisioningView) {
            NavigationStack {
                ProvisioningView(server: Server(
                    name: resolvedName,
                    host: host.trimmingCharacters(in: .whitespaces),
                    port: port,
                    username: resolvedUsername,
                    authMethod: authMethod,
                    keyID: selectedKeyID
                ))
            }
        }
    }

    private func saveServer() {
        let parsedTags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let server = Server(
            id: existingServer?.id ?? UUID(),
            name: resolvedName,
            host: host.trimmingCharacters(in: .whitespaces),
            port: port,
            username: resolvedUsername,
            authMethod: authMethod,
            keyID: selectedKeyID,
            tags: parsedTags,
            createdAt: existingServer?.createdAt ?? .now
        )

        if isEditing {
            store.updateServer(server)
        } else {
            store.addServer(server)
            Telemetry.track("host_added", ["auth": server.authMethod.rawValue])
        }
    }
}

#Preview {
    NavigationStack {
        AddServerView()
    }
    .environment(ServerStore())
}
#endif
