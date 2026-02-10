#if os(iOS)
import SwiftUI
import UIKit

/// Manage SSH keys — generate, import, list, and delete.
public struct KeyManagementView: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showingGenerateSheet = false
    @State private var showingImportSheet = false

    public init() {}

    public var body: some View {
        List {
            if store.sshKeys.isEmpty {
                Section {
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
            } else {
                ForEach(store.sshKeys) { key in
                    keyRow(key)
                }
                .onDelete { offsets in
                    store.deleteKeys(at: offsets)
                }
            }
        }
        .onAppear {
            if store.sshKeys.isEmpty {
                showingGenerateSheet = true
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

    private func keyRow(_ key: SSHKey) -> some View {
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
            Button {
                copyPublicKey(key)
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .help("Copy public key")
        }
        .contextMenu {
            Button {
                copyPublicKey(key)
            } label: {
                Label("Copy Public Key", systemImage: "doc.on.doc")
            }
        }
    }

    private func copyPublicKey(_ key: SSHKey) {
        UIPasteboard.general.string = key.publicKey
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
            tag: key.keychainTag
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
#endif
