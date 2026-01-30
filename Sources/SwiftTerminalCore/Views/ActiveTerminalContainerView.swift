#if canImport(UIKit)
import SwiftUI

/// Full-screen container that shows the tab strip + active terminal session.
/// Presented as a fullScreenCover from ServerListView.
public struct ActiveTerminalContainerView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            SessionTabStrip()

            if let session = sessionManager.activeSession {
                TerminalView(session: session)
                    .id(session.id) // force recreation when switching tabs
            } else {
                ContentUnavailableView {
                    Label("No Active Session", systemImage: "terminal")
                } description: {
                    Text("Go back to add a new connection.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            }
        }
        .background(.black)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .dismissTerminalContainer)) { _ in
            dismiss()
        }
        .onChange(of: sessionManager.sessions.isEmpty) { _, empty in
            if empty {
                dismiss()
            }
        }
    }
}
#endif
