import SwiftUI

/// Manage SSH keys — generate, import, list, and delete.
public struct KeyManagementView: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showingGenerateSheet = false
    @State private var showingImportSheet = false

    public var body: some View {
        Group {
            if store.sshKeys.isEmpty {
                emptyState
            } else {
                keyList
            }
        }
        .navigationTitle("SSH Keys")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                HStack {
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
                    Spacer()
                    ShareLink(item: key.publicKey) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                }
                .contextMenu {
                    Button {
                        copyPublicKey(key)
                    } label: {
                        Label("Copy Public Key", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: key.publicKey) {
                        Label("Share Public Key", systemImage: "square.and.arrow.up")
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
    @State private var errorMessage: String?
    @State private var showCopiedToast = false

    public var body: some View {
        Form {
            Section("Key Details") {
                TextField("Key Name", text: $name, prompt: Text("My SSH Key"))
                Picker("Key Type", selection: $keyType) {
                    ForEach(SSHKeyType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
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
            } header: {
                EmptyView()
            } footer: {
                Text("The private key will be stored securely in the Keychain with biometric protection. The public key will be copied to clipboard.")
            }
        }
        .navigationTitle("Generate SSH Key")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func generateKey() {
        isGenerating = true
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let comment = "\(trimmedName)@iPhone"

        do {
            let generated = try SSHKeyGenerator.generate(type: keyType, comment: comment)

            let key = SSHKey(
                name: trimmedName,
                keyType: keyType,
                publicKey: generated.publicKeyOpenSSH,
                fingerprint: generated.fingerprint
            )

            // Store private key in Keychain
            try KeychainService.savePrivateKey(
                generated.privateKeyRaw,
                tag: key.keychainTag,
                requireBiometrics: true
            )

            store.addKey(key)

            // Copy public key to clipboard
            #if canImport(UIKit)
            UIPasteboard.general.string = generated.publicKeyOpenSSH
            #endif

            isGenerating = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isGenerating = false
        }
    }
}

// MARK: - Import Key Sheet

private struct ImportKeyView: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var publicKey = ""
    @State private var privateKey = ""

    public var body: some View {
        Form {
            Section("Key Details") {
                TextField("Key Name", text: $name, prompt: Text("Imported Key"))
            }

            Section("Public Key") {
                TextEditor(text: $publicKey)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 80)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            Section {
                TextEditor(text: $privateKey)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Private Key")
            } footer: {
                Text("The private key will be stored securely in the Keychain.")
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
