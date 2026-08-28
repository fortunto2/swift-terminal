#if os(iOS)
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
    @State private var onboardingSkipped = false

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
        // Only once there is something to search. On a first launch the field floated over the
        // onboarding card, cut off the Permissions text and buried "Skip Setup" underneath it.
        .modifier(SearchWhenNotEmpty(text: $searchText, isEnabled: !store.servers.isEmpty))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                settingsMenu
            }
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
            // Restore persisted sessions on first launch
            sessionManager.restoreSessionsIfNeeded(from: store)
            // If sessions exist (restored or still running), show terminal
            if !sessionManager.sessions.isEmpty {
                showTerminal = true
            }
            #if DEBUG
            // `-autoConnect` opens the first server straight away, so the simulator lands in a
            // real shell without a tap (clicks can't be scripted into the simulator).
            if UserDefaults.standard.bool(forKey: "autoConnect"),
               sessionManager.sessions.isEmpty,
               let first = store.servers.first {
                sessionManager.createSession(for: first)
                showTerminal = true
            }
            #endif
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
                if let key = store.sshKeys.last {
                    // The step everyone forgets, and the one that makes the first connection
                    // fail with a bare "authentication failed": the key exists on the phone but
                    // the server has never heard of it.
                    Text("Key \"\(key.name)\" is ready. The server needs its public half in "
                         + "~/.ssh/authorized_keys before it will let you in.")
                } else {
                    Text("Add your first server to get started.")
                }
            } actions: {
                Button("Add Server") {
                    showingAddServer = true
                }
                .buttonStyle(.borderedProminent)

                if let key = store.sshKeys.last {
                    Button("Copy Public Key") {
                        Pasteboard.copy(key.publicKey)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var serverList: some View {
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

            // Servers section
            Section(sessionManager.sessions.isEmpty ? "" : "Servers") {
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
/// `.searchable` applied conditionally. Branching inside a modifier rather than at the call site
/// keeps the ~40 lines of toolbar, sheets and cover that follow it in one branch instead of two.
private struct SearchWhenNotEmpty: ViewModifier {
    @Binding var text: String
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $text, prompt: "Search servers...")
        } else {
            content
        }
    }
}
#endif
