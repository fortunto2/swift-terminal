#if canImport(UIKit)
import SwiftUI
import UIKit
import SwiftTerm

/// SwiftUI wrapper around SwiftTerm's TerminalView for interactive SSH sessions.
public struct TerminalView: View {
    let server: Server

    @Environment(ServerStore.self) private var store
    @State private var sshService = SSHService()
    @State private var connectionState: ConnectionState = .disconnected
    @State private var errorMessage: String?
    @State private var showPasswordPrompt = false
    @State private var passwordInput = ""

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
                GeometryReader { geo in
                    if geo.size.width > 0 && geo.size.height > 0 {
                        TerminalViewRepresentable(
                            sshService: sshService,
                            initialSize: geo.size
                        )
                        .ignoresSafeArea(.keyboard)
                    }
                }
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
        .alert("Enter Password", isPresented: $showPasswordPrompt) {
            SecureField("Password", text: $passwordInput)
            Button("Connect") {
                Task { await connectWithPassword(passwordInput) }
                passwordInput = ""
            }
            Button("Cancel", role: .cancel) {
                connectionState = .disconnected
                passwordInput = ""
            }
        } message: {
            Text("Password for \(server.connectionString)")
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

        switch server.authMethod {
        case .password:
            showPasswordPrompt = true
        case .key:
            await connectWithKey()
        case .agent:
            connectionState = .failed
            errorMessage = "SSH Agent not yet supported"
        }
    }

    private func connectWithPassword(_ password: String) async {
        connectionState = .connecting
        do {
            try await sshService.connect(to: server, password: password)
            connectionState = .connected
        } catch {
            connectionState = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func connectWithKey() async {
        guard let keyID = server.keyID,
              let sshKey = store.key(for: keyID) else {
            connectionState = .failed
            errorMessage = "No SSH key assigned to this server"
            return
        }

        do {
            guard let privateKeyData = try KeychainService.load(key: sshKey.keychainTag) else {
                connectionState = .failed
                errorMessage = "Private key not found in Keychain"
                return
            }

            try await sshService.connect(
                to: server,
                privateKeyData: privateKeyData,
                keyType: sshKey.keyType
            )
            connectionState = .connected
        } catch {
            connectionState = .failed
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - UIViewRepresentable for SwiftTerm

public struct TerminalViewRepresentable: UIViewRepresentable {
    let sshService: SSHService
    let initialSize: CGSize

    public func makeCoordinator() -> Coordinator {
        Coordinator(sshService: sshService)
    }

    public func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let frame = CGRect(origin: .zero, size: initialSize)
        let terminalView = SwiftTerm.TerminalView(frame: frame)
        terminalView.backgroundColor = .black

        let fontSize: CGFloat = 14
        terminalView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = .init(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)

        // Set delegate to capture keyboard input
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminalView

        // Start SSH shell and pipe output to terminal
        let cols = terminalView.getTerminal().cols
        let rows = terminalView.getTerminal().rows

        sshService.onOutput = { [weak terminalView] data in
            let bytes = Array(data)
            DispatchQueue.main.async {
                terminalView?.feed(byteArray: ArraySlice(bytes))
            }
        }

        sshService.startShell(cols: cols, rows: rows)

        // Make terminal first responder for keyboard
        DispatchQueue.main.async {
            terminalView.becomeFirstResponder()
        }

        return terminalView
    }

    public func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // Size changes handled by SwiftTerm internally
    }

    // MARK: - Coordinator (TerminalViewDelegate)

    public class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        let sshService: SSHService
        weak var terminalView: SwiftTerm.TerminalView?

        init(sshService: SSHService) {
            self.sshService = sshService
        }

        /// Called when user types — send input to SSH shell
        public func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            sshService.shellWriter.write(Data(data))
        }

        /// Terminal size changed — resize PTY
        public func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            sshService.shellWriter.resize(cols: newCols, rows: newRows)
        }

        public func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        public func setTerminalIconTitle(source: SwiftTerm.TerminalView, title: String) {}
        public func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        public func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        public func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
        public func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
        public func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
        }
        public func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}
    }
}

#Preview {
    NavigationStack {
        TerminalView(server: .preview)
    }
    .environment(ServerStore())
}

#else
import SwiftUI

public struct TerminalView: View {
    let server: Server

    public var body: some View {
        Text("Terminal view requires iOS")
            .navigationTitle(server.name)
    }
}
#endif
