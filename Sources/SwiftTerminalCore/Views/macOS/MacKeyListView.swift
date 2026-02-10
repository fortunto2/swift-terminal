#if os(macOS)
import SwiftUI
import AppKit

/// macOS SSH key management view for the detail pane.
/// Uses ScrollView + VStack instead of List to avoid rendering issues on macOS.
struct MacKeyListView: View {
    @Environment(ServerStore.self) private var store
    @State private var showingGenerateSheet = false
    @State private var showingImportSheet = false

    var body: some View {
        Group {
            if store.sshKeys.isEmpty {
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
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(store.sshKeys) { key in
                            keyRow(key)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("SSH Keys")
        .onAppear {
            if store.sshKeys.isEmpty {
                showingGenerateSheet = true
            }
        }
        .toolbar {
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
                MacImportKeyView()
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
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key.publicKey, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .help("Copy public key")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
        )
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key.publicKey, forType: .string)
            } label: {
                Label("Copy Public Key", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                store.deleteKey(key)
            } label: {
                Label("Delete Key", systemImage: "trash")
            }
        }
    }
}

// MARK: - macOS Import Key Sheet

private struct MacImportKeyView: View {
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
            }

            Section {
                TextEditor(text: $privateKey)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100)
                    .autocorrectionDisabled()
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
#endif
