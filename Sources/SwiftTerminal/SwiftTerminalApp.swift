import SwiftUI
import SwiftData
import SwiftTerminalCore

@main
struct SwiftTerminalApp: App {
    @State private var serverStore = ServerStore()
    @State private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            iOSMainView()
            #else
            MacMainView()
            #endif
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
        .environment(serverStore)
        .environment(sessionManager)
        .modelContainer(for: PersistedSession.self)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(serverStore)
        }
        #endif
    }
}
