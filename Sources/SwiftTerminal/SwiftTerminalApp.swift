import SwiftUI

@main
struct SwiftTerminalApp: App {
    @State private var serverStore = ServerStore()
    #if canImport(UIKit)
    @State private var sessionManager = SessionManager()
    #endif

    var body: some Scene {
        WindowGroup {
            LockScreenView()
                .environment(serverStore)
                #if canImport(UIKit)
                .environment(sessionManager)
                #endif
        }
    }
}
