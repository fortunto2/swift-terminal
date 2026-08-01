import SwiftUI

/// Horizontal tab strip showing all active sessions.
/// Displayed at the top of ActiveTerminalContainerView.
///
/// On iOS 26 the controls are Liquid Glass; older systems keep the flat tinted
/// backgrounds. Everything sits in a single `GlassEffectContainer` because glass
/// cannot sample other glass — separate containers would flatten where they overlap.
public struct SessionTabStrip: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerStore.self) private var store

    /// Apple's minimum comfortable hit target. The old strip used ~28pt controls,
    /// which put the close button of a live SSH session inside a 9pt tap area.
    private let minHit: CGFloat = 44

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            strip
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .background(Color.black)
        .sheet(isPresented: Binding(
            get: { sessionManager.showTmuxSessionList },
            set: { if !$0 { sessionManager.dismissTmuxSessionList() } }
        )) {
            if let server = sessionManager.activeSession?.server {
                TmuxSessionListView(server: server)
                    .environment(sessionManager)
                    .environment(store)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var strip: some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) { content }
            }
        } else {
            HStack(spacing: 6) { content }
        }
    }

    @ViewBuilder
    private var content: some View {
        homeButton
        ForEach(sessionManager.sessions) { session in
            tabButton(for: session)
        }
        tmuxButton
        addButton
    }

    // MARK: - Tabs

    private func tabButton(for session: Session) -> some View {
        let isActive = sessionManager.activeSessionID == session.id

        return HStack(spacing: 8) {
            Button {
                sessionManager.switchTo(session.id)
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.state.color)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.server.name)
                            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                            .lineLimit(1)
                        Text(session.tmuxName)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(isActive ? .teal.opacity(0.8) : .gray.opacity(0.8))
                    }
                }
                .foregroundStyle(isActive ? .teal : .gray)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // Its own button, outside the switch target — closing a live SSH session
            // by mis-tapping the tab was far too easy at the old 9pt size.
            Button {
                sessionManager.closeSession(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close \(session.server.name)"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: minHit)
        .tabBackground(isActive: isActive)
        .contextMenu {
            Button {
                sessionManager.closeSession(session.id)
            } label: {
                Label("Detach", systemImage: "eject")
            }
            Button(role: .destructive) {
                sessionManager.closeAndKillSession(session.id)
            } label: {
                Label("Kill Session", systemImage: "trash")
            }
            Divider()
            if !session.state.isConnected {
                Button {
                    sessionManager.reconnectSession(session.id, using: store)
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Controls

    private var homeButton: some View {
        stripButton(icon: "server.rack", tint: .teal, label: "Servers") {
            #if os(macOS)
            NotificationCenter.default.post(name: .switchToServers, object: nil)
            #else
            NotificationCenter.default.post(name: .dismissTerminalContainer, object: nil)
            #endif
        }
    }

    private var tmuxButton: some View {
        stripButton(icon: "rectangle.stack", tint: .teal, label: "tmux sessions") {
            if let active = sessionManager.activeSession {
                sessionManager.fetchRemoteTmuxSessions(via: active)
                sessionManager.showTmuxSessionList = true
            }
        }
        .disabled(sessionManager.activeSession?.state.isConnected != true)
    }

    private var addButton: some View {
        stripButton(icon: "plus", tint: .gray, label: "New connection") {
            #if os(macOS)
            NotificationCenter.default.post(name: .switchToServers, object: nil)
            #else
            NotificationCenter.default.post(name: .dismissTerminalContainer, object: nil)
            #endif
        }
    }

    private func stripButton(
        icon: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: minHit, height: minHit)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .controlBackground(tint: tint)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Backgrounds (glass on 26, flat fill before that)

private extension View {
    @ViewBuilder
    func tabBackground(isActive: Bool) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(
                isActive ? .regular.tint(.teal.opacity(0.25)).interactive() : .regular.interactive(),
                in: .capsule
            )
        } else {
            background(
                Capsule().fill(isActive ? Color.teal.opacity(0.2) : Color.white.opacity(0.08))
            )
        }
    }

    @ViewBuilder
    func controlBackground(tint: Color) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(Circle().fill(tint.opacity(tint == .gray ? 0.08 : 0.15)))
        }
    }
}

extension Notification.Name {
    static let dismissTerminalContainer = Notification.Name("dismissTerminalContainer")
    static let switchToServers = Notification.Name("switchToServers")
}
