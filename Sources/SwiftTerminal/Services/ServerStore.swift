import Foundation
import SwiftUI

/// Persistent store for servers and SSH keys. Uses JSON + UserDefaults for MVP.
@MainActor
@Observable
final class ServerStore {
    private static let serversKey = "com.swiftterminal.servers"
    private static let keysKey = "com.swiftterminal.sshkeys"

    private(set) var servers: [Server] = []
    private(set) var sshKeys: [SSHKey] = []

    init() {
        loadServers()
        loadKeys()
    }

    // MARK: - Server CRUD

    func addServer(_ server: Server) {
        servers.append(server)
        saveServers()
    }

    func updateServer(_ server: Server) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }

    func deleteServer(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
        saveServers()
    }

    func deleteServer(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        saveServers()
    }

    func markConnected(_ server: Server) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].lastConnected = .now
            saveServers()
        }
    }

    // MARK: - SSH Key CRUD

    func addKey(_ key: SSHKey) {
        sshKeys.append(key)
        saveKeys()
    }

    func deleteKey(_ key: SSHKey) {
        sshKeys.removeAll { $0.id == key.id }
        // Also remove from Keychain
        try? KeychainService.delete(key: key.keychainTag)
        saveKeys()
    }

    func deleteKeys(at offsets: IndexSet) {
        let keysToDelete = offsets.map { sshKeys[$0] }
        for key in keysToDelete {
            try? KeychainService.delete(key: key.keychainTag)
        }
        sshKeys.remove(atOffsets: offsets)
        saveKeys()
    }

    func key(for id: UUID?) -> SSHKey? {
        guard let id else { return nil }
        return sshKeys.first { $0.id == id }
    }

    // MARK: - Persistence

    private func saveServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: Self.serversKey)
    }

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: Self.serversKey),
              let decoded = try? JSONDecoder().decode([Server].self, from: data)
        else { return }
        servers = decoded
    }

    private func saveKeys() {
        guard let data = try? JSONEncoder().encode(sshKeys) else { return }
        UserDefaults.standard.set(data, forKey: Self.keysKey)
    }

    private func loadKeys() {
        guard let data = UserDefaults.standard.data(forKey: Self.keysKey),
              let decoded = try? JSONDecoder().decode([SSHKey].self, from: data)
        else { return }
        sshKeys = decoded
    }
}
