#if os(iOS)
import SwiftUI
import LocalAuthentication

/// Biometric lock screen — Face ID / Touch ID on app launch.
public struct LockScreenView: View {
    @State private var isUnlocked = false
    @State private var authError: String?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("requireLockScreen") private var requireLockScreen = true

    public init() {}

    private var shouldLock: Bool {
        return requireLockScreen
    }

    public var body: some View {
        Group {
            if isUnlocked || !shouldLock {
                NavigationStack {
                    ServerListView()
                }
            } else {
                lockedView
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && shouldLock {
                isUnlocked = false
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("SwiftTerminal")
                .font(.title.bold())

            Text("Unlock to access your servers")
                .foregroundStyle(.secondary)

            if let authError {
                Text(authError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                authenticate()
            } label: {
                Label("Unlock", systemImage: biometricIcon)
                    .font(.headline)
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .onAppear {
            authenticate()
        }
    }

    private var biometricIcon: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch context.biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        default: "lock.open.fill"
        }
    }

    private func authenticate() {
        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"

        var error: NSError?
        // deviceOwnerAuthentication = biometrics + passcode fallback
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics and no passcode — just unlock
            isUnlocked = true
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock SwiftTerminal to access your SSH keys and servers"
        ) { success, authenticationError in
            DispatchQueue.main.async {
                if success {
                    isUnlocked = true
                    authError = nil
                } else {
                    authError = authenticationError?.localizedDescription
                }
            }
        }
    }
}
#endif
