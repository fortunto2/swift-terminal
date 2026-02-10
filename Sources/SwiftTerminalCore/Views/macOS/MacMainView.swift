#if os(macOS)
import SwiftUI
import SwiftData

/// macOS root view: NavigationSplitView with sidebar for Sessions, Servers, SSH Keys.
public struct MacMainView: View {
    public init() {}
    @Environment(ServerStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext

    enum SidebarItem: Hashable {
        case sessions
        case servers
        case keys
    }

    @State private var selection: SidebarItem? = .servers

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label {
                        HStack {
                            Text("Sessions")
                            Spacer()
                            if sessionManager.sessions.count > 0 {
                                Text("\(sessionManager.sessions.count)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.teal.opacity(0.2))
                                    .foregroundStyle(.teal)
                                    .clipShape(Capsule())
                            }
                        }
                    } icon: {
                        Image(systemName: "terminal")
                    }
                    .tag(SidebarItem.sessions)

                    Label("Servers", systemImage: "server.rack")
                        .tag(SidebarItem.servers)
                    Label("SSH Keys", systemImage: "key.fill")
                        .tag(SidebarItem.keys)
                }
            }
            .navigationTitle("Terminal")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .sessions:
                MacSessionsView()
            case .servers:
                NavigationStack {
                    MacServerListView(sidebarSelection: $selection)
                }
            case .keys:
                NavigationStack {
                    MacKeyListView()
                }
            case nil:
                ContentUnavailableView {
                    Label("Select a Section", systemImage: "sidebar.left")
                } description: {
                    Text("Choose Sessions, Servers, or SSH Keys from the sidebar.")
                }
            }
        }
        .onAppear {
            sessionManager.setModelContext(modelContext)
            sessionManager.restoreSessionsIfNeeded(from: store)
            if !sessionManager.sessions.isEmpty {
                selection = .sessions
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToServers)) { _ in
            selection = .servers
        }
    }
}
#endif
