import SwiftUI

/// Manage SSH keys — generate, import, list, and delete.
struct KeyManagementView: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showingGenerateSheet = false
    @State private var showingImportSheet = false

    var body: some View {
        Group {
            if store.sshKeys.isEmpty {
                emptyState
            } else {
                keyList
            }
        }
        .navigationTitle("SSH Keys")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingGenerateSheet = true
                    } label: {
                        Label("Generate New Key", systemImage: "plus.circle")
                    }
                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("Import Key", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingGenerateSheet) {
            NavigationStack {
                GenerateKeyView()
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            NavigationStack {
                ImportKeyView()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No SSH Keys", systemImage: "key.fill")
        } description: {
            Text("Generate or import an SSH key to authenticate with your servers.")
        } actions: {
            Button("Generate Key") {
                showingGenerateSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var keyList: some View {
        @Bindable var store = store
        List {
            ForEach(store.sshKeys) { key in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.orange)
                        Text(key.name)
                            .font(.headline)
                    }
                    Text(key.keyType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(key.publicKey.prefix(50) + "...")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Text("Created \(key.createdAt, format: .dateTime.month().day().year())")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contextMenu {
                    Button {
                        copyPublicKey(key)
                    } label: {
                        Label("Copy Public Key", systemImage: "doc.on.doc")
                    }
                }
            }
            .onDelete { offsets in
                store.deleteKeys(at: offsets)
            }
        }
    }

    private func copyPublicKey(_ key: SSHKey) {
        #if canImport(UIKit)
        UIPasteboard.general.string = key.publicKey
        #endif
    }
}

// MARK: - Generate Key Sheet

private struct GenerateKeyView: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var keyType: SSHKeyType = .ed25519
    @State private var isGenerating = false

    var body: some View {
        Form {
            Section("Key Details") {
                TextField("Key Name", text: $name, prompt: Text("My SSH Key"))
                Picker("Key Type", selection: $keyType) {
                    ForEach(SSHKeyType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

            Section {
                Button {
                    generateKey()
                } label: {
                    if isGenerating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Generate Key")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("The private key will be stored securely in the iOS Keychain with biometric protection.")
            }
        }
        .navigationTitle("Generate SSH Key")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func generateKey() {
        isGenerating = true

        // MVP: placeholder key generation
        // Real implementation would use Security framework or CryptoKit
        let key = SSHKey(
            name: name.trimmingCharacters(in: .whitespaces),
            keyType: keyType,
            publicKey: "\(keyType.algorithmName) AAAA...placeholder... \(name)",
            fingerprint: "SHA256:placeholder_\(UUID().uuidString.prefix(8))"
        )

        // Store private key in Keychain (placeholder)
        try? KeychainService.savePrivateKey(
            "placeholder-private-key-\(key.id)",
            tag: key.keychainTag,
            requireBiometrics: true
        )

        store.addKey(key)
        isGenerating = false
        dismiss()
    }
}

// MARK: - Import Key Sheet

private struct ImportKeyView: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var publicKey = ""
    @State private var privateKey = ""

    var body: some View {
        Form {
            Section("Key Details") {
                TextField("Key Name", text: $name, prompt: Text("Imported Key"))
            }

            Section("Public Key") {
                TextEditor(text: $publicKey)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 80)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section("Private Key") {
                TextEditor(text: $privateKey)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } footer: {
                Text("The private key will be stored securely in the iOS Keychain.")
            }

            Section {
                Button("Import Key") {
                    importKey()
                }
                .disabled(
                    name.trimmingCharacters(in: .whitespaces).isEmpty ||
                    publicKey.trimmingCharacters(in: .whitespaces).isEmpty ||
                    privateKey.trimmingCharacters(in: .whitespaces).isEmpty
                )
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Import SSH Key")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func importKey() {
        let key = SSHKey(
            name: name.trimmingCharacters(in: .whitespaces),
            keyType: detectKeyType(from: publicKey),
            publicKey: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        // Store private key in Keychain
        try? KeychainService.savePrivateKey(
            privateKey.trimmingCharacters(in: .whitespacesAndNewlines),
            tag: key.keychainTag,
            requireBiometrics: true
        )

        store.addKey(key)
        dismiss()
    }

    private func detectKeyType(from publicKey: String) -> SSHKeyType {
        if publicKey.hasPrefix("ssh-ed25519") {
            .ed25519
        } else if publicKey.hasPrefix("ecdsa-") {
            .ecdsaP256
        } else {
            .rsa4096
        }
    }
}

#Preview {
    NavigationStack {
        KeyManagementView()
    }
    .environment(ServerStore())
}
