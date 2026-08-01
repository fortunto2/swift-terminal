import Foundation
import SwiftUI

/// Persistent store for servers and SSH keys.
/// Uses Keychain for persistence — data survives app reinstall.
@MainActor
@Observable
public final class ServerStore {
    private static let serversKey = "com.swiftterminal.servers"
    private static let keysKey = "com.swiftterminal.sshkeys"

    public private(set) var servers: [Server] = []
    public private(set) var sshKeys: [SSHKey] = []

    public init() {
        loadServers()
        loadKeys()
        #if DEBUG
        addDebugDefaultsIfNeeded()
        #endif
    }

    #if DEBUG
    /// Debug convenience only. Points at a throwaway SSH server on the developer's own machine
    /// (`docker run -p 2222:2222 … linuxserver/openssh-server`, user `test`), so the simulator can
    /// reach a real shell without anyone's production host or credentials being baked in.
    private func addDebugDefaultsIfNeeded() {
        if servers.isEmpty {
            servers = [
                Server(
                    name: "Local test (docker)",
                    host: "localhost",
                    port: 2222,
                    username: "test",
                    authMethod: .password,
                    tags: ["local"]
                )
            ]
            saveServers()
        }
    }
    #endif

    // MARK: - Server CRUD

    public func addServer(_ server: Server) {
        servers.append(server)
        saveServers()
    }

    public func updateServer(_ server: Server) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }

    public func deleteServer(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
        saveServers()
    }

    public func deleteServer(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        saveServers()
    }

    public func markConnected(_ server: Server) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].lastConnected = .now
            saveServers()
        }
    }

    // MARK: - SSH Key CRUD

    public func addKey(_ key: SSHKey) {
        sshKeys.append(key)
        saveKeys()
    }

    public func deleteKey(_ key: SSHKey) {
        sshKeys.removeAll { $0.id == key.id }
        try? KeychainService.delete(key: key.keychainTag)
        saveKeys()
    }

    public func deleteKeys(at offsets: IndexSet) {
        let keysToDelete = offsets.map { sshKeys[$0] }
        for key in keysToDelete {
            try? KeychainService.delete(key: key.keychainTag)
        }
        sshKeys.remove(atOffsets: offsets)
        saveKeys()
    }

    public func key(for id: UUID?) -> SSHKey? {
        guard let id else { return nil }
        return sshKeys.first { $0.id == id }
    }

    // MARK: - Persistence (Keychain — survives app reinstall)

    private func saveServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        do {
            try KeychainService.save(key: Self.serversKey, data: data)
        } catch {
            print("[ServerStore] Failed to save servers: \(error)")
        }
    }

    private func loadServers() {
        do {
            guard let data = try KeychainService.load(key: Self.serversKey),
                  let decoded = try? JSONDecoder().decode([Server].self, from: data)
            else { return }
            servers = decoded
        } catch {
            print("[ServerStore] Failed to load servers: \(error)")
        }
    }

    private func saveKeys() {
        guard let data = try? JSONEncoder().encode(sshKeys) else { return }
        do {
            try KeychainService.save(key: Self.keysKey, data: data)
        } catch {
            print("[ServerStore] Failed to save keys: \(error)")
        }
    }

    private func loadKeys() {
        do {
            guard let data = try KeychainService.load(key: Self.keysKey),
                  let decoded = try? JSONDecoder().decode([SSHKey].self, from: data)
            else { return }
            sshKeys = decoded
        } catch {
            print("[ServerStore] Failed to load keys: \(error)")
        }
    }
}
