#if os(macOS)
import SwiftUI

/// macOS inline sessions view: tab strip + quick commands + terminal.
/// Displayed in the detail pane when "Sessions" is selected in the sidebar.
struct MacSessionsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerStore.self) private var store

    var body: some View {
        if sessionManager.sessions.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                SessionTabStrip()

                if let session = sessionManager.activeSession {
                    MacQuickCommandsBar(session: session)

                    TerminalView(session: session)
                        .id(session.id)

                    sessionStatusBar(session)
                } else {
                    ContentUnavailableView {
                        Label("No Active Session", systemImage: "terminal")
                    } description: {
                        Text("Select a session tab above.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                }
            }
            .background(.black)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if let session = sessionManager.activeSession {
                        sessionToolbarItems(session)
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private func sessionToolbarItems(_ session: Session) -> some View {
        if session.state.isConnected {
            Button {
                sessionManager.disconnectSession(session.id)
            } label: {
                Label("Disconnect", systemImage: "bolt.slash")
            }
            .help("Disconnect (keep session)")
        } else {
            Button {
                sessionManager.reconnectSession(session.id, using: store)
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
            .help("Reconnect to server")
        }

        Button(role: .destructive) {
            sessionManager.closeSession(session.id)
        } label: {
            Label("Close", systemImage: "xmark.circle")
        }
        .help("Close and remove session")
    }

    // MARK: - Status Bar

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func sessionStatusBar(_ session: Session) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(session.state.color)
                    .frame(width: 7, height: 7)
                Text(session.state.label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }

            statusDivider

            Text(session.server.connectionString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            statusDivider

            Label(session.tmuxName, systemImage: "square.stack")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)

            statusDivider

            Label {
                Text("Created \(Self.timeFormatter.string(from: session.createdAt))")
            } icon: {
                Image(systemName: "clock")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)

            Spacer()

            Text(session.lastActivity, style: .relative)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(white: 0.1))
        .foregroundStyle(.gray)
    }

    private var statusDivider: some View {
        Text("│")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.15))
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Sessions", systemImage: "terminal")
        } description: {
            Text("Connect to a server to start a terminal session.")
        } actions: {
            Text("Go to **Servers** in the sidebar to connect.")
                .foregroundStyle(.secondary)
        }
    }
}
#endif
