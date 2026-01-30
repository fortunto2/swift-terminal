#if canImport(UIKit)
import SwiftUI
import UIKit
import SwiftTerm

/// SwiftUI wrapper around SwiftTerm's TerminalView for interactive SSH sessions.
public struct TerminalView: View {
    let server: Server

    @State private var sshService = SSHService()
    @State private var connectionState: ConnectionState = .disconnected
    @State private var errorMessage: String?

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case failed
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch connectionState {
            case .disconnected, .connecting:
                connectingOverlay
            case .connected:
                TerminalViewRepresentable()
                    .ignoresSafeArea(.keyboard)
            case .failed:
                failedOverlay
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if connectionState == .connected {
                        Button {
                            Task { await sshService.disconnect() }
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    }
                    Button {
                        Task { await connect() }
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await connect()
        }
    }

    // MARK: - Overlays

    private var connectingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.green)
            Text("Connecting to \(server.connectionString)...")
                .foregroundStyle(.green)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var failedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Connection Failed")
                .font(.headline)
                .foregroundStyle(.white)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Retry") {
                Task { await connect() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    // MARK: - Connection

    private func connect() async {
        connectionState = .connecting
        errorMessage = nil

        do {
            // MVP: password auth placeholder — real implementation will use
            // KeychainService to load private key or prompt for password
            try await sshService.connect(to: server, password: "")
            connectionState = .connected
        } catch {
            connectionState = .failed
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - UIViewRepresentable for SwiftTerm

public struct TerminalViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        terminalView.backgroundColor = .black

        // Configure terminal appearance
        let fontSize: CGFloat = 14
        terminalView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = .init(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)

        // Feed initial welcome text
        let welcome = "SwiftTerminal v0.1.0\r\nConnecting...\r\n"
        let bytes: [UInt8] = Array(welcome.utf8)
        terminalView.feed(byteArray: bytes)

        return terminalView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // Updates handled by the terminal's internal state
    }
}

#Preview {
    NavigationStack {
        TerminalView(server: .preview)
    }
}

#else
// macOS stub — SwiftTerm terminal view requires UIKit on iOS
import SwiftUI

public struct TerminalView: View {
    let server: Server

    public var body: some View {
        Text("Terminal view requires iOS")
            .navigationTitle(server.name)
    }
}

public struct TerminalViewRepresentable: View {
    public var body: some View {
        Text("Terminal requires UIKit")
    }
}
#endif
