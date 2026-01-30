import SwiftUI

/// macOS root view: NavigationSplitView with sidebar for Servers, SSH Keys, Settings.
struct MacMainView: View {
    @Environment(ServerStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager

    enum SidebarItem: Hashable {
        case servers
        case keys
    }

    @State private var selection: SidebarItem? = .servers

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
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
            case .servers:
                NavigationStack {
                    MacServerListView()
                }
            case .keys:
                NavigationStack {
                    MacKeyListView()
                }
            case nil:
                ContentUnavailableView {
                    Label("Select a Section", systemImage: "sidebar.left")
                } description: {
                    Text("Choose Servers or SSH Keys from the sidebar.")
                }
            }
        }
    }
}
