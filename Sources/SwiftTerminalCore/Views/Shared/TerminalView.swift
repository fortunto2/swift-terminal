import SwiftUI
import SwiftTerm
import os.log

private let scrollLog = Logger(subsystem: "co.superduperai.swift-terminal", category: "scroll")

#if DEBUG
private func scrollPrint(_ msg: String) {
    print("[scroll] \(msg)")
}

private func tvLog(_ msg: String) {
    print("[tv] \(msg)")
}
#else
@inline(__always) private func tvLog(_ msg: String) {}
#endif

#if DEBUG && canImport(UIKit)
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

// MARK: - TerminalView (SwiftUI, cross-platform)

/// SwiftUI wrapper around SwiftTerm's TerminalView for interactive SSH sessions.
/// Operates on a `Session` — uses session.sshService, session.state, and
/// caches the SwiftTerm view in session.terminalView for tab-switch reuse.
public struct TerminalView: View {
    let session: Session

    @Environment(ServerStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    @AppStorage("autoReconnect") private var autoReconnect = true
    @State private var showPasswordPrompt = false
    @State private var passwordInput = ""
    @State private var terminalViewRef = TerminalViewRef()
    #if canImport(UIKit)
    @State private var isKeyboardVisible = false
    #endif
    #if DEBUG && canImport(UIKit)
    @State private var showDebugOverlay = false
    @State private var debugInfo = TerminalDebugInfo()
    @State private var debugTimer: Timer?
    #endif

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch session.state {
            case .disconnected, .connecting:
                connectingOverlay
            case .connected:
                ZStack(alignment: .top) {
                    GeometryReader { geo in
                        if geo.size.width > 0 && geo.size.height > 0 {
                            #if canImport(UIKit)
                            TerminalViewRepresentable(
                                session: session,
                                containerSize: geo.size,
                                isKeyboardVisible: $isKeyboardVisible,
                                terminalViewRef: terminalViewRef
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            #else
                            MacTerminalViewRepresentable(
                                session: session,
                                containerSize: geo.size,
                                terminalViewRef: terminalViewRef
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            #endif
                        }
                    }
                    #if DEBUG && canImport(UIKit)
                    if showDebugOverlay {
                        terminalDebugOverlayView
                    }
                    #endif
                }
            case .reconnecting(let attempt):
                reconnectingOverlay(attempt: attempt)
            case .failed(let message):
                failedOverlay(message: message)
            }
        }
        .toolbar {
            #if canImport(UIKit)
            if session.state.isConnected {
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
            #endif
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if session.state.isConnected {
                        Button {
                            Task { await session.disconnect() }
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    }
                    Button {
                        Task { await connect() }
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                    #if DEBUG && canImport(UIKit)
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
        #if canImport(UIKit)
        .toolbarBackground(.black, for: .bottomBar)
        .toolbarColorScheme(.dark, for: .bottomBar)
        #endif
        .alert("Enter Password", isPresented: $showPasswordPrompt) {
            SecureField("Password", text: $passwordInput)
            Button("Connect") {
                Task { await session.connectWithPassword(passwordInput) }
                passwordInput = ""
            }
            Button("Cancel", role: .cancel) {
                session.state = .disconnected
                passwordInput = ""
            }
        } message: {
            Text("Password for \(session.server.connectionString)")
        }
        .sheet(isPresented: Binding(
            get: { sessionManager.showTmuxPicker },
            set: { if !$0 { sessionManager.dismissTmuxPicker() } }
        )) {
            TmuxSessionPickerView()
                .environment(sessionManager)
                .environment(store)
        }
        .task {
            session.setupDisconnectHandler(using: store, autoReconnect: autoReconnect)
            // Don't re-connect if session is already connected (tab switch reuse)
            if !session.state.isConnected {
                await connect()
            }
            // Sync orphaned tmux sessions from server (runs once per server)
            if session.state.isConnected {
                sessionManager.syncRemoteTmuxSessions(via: session, store: store)
                // Discover user-created tmux sessions and offer to open them
                sessionManager.discoverAllTmuxSessions(via: session, store: store)
            }
        }
        .onDisappear {
            #if DEBUG && canImport(UIKit)
            debugTimer?.invalidate()
            debugTimer = nil
            #endif
        }
        #if DEBUG && canImport(UIKit)
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

    // MARK: - Debug Overlay (iOS only)

    #if DEBUG && canImport(UIKit)
    private var terminalDebugOverlayView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "frame: \(Int(debugInfo.frameWidth))x\(Int(debugInfo.frameHeight))  content: \(Int(debugInfo.contentWidth))x\(Int(debugInfo.contentHeight))  offset: (\(Int(debugInfo.offsetX)), \(Int(debugInfo.offsetY)))")
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
            Text("Connecting to \(session.server.connectionString)...")
                .foregroundStyle(.green)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func failedOverlay(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Connection Failed")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
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
                session.reconnectTask?.cancel()
                session.reconnectTask = nil
                session.state = .failed("Reconnect canceled")
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
    }

    // MARK: - Connection

    private func connect() async {
        if session.server.authMethod == .password {
            session.state = .connecting
            showPasswordPrompt = true
            return
        }
        await session.connect(using: store)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleTerminalKeyboard = Notification.Name("toggleTerminalKeyboard")
}

// MARK: - iOS UIViewRepresentable

#if canImport(UIKit)
import UIKit

public struct TerminalViewRepresentable: UIViewRepresentable {
    let session: Session
    var containerSize: CGSize
    @Binding var isKeyboardVisible: Bool
    let terminalViewRef: TerminalViewRef

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session, isKeyboardVisible: $isKeyboardVisible)
    }

    public func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        // UIView reuse: if session already has a terminal view, return it
        if let existing = session.terminalView {
            tvLog("REUSE terminalView for \(session.tmuxName), delegate=\(String(describing: existing.terminalDelegate)), isFirstResponder=\(existing.isFirstResponder)")
            terminalViewRef.terminalView = existing
            context.coordinator.terminalView = existing

            // Re-assign delegate to the NEW coordinator (old one was deallocated)
            existing.terminalDelegate = context.coordinator

            // Re-attach keyboard observers (they were removed on dismantle)
            context.coordinator.removeObservers()
            attachObservers(to: existing, context: context)

            // Re-target the scroll wheel gesture to the new coordinator
            for gesture in existing.gestureRecognizers ?? [] {
                if let pan = gesture as? UIPanGestureRecognizer,
                   pan.maximumNumberOfTouches == 1 {
                    pan.removeTarget(nil, action: nil)
                    pan.addTarget(context.coordinator, action: #selector(Coordinator.handleScrollWheelPan(_:)))
                    pan.delegate = context.coordinator
                    context.coordinator.scrollWheelPanGesture = pan
                }
            }

            // Update frame
            existing.frame = CGRect(origin: .zero, size: containerSize)
            DispatchQueue.main.async {
                let ok = existing.becomeFirstResponder()
                tvLog("REUSE becomeFirstResponder → \(ok), window=\(existing.window != nil)")
            }
            return existing
        }

        tvLog("CREATE terminalView for \(session.tmuxName)")

        // Create new terminal view
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

        // Cache in session for reuse across tab switches
        session.terminalView = terminalView

        // Replace default accessory with Claude Code keyboard bar
        let accessory = ClaudeCodeAccessoryView(terminalView: terminalView)
        terminalView.inputAccessoryView = accessory

        // Prevent iOS from adding safe-area content insets that shift the
        // terminal content (SwiftUI already accounts for safe areas).
        terminalView.contentInsetAdjustmentBehavior = .never
        terminalView.contentInset = .zero
        terminalView.scrollIndicatorInsets = .zero

        // Disable bounce to prevent overscroll in TUI apps (Claude Code).
        terminalView.bounces = false
        terminalView.alwaysBounceVertical = false
        terminalView.showsVerticalScrollIndicator = false
        terminalView.isScrollEnabled = false

        // Start shell + wire output (via session helper)
        if !session.shellStarted {
            session.startShellIfNeeded()
        }

        // Start auto-start port forwards
        session.startAutoForwards()

        attachObservers(to: terminalView, context: context)

        // Add pan gesture for tmux mouse wheel scrollback.
        // Must take priority over SwiftTerm's own panMouseGesture (which sends
        // click+drag instead of wheel events).
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleScrollWheelPan(_:)))
        panGesture.delegate = context.coordinator
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        terminalView.addGestureRecognizer(panGesture)
        context.coordinator.scrollWheelPanGesture = panGesture

        // Make terminal first responder for keyboard
        DispatchQueue.main.async {
            let ok = terminalView.becomeFirstResponder()
            tvLog("CREATE becomeFirstResponder → \(ok)")
        }

        return terminalView
    }

    private func attachObservers(to terminalView: SwiftTerm.TerminalView, context: Context) {
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

        // Dynamic scroll mode: alt buffer (tmux) → disable UIScrollView scroll,
        // normal buffer → enable for native scrollback
        let terminal = uiView.getTerminal()
        let inAltBuffer = terminal.isCurrentBufferAlternate
        uiView.isScrollEnabled = !inAltBuffer

        // Remove SwiftTerm's dynamically-added panMouseGesture (backup for rangeChanged)
        if let wheelGesture = context.coordinator.scrollWheelPanGesture {
            let builtInPan = uiView.panGestureRecognizer
            for gesture in uiView.gestureRecognizers ?? [] {
                if let pan = gesture as? UIPanGestureRecognizer,
                   pan !== wheelGesture,
                   pan !== builtInPan {
                    uiView.removeGestureRecognizer(pan)
                }
            }
        }
    }

    public static func dismantleUIView(_ uiView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        // Only remove observers — do NOT destroy the terminal view
        // (it's cached in session.terminalView for reuse)
        coordinator.removeObservers()
    }

    // MARK: - Coordinator (TerminalViewDelegate)

    public class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        let session: Session
        weak var terminalView: SwiftTerm.TerminalView?
        var isKeyboardVisible: Binding<Bool>
        var toggleObserver: Any?
        var showObserver: Any?
        var hideObserver: Any?
        var scrollWheelPanGesture: UIPanGestureRecognizer?
        private var lastWheelY: CGFloat = 0

        init(session: Session, isKeyboardVisible: Binding<Bool>) {
            self.session = session
            self.isKeyboardVisible = isKeyboardVisible
        }

        func removeObservers() {
            if let obs = toggleObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = showObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = hideObserver { NotificationCenter.default.removeObserver(obs) }
            toggleObserver = nil
            showObserver = nil
            hideObserver = nil
        }

        deinit {
            removeObservers()
        }

        /// Called when user types — send input to SSH shell
        public func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            tvLog("send \(data.count) bytes")
            session.sshService.shellWriter.write(Data(data))
        }

        /// Terminal size changed — resize PTY
        public func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            tvLog("sizeChanged \(newCols)x\(newRows)")
            session.sshService.shellWriter.resize(cols: newCols, rows: newRows)
        }

        public func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        public func setTerminalIconTitle(source: SwiftTerm.TerminalView, title: String) {}
        public func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        public func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        public func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
        public func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            // Capture before entering MainActor isolation to satisfy Swift 6.
            let wheelGesture = scrollWheelPanGesture
            // rangeChanged is always called on the main thread by SwiftTerm.
            MainActor.assumeIsolated {
                let inAltBuffer = source.getTerminal().isCurrentBufferAlternate

                // Alt buffer (tmux) → disable UIScrollView scroll,
                // normal buffer → enable for native scrollback.
                if source.isScrollEnabled == inAltBuffer {
                    source.isScrollEnabled = !inAltBuffer
                }

                // Remove SwiftTerm's dynamically-added panMouseGesture so it
                // doesn't capture pans before our wheel gesture.  SwiftTerm adds
                // it via mouseModeChanged → enableMousePanGesture; we strip it
                // here because rangeChanged fires on every screen update and
                // catches it right after it's added.
                if let wheelGesture {
                    let builtInPan = source.panGestureRecognizer
                    for gesture in source.gestureRecognizers ?? [] {
                        if let pan = gesture as? UIPanGestureRecognizer,
                           pan !== wheelGesture,
                           pan !== builtInPan {
                            source.removeGestureRecognizer(pan)
                        }
                    }
                }
            }
        }
        public func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
        }
        public func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}
    }
}

// MARK: - Coordinator + UIGestureRecognizerDelegate (tmux scroll wheel)

@MainActor
extension TerminalViewRepresentable.Coordinator: UIGestureRecognizerDelegate {

    /// Whether the terminal is in a state where we should intercept pan
    /// gestures and convert them to mouse wheel events (tmux with mouse on).
    private var shouldSendMouseWheel: Bool {
        guard let tv = terminalView else { return false }
        let terminal = tv.getTerminal()
        return terminal.mouseMode != .off && terminal.isCurrentBufferAlternate
    }

    /// Only begin the scroll-wheel pan when tmux mouse mode is active.
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === scrollWheelPanGesture {
            return shouldSendMouseWheel
        }
        return true
    }

    /// Allow coexistence with SwiftTerm's own gestures when this one
    /// doesn't activate (normal scrollback mode).
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    /// Converts vertical finger pans into mouse wheel escape sequences
    /// (button 64 = scroll up, 65 = scroll down) that tmux understands.
    @objc func handleScrollWheelPan(_ gesture: UIPanGestureRecognizer) {
        guard let tv = terminalView else { return }
        let terminal = tv.getTerminal()

        switch gesture.state {
        case .began:
            lastWheelY = 0
            #if DEBUG
            scrollPrint("wheel gesture BEGAN mouseMode=\(terminal.mouseMode) altBuf=\(terminal.isCurrentBufferAlternate)")
            #endif
        case .changed:
            let translation = gesture.translation(in: tv)
            let deltaY = translation.y - lastWheelY

            // Each ~20pt of finger movement sends one wheel event
            let threshold: CGFloat = 20
            let steps = Int(deltaY / threshold)
            guard steps != 0 else { return }

            lastWheelY += CGFloat(steps) * threshold

            // button 4 = scroll up, button 5 = scroll down
            let button = steps < 0 ? 4 : 5
            let count = abs(steps)

            let flags = terminal.encodeButton(
                button: button,
                release: false,
                shift: false,
                meta: false,
                control: false
            )

            // Send from center of viewport
            let midCol = terminal.cols / 2
            let midRow = terminal.rows / 2

            #if DEBUG
            scrollPrint("wheel \(button == 4 ? "UP" : "DOWN") x\(count) flags=\(flags)")
            #endif
            for _ in 0..<count {
                terminal.sendEvent(buttonFlags: flags, x: midCol, y: midRow)
            }
        default:
            break
        }
    }
}
#endif

// MARK: - macOS NSViewRepresentable

#if os(macOS)
import AppKit

public struct MacTerminalViewRepresentable: NSViewRepresentable {
    let session: Session
    var containerSize: CGSize
    let terminalViewRef: TerminalViewRef

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    public func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        // View reuse: if session already has a terminal view, return it
        if let existing = session.terminalView {
            tvLog("REUSE terminalView for \(session.tmuxName)")
            terminalViewRef.terminalView = existing
            context.coordinator.terminalView = existing
            existing.terminalDelegate = context.coordinator
            existing.frame = CGRect(origin: .zero, size: containerSize)
            DispatchQueue.main.async {
                existing.window?.makeFirstResponder(existing)
            }
            return existing
        }

        tvLog("CREATE terminalView for \(session.tmuxName)")

        let frame = CGRect(origin: .zero, size: containerSize)
        let terminalView = SwiftTerm.TerminalView(frame: frame)

        let fontSize: CGFloat = 14
        terminalView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = .init(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)

        terminalView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminalView
        terminalViewRef.terminalView = terminalView

        // Cache in session for reuse across tab switches
        session.terminalView = terminalView

        // Start shell + wire output (via session helper)
        if !session.shellStarted {
            session.startShellIfNeeded()
        }

        // Start auto-start port forwards
        session.startAutoForwards()

        // Make terminal first responder
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }

        return terminalView
    }

    public func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        let newSize = containerSize
        if abs(nsView.frame.size.height - newSize.height) > 1
            || abs(nsView.frame.size.width - newSize.width) > 1 {
            nsView.frame = CGRect(origin: .zero, size: newSize)
            nsView.needsLayout = true
        }
    }

    public static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        // Don't destroy — cached in session.terminalView for reuse
    }

    // MARK: - Coordinator (TerminalViewDelegate)

    public class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        let session: Session
        weak var terminalView: SwiftTerm.TerminalView?

        init(session: Session) {
            self.session = session
        }

        public func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            tvLog("send \(data.count) bytes")
            session.sshService.shellWriter.write(Data(data))
        }

        public func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            tvLog("sizeChanged \(newCols)x\(newRows)")
            session.sshService.shellWriter.resize(cols: newCols, rows: newRows)
        }

        public func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        public func setTerminalIconTitle(source: SwiftTerm.TerminalView, title: String) {}
        public func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        public func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        public func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
        public func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
        public func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
        }
        public func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}
    }
}
#endif

#Preview {
    NavigationStack {
        Text("Terminal preview requires running session")
    }
}
