#if canImport(UIKit)
import SwiftUI

/// View for managing port forwards for a session.
public struct PortForwardView: View {
    let session: Session
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showAddForward = false

    public var body: some View {
        List {
            if !session.activeForwards.isEmpty {
                Section("Active Forwards") {
                    ForEach(session.activeForwards) { forward in
                        HStack {
                            Image(systemName: forward.config.type.systemImage)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                if !forward.config.label.isEmpty {
                                    Text(forward.config.label)
                                        .font(.subheadline.weight(.medium))
                                }
                                Text(forward.config.summary)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle()
                                .fill(forward.isActive ? .green : .gray)
                                .frame(width: 8, height: 8)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                session.stopForward(forward.id)
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                        }
                    }
                }
            }

            let savedConfigs = session.server.portForwards.filter { config in
                !session.activeForwards.contains { $0.config.id == config.id }
            }
            if !savedConfigs.isEmpty {
                Section("Saved Forwards") {
                    ForEach(savedConfigs) { config in
                        Button {
                            session.startForward(config)
                        } label: {
                            HStack {
                                Image(systemName: config.type.systemImage)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    if !config.label.isEmpty {
                                        Text(config.label)
                                            .font(.subheadline.weight(.medium))
                                    }
                                    Text(config.summary)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if config.autoStart {
                                    Text("Auto")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.fill.tertiary)
                                        .clipShape(Capsule())
                                }
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }

            if session.activeForwards.isEmpty && session.server.portForwards.isEmpty {
                ContentUnavailableView {
                    Label("No Port Forwards", systemImage: "arrow.left.arrow.right")
                } description: {
                    Text("Add a port forward to tunnel traffic through SSH.")
                }
            }
        }
        .navigationTitle("Port Forwards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddForward = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddForward) {
            NavigationStack {
                AddPortForwardView(session: session)
            }
        }
    }
}

/// Form for adding a new port forward configuration.
struct AddPortForwardView: View {
    let session: Session
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var type: ForwardType = .local
    @State private var localPort = ""
    @State private var remoteHost = "127.0.0.1"
    @State private var remotePort = ""
    @State private var label = ""
    @State private var autoStart = false

    var body: some View {
        Form {
            Section("Type") {
                Picker("Direction", selection: $type) {
                    ForEach(ForwardType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Ports") {
                HStack {
                    Text("Local Port")
                    Spacer()
                    TextField("3000", text: $localPort)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .keyboardType(.numberPad)
                }
                HStack {
                    Text("Remote Host")
                    Spacer()
                    TextField("127.0.0.1", text: $remoteHost)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                HStack {
                    Text("Remote Port")
                    Spacer()
                    TextField("3000", text: $remotePort)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .keyboardType(.numberPad)
                }
            }

            Section {
                TextField("Label (optional)", text: $label)
                Toggle("Auto-start on connect", isOn: $autoStart)
            }

            Section {
                Button("Add & Start") {
                    addAndStart()
                }
                .disabled(!isValid)
            }
        }
        .navigationTitle("Add Port Forward")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var isValid: Bool {
        guard let lp = Int(localPort), lp > 0, lp < 65536,
              let rp = Int(remotePort), rp > 0, rp < 65536,
              !remoteHost.isEmpty else { return false }
        return true
    }

    private func addAndStart() {
        guard let lp = Int(localPort), let rp = Int(remotePort) else { return }

        let config = PortForwardConfig(
            type: type,
            localPort: lp,
            remoteHost: remoteHost,
            remotePort: rp,
            label: label,
            autoStart: autoStart
        )

        // Save to server config if autoStart or label is set
        if autoStart || !label.isEmpty {
            var server = session.server
            server.portForwards.append(config)
            store.updateServer(server)
        }

        // Start immediately
        session.startForward(config)
        dismiss()
    }
}
#endif
