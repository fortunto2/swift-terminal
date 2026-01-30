import Foundation
import Testing
@testable import SwiftTerminal

@Suite("Server Model")
struct ServerTests {
    @Test("Server creation with defaults")
    func serverDefaults() {
        let server = Server(name: "Test", host: "example.com")
        #expect(server.name == "Test")
        #expect(server.host == "example.com")
        #expect(server.port == 22)
        #expect(server.username == "root")
        #expect(server.authMethod == .key)
        #expect(server.tags.isEmpty)
    }

    @Test("Connection string without custom port")
    func connectionStringDefaultPort() {
        let server = Server(name: "Test", host: "example.com")
        #expect(server.connectionString == "root@example.com")
    }

    @Test("Connection string with custom port")
    func connectionStringCustomPort() {
        let server = Server(name: "Test", host: "example.com", port: 2222)
        #expect(server.connectionString == "root@example.com:2222")
    }

    @Test("Server is Codable")
    func serverCodable() throws {
        let server = Server(name: "Test", host: "example.com", port: 2222, username: "deploy", tags: ["dev"])
        let data = try JSONEncoder().encode(server)
        let decoded = try JSONDecoder().decode(Server.self, from: data)
        #expect(decoded.name == server.name)
        #expect(decoded.host == server.host)
        #expect(decoded.port == server.port)
        #expect(decoded.username == server.username)
        #expect(decoded.tags == server.tags)
    }
}

@Suite("SSH Key Model")
struct SSHKeyTests {
    @Test("SSH key creation")
    func keyCreation() {
        let key = SSHKey(name: "Test Key", publicKey: "ssh-ed25519 AAAA...")
        #expect(key.name == "Test Key")
        #expect(key.keyType == .ed25519)
        #expect(key.keychainTag.starts(with: "com.swiftterminal.key."))
    }

    @Test("SSH key is Codable")
    func keyCodable() throws {
        let key = SSHKey(name: "Test", keyType: .rsa4096, publicKey: "ssh-rsa AAAA...")
        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(SSHKey.self, from: data)
        #expect(decoded.name == key.name)
        #expect(decoded.keyType == .rsa4096)
    }
}

@Suite("Provisioning Config")
struct ProvisioningConfigTests {
    @Test("Default config")
    func defaultConfig() {
        let config = ProvisioningConfig.default
        #expect(config.provider == .hetzner)
        #expect(config.deployUsername == "deploy")
        #expect(config.sshPort == 2222)
        #expect(config.features.contains(.securityHardening))
        #expect(config.features.contains(.claudeCode))
    }

    @Test("Provisioning scripts are non-empty")
    func scriptsExist() {
        for feature in ProvisioningFeature.allCases {
            let script = ProvisioningScripts.script(for: feature)
            #expect(!script.isEmpty, "Script for \(feature.displayName) should not be empty")
        }
    }

    @Test("Full provisioning script contains all features")
    func fullScript() {
        let config = ProvisioningConfig(
            features: [.securityHardening, .claudeCode, .devTools]
        )
        let script = ProvisioningScripts.fullScript(for: config)
        #expect(script.contains("Security Hardening"))
        #expect(script.contains("Claude Code"))
        #expect(script.contains("dev tools"))
        #expect(script.contains("Provisioning complete"))
    }
}

@Suite("Auth Method")
struct AuthMethodTests {
    @Test("All auth methods have display names")
    func displayNames() {
        for method in AuthMethod.allCases {
            #expect(!method.displayName.isEmpty)
            #expect(!method.systemImage.isEmpty)
        }
    }
}

@Suite("Cloud Provider")
struct CloudProviderTests {
    @Test("All providers have display names")
    func displayNames() {
        for provider in CloudProvider.allCases {
            #expect(!provider.displayName.isEmpty)
            #expect(!provider.iconName.isEmpty)
        }
    }
}

@Suite("Provisioning Feature")
struct ProvisioningFeatureTests {
    @Test("All features have metadata")
    func metadata() {
        for feature in ProvisioningFeature.allCases {
            #expect(!feature.displayName.isEmpty)
            #expect(!feature.description.isEmpty)
            #expect(!feature.systemImage.isEmpty)
        }
    }
}
