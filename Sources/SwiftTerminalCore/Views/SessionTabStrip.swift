#if canImport(UIKit)
import SwiftUI

/// Horizontal tab strip showing all active sessions.
/// Displayed at the top of ActiveTerminalContainerView.
public struct SessionTabStrip: View {
    @Environment(SessionManager.self) private var sessionManager

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(sessionManager.sessions) { session in
                    tabButton(for: session)
                }
                addButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color.black)
    }

    private func tabButton(for session: Session) -> some View {
        let isActive = sessionManager.activeSessionID == session.id

        return Button {
            sessionManager.switchTo(session.id)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.state.color)
                    .frame(width: 8, height: 8)

                Text(session.server.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)

                Button {
                    sessionManager.closeSession(session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.green.opacity(0.2) : Color.white.opacity(0.08))
            )
            .foregroundStyle(isActive ? .green : .gray)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button {
            // Post notification to dismiss terminal and go back to server list
            NotificationCenter.default.post(name: .dismissTerminalContainer, object: nil)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.gray)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

extension Notification.Name {
    static let dismissTerminalContainer = Notification.Name("dismissTerminalContainer")
}
#endif
