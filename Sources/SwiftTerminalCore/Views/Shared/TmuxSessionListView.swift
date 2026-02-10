import SwiftUI

/// On-demand list of all remote tmux sessions on the current server.
/// Shows session name, window count, attached status. Sessions already
/// open as tabs get a "Switch" action; others get "Attach".
struct TmuxSessionListView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerStore.self) private var store
    let server: Server

    var body: some View {
        NavigationStack {
            Group {
                if sessionManager.isFetchingTmuxSessions {
                    ProgressView("Loading sessions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sessionManager.remoteTmuxSessions.isEmpty {
                    ContentUnavailableView(
                        "No Tmux Sessions",
                        systemImage: "rectangle.stack.badge.minus",
                        description: Text("No tmux sessions found on \(server.name).")
                    )
                } else {
                    sessionList
                }
            }
            .navigationTitle("Tmux — \(server.name)")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        sessionManager.dismissTmuxSessionList()
                    }
                }
            }
        }
    }

    private var sessionList: some View {
        List {
            ForEach(sessionManager.remoteTmuxSessions) { tmux in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if tmux.isOpen {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                            }
                            Text(tmux.name)
                                .font(.system(.body, design: .monospaced))
                        }
                        HStack(spacing: 8) {
                            Label(
                                "\(tmux.windowCount) window\(tmux.windowCount == 1 ? "" : "s")",
                                systemImage: "rectangle.on.rectangle"
                            )
                            if tmux.isAttached {
                                Label("attached", systemImage: "link")
                                    .foregroundStyle(.green)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if tmux.isOpen, let localID = tmux.localSessionID {
                        Button("Switch") {
                            sessionManager.switchToTmuxSession(localID: localID)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                    } else {
                        Button("Attach") {
                            sessionManager.attachRemoteTmuxSession(
                                name: tmux.name,
                                server: server,
                                store: store
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        if let active = sessionManager.activeSession {
                            sessionManager.killTmuxSession(name: tmux.name, via: active)
                        }
                    } label: {
                        Label("Kill", systemImage: "trash")
                    }
                }
            }
        }
    }
}
