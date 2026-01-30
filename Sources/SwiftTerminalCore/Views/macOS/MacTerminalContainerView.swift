import SwiftUI

/// macOS terminal container: session tab strip + active terminal view.
/// Presented as a sheet from MacServerListView.
struct MacTerminalContainerView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SessionTabStrip()

            if let session = sessionManager.activeSession {
                TerminalView(session: session)
                    .id(session.id)
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
