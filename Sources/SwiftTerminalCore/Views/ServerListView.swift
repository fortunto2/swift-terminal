#if canImport(UIKit)
import SwiftUI

/// Main view — shows a list of saved servers with connection actions.
public struct ServerListView: View {
    @Environment(ServerStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    @State private var showingAddServer = false
    @State private var showingSettings = false
    @State private var showingKeyManagement = false
    @State private var provisioningServer: Server?
    @State private var editingServer: Server?
    @State private var showTerminal = false
    @State private var searchText = ""

    public init() {}

    private var filteredServers: [Server] {
        if searchText.isEmpty {
            store.servers
        } else {
            store.servers.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.host.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }

    public var body: some View {
        Group {
            if store.servers.isEmpty && sessionManager.sessions.isEmpty {
                emptyState
            } else {
                serverList
            }
        }
        .navigationTitle("Servers")
        .searchable(text: $searchText, prompt: "Search servers...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                settingsMenu
            }
            #else
            ToolbarItem(placement: .automatic) {
                settingsMenu
            }
            #endif
        }
        .sheet(isPresented: $showingAddServer) {
            NavigationStack {
                AddServerView()
            }
        }
        .sheet(isPresented: $showingKeyManagement) {
            NavigationStack {
                KeyManagementView()
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(item: $editingServer) { server in
            NavigationStack {
                AddServerView(existingServer: server)
            }
        }
        .sheet(item: $provisioningServer) { server in
            NavigationStack {
                ProvisioningView(server: server)
            }
        }
        .fullScreenCover(isPresented: $showTerminal) {
            ActiveTerminalContainerView()
        }
        .onAppear {
            // If sessions exist when returning, show terminal immediately
            if !sessionManager.sessions.isEmpty {
                showTerminal = true
            }
        }
    }

    // MARK: - Subviews

    private var settingsMenu: some View {
        Menu {
            Button {
                showingKeyManagement = true
            } label: {
                Label("SSH Keys", systemImage: "key.fill")
            }
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Servers", systemImage: "server.rack")
        } description: {
            Text("Add your first server to get started.")
        } actions: {
            Button("Add Server") {
                showingAddServer = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var serverList: some View {
        @Bindable var store = store
        List {
            // Active Sessions section
            if !sessionManager.sessions.isEmpty {
                Section("Active Sessions") {
                    ForEach(sessionManager.sessions) { session in
                        Button {
                            sessionManager.switchTo(session.id)
                            showTerminal = true
                        } label: {
                            HStack {
                                Circle()
                                    .fill(session.state.color)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.server.name)
                                        .font(.headline)
                                    Text(session.state.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                sessionManager.closeSession(session.id)
                            } label: {
                                Label("Close", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
            }

            // Quick Reconnect — recent servers (no active session) after app restart
            let recentServers = sessionManager.recentServersForReconnect(from: store.servers)
            if !recentServers.isEmpty && sessionManager.sessions.isEmpty {
                Section {
                    ForEach(recentServers) { server in
                        Button {
                            sessionManager.createSession(for: server)
                            showTerminal = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name)
                                        .font(.headline)
                                    Text(server.connectionString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("Quick Reconnect")
                } footer: {
                    Text("Tap to reconnect to a recent server. tmux sessions may still be alive.")
                }
            }

            // Servers section
            Section(sessionManager.sessions.isEmpty && recentServers.isEmpty ? "" : "Servers") {
                ForEach(filteredServers) { server in
                    ServerRow(
                        server: server,
                        hasActiveSessions: sessionManager.hasSessions(for: server)
                    ) {
                        sessionManager.createSession(for: server)
                        showTerminal = true
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            provisioningServer = server
                        } label: {
                            Label("Provision", systemImage: "play.fill")
                        }
                        .tint(.purple)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let idx = store.servers.firstIndex(where: { $0.id == server.id }) {
                                store.deleteServer(at: IndexSet(integer: idx))
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingServer = server
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button {
                            sessionManager.createSession(for: server)
                            showTerminal = true
                        } label: {
                            Label("Connect", systemImage: "terminal")
                        }
                        Button {
                            editingServer = server
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            provisioningServer = server
                        } label: {
                            Label("Provision", systemImage: "play.fill")
                        }
                    }
                }
                .onDelete { offsets in
                    store.deleteServer(at: offsets)
                }
            }
        }
    }
}

// MARK: - Server Row

private struct ServerRow: View {
    let server: Server
    let hasActiveSessions: Bool
    let onConnect: () -> Void

    public var body: some View {
        Button(action: onConnect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(server.name)
                            .font(.headline)
                        if hasActiveSessions {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text(server.connectionString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !server.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(server.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.fill.tertiary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                Spacer()
                Image(systemName: server.authMethod.systemImage)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
    }
}

#Preview {
    NavigationStack {
        ServerListView()
    }
    .environment(ServerStore())
    .environment(SessionManager())
}

#else
import SwiftUI

public struct ServerListView: View {
    public init() {}

    public var body: some View {
        Text("Server list requires iOS")
    }
}
#endif
