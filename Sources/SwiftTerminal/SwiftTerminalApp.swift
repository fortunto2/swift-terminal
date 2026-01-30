import SwiftUI

@main
struct SwiftTerminalApp: App {
    @State private var serverStore = ServerStore()

    var body: some Scene {
        WindowGroup {
            LockScreenView()
                .environment(serverStore)
        }
    }
}
