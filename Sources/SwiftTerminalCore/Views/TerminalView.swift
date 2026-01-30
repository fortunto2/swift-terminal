#if canImport(UIKit)
import SwiftUI
import UIKit
import SwiftTerm
import os.log

private let scrollLog = Logger(subsystem: "co.superduperai.swift-terminal", category: "scroll")

#if DEBUG
private func scrollPrint(_ msg: String) {
    print("[scroll] \(msg)")
}
#endif

#if DEBUG
struct TerminalDebugInfo {
    var frameWidth: CGFloat = 0
    var frameHeight: CGFloat = 0
    var contentWidth: CGFloat = 0
    var contentHeight: CGFloat = 0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var rows: Int = 0
    var cols: Int = 0
    var isAltBuffer: Bool = false
    var yDisp: Int = 0
    var isScrollEnabled: Bool = true
}
#endif

/// Holds a weak reference to the SwiftTerm.TerminalView so the SwiftUI
/// parent can read metrics for the debug overlay.
final class TerminalViewRef: @unchecked Sendable {
    weak var terminalView: SwiftTerm.TerminalView?
}

/// SwiftUI wrapper around SwiftTerm's TerminalView for interactive SSH sessions.
public struct TerminalView: View {
    let server: Server

    @Environment(ServerStore.self) private var store
    @AppStorage("autoReconnect") private var autoReconnect = true
    @State private var sshService = SSHService()
    @State private var connectionState: ConnectionState = .disconnected
    @State private var errorMessage: String?
    @State private var showPasswordPrompt = false
    @State private var passwordInput = ""
    @State private var isKeyboardVisible = false
    @State private var reconnectAttempt = 0
    @State private var reconnectTask: Task<Void, Never>?
    @State private var terminalViewRef = TerminalViewRef()
    #if DEBUG
    @State private var showDebugOverlay = false
    @State private var debugInfo = TerminalDebugInfo()
    @State private var debugTimer: Timer?
    #endif

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case failed
        case reconnecting(attempt: Int)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch connectionState {
            case .disconnected, .connecting:
                connectingOverlay
            case .connected:
                ZStack(alignment: .top) {
                    GeometryReader { geo in
                        if geo.size.width > 0 && geo.size.height > 0 {
                            TerminalViewRepresentable(
                                sshService: sshService,
                                containerSize: geo.size,
                                isKeyboardVisible: $isKeyboardVisible,
                                terminalViewRef: terminalViewRef
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                        }
                    }
                    #if DEBUG
                    if showDebugOverlay {
                        terminalDebugOverlayView
                    }
                    #endif
                }
            case .reconnecting(let attempt):
                reconnectingOverlay(attempt: attempt)
            case .failed:
                failedOverlay
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if connectionState.isConnected {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        NotificationCenter.default.post(
                            name: .toggleTerminalKeyboard, object: nil
                        )
                    } label: {
                        Image(systemName: isKeyboardVisible
                              ? "keyboard.chevron.compact.down"
                              : "keyboard")
                            .foregroundStyle(.green)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if connectionState.isConnected {
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
                    #if DEBUG
                    Divider()
                    Button {
                        showDebugOverlay.toggle()
                    } label: {
                        Label(
                            showDebugOverlay ? "Hide Debug Info" : "Show Debug Info",
                            systemImage: showDebugOverlay ? "eye.slash" : "ladybug"
                        )
                    }
                    #endif
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .toolbarBackground(.black, for: .bottomBar)
        .toolbarColorScheme(.dark, for: .bottomBar)
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
            setupDisconnectHandler()
            await connect()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sshSessionDisconnected)) { _ in
            guard case .connected = connectionState else { return }
            if autoReconnect {
                startAutoReconnect()
            } else {
                connectionState = .failed
                errorMessage = "Connection lost"
            }
        }
        .onDisappear {
            reconnectTask?.cancel()
            reconnectTask = nil
            #if DEBUG
            debugTimer?.invalidate()
            debugTimer = nil
            #endif
        }
        #if DEBUG
        .onChange(of: showDebugOverlay) { _, show in
            if show {
                startDebugTimer()
            } else {
                debugTimer?.invalidate()
                debugTimer = nil
            }
        }
        #endif
    }

    // MARK: - Debug Overlay

    #if DEBUG
    private var terminalDebugOverlayView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "frame: \(Int(debugInfo.frameWidth))×\(Int(debugInfo.frameHeight))  content: \(Int(debugInfo.contentWidth))×\(Int(debugInfo.contentHeight))  offset: (\(Int(debugInfo.offsetX)), \(Int(debugInfo.offsetY)))")
            Text(verbatim: "rows: \(debugInfo.rows)  cols: \(debugInfo.cols)  altBuf: \(debugInfo.isAltBuffer)  yDisp: \(debugInfo.yDisp)  canScroll: \(debugInfo.isScrollEnabled)")
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.75))
        .cornerRadius(4)
        .padding(.top, 2)
        .allowsHitTesting(false)
    }

    private func startDebugTimer() {
        debugTimer?.invalidate()
        let ref = terminalViewRef
        debugTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in
                guard let tv = ref.terminalView else { return }
                let terminal = tv.getTerminal()
                debugInfo = TerminalDebugInfo(
                    frameWidth: tv.frame.width,
                    frameHeight: tv.frame.height,
                    contentWidth: tv.contentSize.width,
                    contentHeight: tv.contentSize.height,
                    offsetX: tv.contentOffset.x,
                    offsetY: tv.contentOffset.y,
                    rows: terminal.rows,
                    cols: terminal.cols,
                    isAltBuffer: terminal.isCurrentBufferAlternate,
                    yDisp: 0,
                    isScrollEnabled: tv.isScrollEnabled
                )
            }
        }
    }
    #endif

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

    private func reconnectingOverlay(attempt: Int) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.orange)
            Text("Reconnecting...")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Attempt \(attempt)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel") {
                reconnectTask?.cancel()
                reconnectTask = nil
                connectionState = .failed
                errorMessage = "Reconnect canceled"
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
    }

    // MARK: - Auto-Reconnect

    private func setupDisconnectHandler() {
        sshService.onDisconnect = {
            NotificationCenter.default.post(name: .sshSessionDisconnected, object: nil)
        }
    }

    private func startAutoReconnect() {
        reconnectTask?.cancel()
        reconnectAttempt = 0
        reconnectTask = Task {
            let maxAttempts = 5
            while reconnectAttempt < maxAttempts, !Task.isCancelled {
                reconnectAttempt += 1
                connectionState = .reconnecting(attempt: reconnectAttempt)

                // Exponential backoff: 1s, 2s, 4s, 8s, 16s
                let delay = UInt64(pow(2.0, Double(reconnectAttempt - 1))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { return }

                await sshService.disconnect()

                do {
                    try await reconnect()
                    connectionState = .connected
                    reconnectAttempt = 0
                    return
                } catch {
                    // Try next attempt
                }
            }

            if !Task.isCancelled {
                connectionState = .failed
                errorMessage = "Reconnect failed after \(maxAttempts) attempts"
            }
        }
    }

    private func reconnect() async throws {
        switch server.authMethod {
        case .key:
            guard let keyID = server.keyID,
                  let sshKey = store.key(for: keyID),
                  let privateKeyData = try KeychainService.load(key: sshKey.keychainTag) else {
                throw SSHServiceError.authenticationFailed
            }
            try await sshService.connect(
                to: server,
                privateKeyData: privateKeyData,
                keyType: sshKey.keyType
            )
        default:
            throw SSHServiceError.authenticationFailed
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
    var containerSize: CGSize
    @Binding var isKeyboardVisible: Bool
    let terminalViewRef: TerminalViewRef

    public func makeCoordinator() -> Coordinator {
        Coordinator(sshService: sshService, isKeyboardVisible: $isKeyboardVisible)
    }

    public func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let frame = CGRect(origin: .zero, size: containerSize)
        let terminalView = SwiftTerm.TerminalView(frame: frame)
        terminalView.backgroundColor = .black

        let fontSize: CGFloat = 14
        terminalView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = .init(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)

        // Set delegate to capture keyboard input
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminalView
        terminalViewRef.terminalView = terminalView

        // Replace default accessory with Claude Code keyboard bar
        let accessory = ClaudeCodeAccessoryView(terminalView: terminalView)
        terminalView.inputAccessoryView = accessory

        // Start SSH shell and pipe output to terminal
        let cols = terminalView.getTerminal().cols
        let rows = terminalView.getTerminal().rows

        // Prevent iOS from adding safe-area content insets that shift the
        // terminal content (SwiftUI already accounts for safe areas).
        terminalView.contentInsetAdjustmentBehavior = .never
        terminalView.contentInset = .zero
        terminalView.scrollIndicatorInsets = .zero

        // Disable bounce to prevent overscroll in TUI apps (Claude Code).
        terminalView.bounces = false
        terminalView.alwaysBounceVertical = false
        terminalView.showsVerticalScrollIndicator = false
        // Disable touch/gesture scrolling — prevents user from accidentally
        // scrolling into empty scrollback area (black screen).  Programmatic
        // contentOffset changes (SwiftTerm's internal scrollTo) still work.
        terminalView.isScrollEnabled = false

        sshService.onOutput = { [weak terminalView] data in
            let bytes = Array(data)
            DispatchQueue.main.async {
                guard let tv = terminalView else { return }
                // Wrap feed + offset reset in a CATransaction so no
                // intermediate frame renders at the wrong offset
                // (prevents flicker from SwiftTerm's internal scrollTo).
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                tv.feed(byteArray: ArraySlice(bytes))
                tv.contentOffset = .zero
                CATransaction.commit()
            }
        }

        sshService.startShell(cols: cols, rows: rows)

        // Listen for keyboard toggle from toolbar button
        context.coordinator.toggleObserver = NotificationCenter.default.addObserver(
            forName: .toggleTerminalKeyboard, object: nil, queue: .main
        ) { [weak terminalView] _ in
            MainActor.assumeIsolated {
                guard let terminalView else { return }
                if terminalView.isFirstResponder {
                    _ = terminalView.resignFirstResponder()
                } else {
                    _ = terminalView.becomeFirstResponder()
                }
            }
        }

        // Track keyboard show/hide to update binding
        context.coordinator.showObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.async {
                context.coordinator.isKeyboardVisible.wrappedValue = true
            }
        }
        context.coordinator.hideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.async {
                context.coordinator.isKeyboardVisible.wrappedValue = false
            }
        }

        // Make terminal first responder for keyboard
        DispatchQueue.main.async {
            _ = terminalView.becomeFirstResponder()
        }

        return terminalView
    }

    public func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // Resize terminal when container changes (keyboard show/hide)
        let newSize = containerSize
        if abs(uiView.frame.size.height - newSize.height) > 1
            || abs(uiView.frame.size.width - newSize.width) > 1 {
            uiView.frame = CGRect(origin: .zero, size: newSize)
            uiView.setNeedsLayout()
            uiView.layoutIfNeeded()
        }
    }

    public static func dismantleUIView(_ uiView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.removeObservers()
    }

    // MARK: - Coordinator (TerminalViewDelegate)

    public class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        let sshService: SSHService
        weak var terminalView: SwiftTerm.TerminalView?
        var isKeyboardVisible: Binding<Bool>
        var toggleObserver: Any?
        var showObserver: Any?
        var hideObserver: Any?

        init(sshService: SSHService, isKeyboardVisible: Binding<Bool>) {
            self.sshService = sshService
            self.isKeyboardVisible = isKeyboardVisible
        }

        func removeObservers() {
            if let obs = toggleObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = showObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = hideObserver { NotificationCenter.default.removeObserver(obs) }
        }

        deinit {
            removeObservers()
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

extension Notification.Name {
    static let toggleTerminalKeyboard = Notification.Name("toggleTerminalKeyboard")
    static let sshSessionDisconnected = Notification.Name("sshSessionDisconnected")
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
