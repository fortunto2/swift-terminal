import SwiftUI

/// First-launch onboarding: guides user through SSH key creation and server setup.
struct OnboardingView: View {
    @Environment(ServerStore.self) private var store
    @State private var showingGenerateKey = false
    @State private var showingAddServer = false

    var onSkip: () -> Void

    private var hasKeys: Bool { !store.sshKeys.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                step1
                step2
                permissionsInfo
                skipButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(isPresented: $showingGenerateKey) {
            NavigationStack {
                GenerateKeyView()
            }
        }
        .sheet(isPresented: $showingAddServer) {
            #if os(iOS)
            NavigationStack {
                AddServerView()
            }
            #else
            MacAddServerView()
            #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Welcome to SuperDuper Terminal")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Set up SSH access in two steps")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 1: Create SSH Key

    private var step1: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                stepBadge(number: 1, completed: hasKeys)
                Text("Create SSH Key")
                    .font(.headline)
                if hasKeys {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if hasKeys {
                let keyName = store.sshKeys.first?.name ?? "Key"
                Label("\(keyName) ready", systemImage: "key.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    showingGenerateKey = true
                } label: {
                    Label("Generate SSH Key", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Ed25519 recommended. Your private key stays in the Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Step 2: Add Server

    private var step2: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                stepBadge(number: 2, completed: false)
                Text("Add Your Server")
                    .font(.headline)
            }

            Button {
                showingAddServer = true
            } label: {
                Label("Add Server", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasKeys)

            if !hasKeys {
                Text("Generate an SSH key first to unlock this step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(hasKeys ? 1 : 0.6)
    }

    // MARK: - Permissions Info

    private var permissionsInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permissions", systemImage: "info.circle")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            #if os(iOS)
            bulletPoint("Face ID / Touch ID protects your keys")
            bulletPoint("Keychain stores keys securely on device")
            #else
            bulletPoint("Keychain stores keys securely")
            bulletPoint("Allow Keychain access when prompted by macOS")
            #endif
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Skip

    private var skipButton: some View {
        Button("Skip Setup") {
            onSkip()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func stepBadge(number: Int, completed: Bool) -> some View {
        Text(completed ? "\u{2713}" : "\(number)")
            .font(.caption.bold())
            .foregroundStyle(completed ? .green : .white)
            .frame(width: 24, height: 24)
            .background(completed ? Color.green.opacity(0.2) : Color.accentColor)
            .clipShape(Circle())
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    OnboardingView(onSkip: {})
        .environment(ServerStore())
}
