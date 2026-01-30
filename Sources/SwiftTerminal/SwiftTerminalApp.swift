import SwiftUI

@main
struct SwiftTerminalApp: App {
    @State private var serverStore = ServerStore()
    @State private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            LockScreenView()
                .environment(serverStore)
                .environment(sessionManager)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection") {
                    // Post notification that ServerListView can listen to
                }
                .keyboardShortcut("n")
            }
            CommandGroup(after: .textEditing) {
                Button("Clear Terminal") {
                    // Cmd+K — clear terminal
                }
                .keyboardShortcut("k")
            }
        }
        #endif
    }
}
