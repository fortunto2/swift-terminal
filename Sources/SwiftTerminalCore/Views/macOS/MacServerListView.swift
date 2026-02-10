#if os(macOS)
import SwiftUI
import AppKit

/// macOS server list for the detail pane.
struct MacServerListView: View {
    @Environment(ServerStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    @Binding var sidebarSelection: MacMainView.SidebarItem?
    @State private var showingAddServer = false
    @State private var editingServer: Server?
    @State private var provisioningServer: Server?
    @State private var searchText = ""
    @State private var onboardingSkipped = false

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

    var body: some View {
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
        }
        .sheet(isPresented: $showingAddServer) {
            MacAddServerView()
        }
        .sheet(item: $editingServer) { server in
            MacAddServerView(existingServer: server)
        }
        .sheet(item: $provisioningServer) { server in
            NavigationStack {
                ProvisioningView(server: server)
            }
            .frame(minWidth: 520, minHeight: 500)
        }
        .onAppear {
            sessionManager.restoreSessionsIfNeeded(from: store)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        if store.sshKeys.isEmpty && !onboardingSkipped {
            OnboardingView {
                onboardingSkipped = true
            }
        } else {
            ContentUnavailableView {
                Label("No Servers", systemImage: "server.rack")
            } description: {
                if !store.sshKeys.isEmpty {
                    Text("SSH key ready. Add your first server to connect.")
                } else {
                    Text("Add your first server to get started.")
                }
            } actions: {
                Button("Add Server") {
                    showingAddServer = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Server List

    @ViewBuilder
    private var serverList: some View {
        List {
            Section(sessionManager.sessions.isEmpty ? "" : "Servers") {
                ForEach(filteredServers) { server in
                    MacServerRow(
                        server: server,
                        hasActiveSessions: sessionManager.hasSessions(for: server)
                    ) {
                        connectToServer(server)
                    }
                    .contextMenu {
                        Button {
                            connectToServer(server)
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
                        Divider()
                        Button(role: .destructive) {
                            store.deleteServer(server)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func connectToServer(_ server: Server) {
        sessionManager.createSession(for: server)
        sidebarSelection = .sessions
    }
}

// MARK: - macOS Server Row

private struct MacServerRow: View {
    let server: Server
    let hasActiveSessions: Bool
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(server.name)
                            .font(.headline)
                        if hasActiveSessions {
                            Circle()
                                .fill(.teal)
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
            }
        }
        .tint(.primary)
    }
}
#endif
