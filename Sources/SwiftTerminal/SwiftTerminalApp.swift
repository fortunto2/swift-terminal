import SwiftUI
import SwiftTerminalCore

@main
struct SwiftTerminalApp: App {
    @State private var serverStore = ServerStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ServerListView()
            }
            .environment(serverStore)
        }
    }
}
