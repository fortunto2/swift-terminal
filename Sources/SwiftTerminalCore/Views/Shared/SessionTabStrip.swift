import SwiftUI

/// Horizontal tab strip showing all active sessions.
/// Displayed at the top of ActiveTerminalContainerView.
public struct SessionTabStrip: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerStore.self) private var store

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                homeButton
                ForEach(sessionManager.sessions) { session in
                    tabButton(for: session)
                }
                tmuxButton
                addButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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

    private func tabButton(for session: Session) -> some View {
        let isActive = sessionManager.activeSessionID == session.id

        return Button {
            sessionManager.switchTo(session.id)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.state.color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.server.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Text(session.tmuxName)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(isActive ? .teal.opacity(0.7) : .gray.opacity(0.7))
                }

                Button {
                    sessionManager.closeSession(session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.teal.opacity(0.2) : Color.white.opacity(0.08))
            )
            .foregroundStyle(isActive ? .teal : .gray)
        }
        .buttonStyle(.plain)
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

    private var homeButton: some View {
        Button {
            #if os(macOS)
            NotificationCenter.default.post(name: .switchToServers, object: nil)
            #else
            NotificationCenter.default.post(name: .dismissTerminalContainer, object: nil)
            #endif
        } label: {
            Image(systemName: "server.rack")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.teal)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.teal.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }

    private var tmuxButton: some View {
        Button {
            if let active = sessionManager.activeSession {
                sessionManager.fetchRemoteTmuxSessions(via: active)
                sessionManager.showTmuxSessionList = true
            }
        } label: {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.teal)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.teal.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .disabled(sessionManager.activeSession?.state.isConnected != true)
    }

    private var addButton: some View {
        Button {
            #if os(macOS)
            NotificationCenter.default.post(name: .switchToServers, object: nil)
            #else
            NotificationCenter.default.post(name: .dismissTerminalContainer, object: nil)
            #endif
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.gray)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

extension Notification.Name {
    static let dismissTerminalContainer = Notification.Name("dismissTerminalContainer")
    static let switchToServers = Notification.Name("switchToServers")
}
