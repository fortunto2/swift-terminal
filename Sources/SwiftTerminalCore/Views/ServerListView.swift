import SwiftUI

/// Main view — shows a list of saved servers with connection actions.
struct ServerListView: View {
    @Environment(ServerStore.self) private var store
    @State private var showingAddServer = false
    @State private var showingSettings = false
    @State private var showingKeyManagement = false
    @State private var selectedServer: Server?
    @State private var searchText = ""

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
            if store.servers.isEmpty {
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
        .navigationDestination(item: $selectedServer) { server in
            TerminalView(server: server)
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
            ForEach(filteredServers) { server in
                ServerRow(server: server) {
                    selectedServer = server
                }
            }
            .onDelete { offsets in
                store.deleteServer(at: offsets)
            }
        }
    }
}

// MARK: - Server Row

private struct ServerRow: View {
    let server: Server
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
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
}
