import SwiftUI
import SwiftData
import LocalAuthentication

/// iOS root view: LockScreen gate → NavigationStack → ServerListView.
struct iOSMainView: View {
    @State private var isUnlocked = false
    @State private var authError: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionManager.self) private var sessionManager
    @AppStorage("requireLockScreen") private var requireLockScreen = true

    private var shouldLock: Bool { requireLockScreen }

    var body: some View {
        Group {
            if isUnlocked || !shouldLock {
                NavigationStack {
                    ServerListView()
                }
            } else {
                lockedView
            }
        }
        .onAppear {
            sessionManager.setModelContext(modelContext)
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
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
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
