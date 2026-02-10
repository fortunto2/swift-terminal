import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Generate Key Sheet

struct GenerateKeyView: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var keyType: SSHKeyType = .ed25519
    @State private var isGenerating = false
    @State private var errorMessage: String?

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
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Keychain Error", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline.bold())
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        #if os(macOS)
                        Text("Open System Settings > Privacy & Security > Keychain Access if prompted. Make sure the app is allowed to access the Keychain.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        #endif
                        Button("Retry") {
                            generateKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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
            } header: {
                EmptyView()
            } footer: {
                #if os(iOS)
                Text("The private key will be stored securely in the Keychain with biometric protection. The public key will be copied to clipboard.")
                #else
                Text("The private key will be stored securely in the Keychain. The public key will be copied to clipboard.")
                #endif
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
        #if os(iOS)
        let comment = "\(trimmedName)@iPhone"
        #else
        let comment = "\(trimmedName)@Mac"
        #endif

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
                tag: key.keychainTag
            )

            store.addKey(key)

            // Copy public key to clipboard
            #if canImport(UIKit)
            UIPasteboard.general.string = generated.publicKeyOpenSSH
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(generated.publicKeyOpenSSH, forType: .string)
            #endif

            isGenerating = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isGenerating = false
        }
    }
}
