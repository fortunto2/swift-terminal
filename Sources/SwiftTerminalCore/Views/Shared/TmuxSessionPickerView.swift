import SwiftUI

/// Picker sheet for discovered tmux sessions on the remote server.
/// Shows session name, window count, and attached status. User can select
/// which sessions to open as tabs.
struct TmuxSessionPickerView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerStore.self) private var store
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessionManager.discoveredTmuxSessions) { info in
                    Button {
                        if selected.contains(info.id) {
                            selected.remove(info.id)
                        } else {
                            selected.insert(info.id)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.name)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    Label("\(info.windowCount) window\(info.windowCount == 1 ? "" : "s")",
                                          systemImage: "rectangle.on.rectangle")
                                    if info.isAttached {
                                        Label("attached", systemImage: "link")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected.contains(info.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title3)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                                    .font(.title3)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Tmux Sessions")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        sessionManager.dismissTmuxPicker()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(selected.isEmpty ? "Skip" : "Open (\(selected.count))") {
                        if selected.isEmpty {
                            sessionManager.dismissTmuxPicker()
                        } else {
                            let toAdopt = sessionManager.discoveredTmuxSessions
                                .filter { selected.contains($0.id) }
                            sessionManager.adoptDiscoveredSessions(toAdopt, using: store)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(false)
                }
                #if canImport(UIKit)
                ToolbarItem(placement: .bottomBar) {
                    Button("Select All") {
                        if selected.count == sessionManager.discoveredTmuxSessions.count {
                            selected.removeAll()
                        } else {
                            selected = Set(sessionManager.discoveredTmuxSessions.map(\.id))
                        }
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Select All") {
                        if selected.count == sessionManager.discoveredTmuxSessions.count {
                            selected.removeAll()
                        } else {
                            selected = Set(sessionManager.discoveredTmuxSessions.map(\.id))
                        }
                    }
                }
                #endif
            }
            .onAppear {
                // Pre-select all sessions
                selected = Set(sessionManager.discoveredTmuxSessions.map(\.id))
            }
        }
    }
}
