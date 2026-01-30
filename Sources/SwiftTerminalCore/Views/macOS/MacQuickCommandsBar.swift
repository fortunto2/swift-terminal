import SwiftUI

/// Quick commands bar for macOS terminal sessions.
/// Provides one-click access to Claude Code commands and control sequences.
struct MacQuickCommandsBar: View {
    let session: Session

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                claudeMenu
                divider
                commandButton("/help", text: "/help")
                commandButton("/compact", text: "/compact")
                commandButton("/clear", text: "/clear")
                commandButton("/cost", text: "/cost")
                commandButton("/model", text: "/model")
                commandButton("/config", text: "/config")
                commandButton("/doctor", text: "/doctor")
                divider
                controlButton("^C", bytes: [0x03])
                controlButton("^D", bytes: [0x04])
                controlButton("^Z", bytes: [0x1A])
                controlButton("^L", bytes: [0x0C])
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(white: 0.12))
    }

    // MARK: - Claude Menu

    private var claudeMenu: some View {
        Menu {
            Button("claude") { sendText("claude") }
            Button("claude -c (continue)") { sendText("claude -c") }
            Button("claude -r (resume)") { sendText("claude -r") }
            Divider()
            Button("claude --dangerously-skip-permissions") {
                sendText("claude --dangerously-skip-permissions")
            }
        } label: {
            HStack(spacing: 4) {
                Text("claude")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.2))
            .foregroundStyle(.green)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Buttons

    private func commandButton(_ label: String, text: String) -> some View {
        Button {
            sendText(text)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(.gray)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func controlButton(_ label: String, bytes: [UInt8]) -> some View {
        Button {
            sendBytes(bytes)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }

    // MARK: - Send Helpers

    private func sendText(_ text: String) {
        let data = Data((text + "\n").utf8)
        session.sshService.shellWriter.write(data)
    }

    private func sendBytes(_ bytes: [UInt8]) {
        session.sshService.shellWriter.write(Data(bytes))
    }
}
