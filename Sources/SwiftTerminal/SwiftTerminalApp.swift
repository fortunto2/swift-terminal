import SwiftUI
import SwiftData
import SwiftTerminalCore
import SuperDuperAnalytics

@main
struct SwiftTerminalApp: App {
    @State private var serverStore = ServerStore()
    @State private var sessionManager = SessionManager()

    @Environment(\.scenePhase) private var scenePhase

    /// One source id for both builds — the package reports `ios` or `macos` in `platform`, which
    /// is a column rather than a separate product. Splitting them into two sources would make
    /// "how many people use the terminal" a sum someone has to remember to compute.
    init() {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        Analytics.configure(source: "swift-terminal")
        Analytics.track("app_launched")
    }

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
        // The buffer dies with the process. On a phone this app is opened to check one job and
        // closed again, so without this most launches would never be sent.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Analytics.flush() }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(serverStore)
        }
        #endif
    }
}
