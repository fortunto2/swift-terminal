import Foundation
import CryptoKit
import Citadel

// MARK: - SwiftTerminal CLI — local testing tool

@main
struct CLI {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())

        guard let command = args.first else {
            printUsage()
            return
        }

        do {
            switch command {
            case "keygen":
                try keygen(args: Array(args.dropFirst()))
            case "connect":
                try await connect(args: Array(args.dropFirst()))
            case "exec":
                try await exec(args: Array(args.dropFirst()))
            case "help", "--help", "-h":
                printUsage()
            default:
                print("Unknown command: \(command)")
                printUsage()
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Commands

func keygen(args: [String]) throws {
    let name = args.first ?? "test-key"

    print("Generating Ed25519 key '\(name)'...")

    let privateKey = Curve25519.Signing.PrivateKey()
    let publicKeyBytes = privateKey.publicKey.rawRepresentation

    var blob = Data()
    blob.appendSSHString("ssh-ed25519")
    blob.appendSSHBytes(publicKeyBytes)

    let publicKeyOpenSSH = "ssh-ed25519 \(blob.base64EncodedString()) \(name)@cli"

    let hash = SHA256.hash(data: blob)
    let fingerprint = "SHA256:\(Data(hash).base64EncodedString().replacingOccurrences(of: "=", with: ""))"

    let privateKeyHex = privateKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()

    print()
    print("Public key (add to ~/.ssh/authorized_keys):")
    print(publicKeyOpenSSH)
    print()
    print("Fingerprint: \(fingerprint)")
    print()
    print("Private key (raw hex, for testing):")
    print(privateKeyHex)
    print()

    let pubPath = "\(name).pub"
    try publicKeyOpenSSH.write(toFile: pubPath, atomically: true, encoding: .utf8)
    print("Saved: \(pubPath)")

    let privPath = "\(name).key"
    try privateKeyHex.write(toFile: privPath, atomically: true, encoding: .utf8)
    print("Saved: \(privPath)")
}

func connect(args: [String]) async throws {
    let (user, host, port, authMethod) = try parseTarget(args)

    print("Connecting to \(user)@\(host):\(port)...")

    let client: SSHClient
    switch authMethod {
    case .password(let password):
        client = try await SSHClient.connect(
            host: host, port: port,
            authenticationMethod: .passwordBased(username: user, password: password),
            hostKeyValidator: .acceptAnything(), reconnect: .never
        )
    case .key(let keyPath):
        let hexString = try String(contentsOfFile: keyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let keyData = try hexToData(hexString)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        client = try await SSHClient.connect(
            host: host, port: port,
            authenticationMethod: .ed25519(username: user, privateKey: privateKey),
            hostKeyValidator: .acceptAnything(), reconnect: .never
        )
    }

    print("Connected!")
    let buffer = try await client.executeCommand("echo 'SwiftTerminal CLI connected successfully' && uname -a")
    print(String(buffer: buffer))
    try await client.close()
    print("Disconnected.")
}

func exec(args: [String]) async throws {
    guard args.count >= 2 else {
        print("Usage: SwiftTerminalCLI exec user@host[:port] \"command\" [-p password | -k keyfile]")
        return
    }

    let targetArgs = [args[0]] + Array(args.dropFirst(2))
    let (user, host, port, authMethod) = try parseTarget(targetArgs)
    let command = args[1]

    print("Executing on \(user)@\(host):\(port): \(command)")

    let client: SSHClient
    switch authMethod {
    case .password(let password):
        client = try await SSHClient.connect(
            host: host, port: port,
            authenticationMethod: .passwordBased(username: user, password: password),
            hostKeyValidator: .acceptAnything(), reconnect: .never
        )
    case .key(let keyPath):
        let hexString = try String(contentsOfFile: keyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let keyData = try hexToData(hexString)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        client = try await SSHClient.connect(
            host: host, port: port,
            authenticationMethod: .ed25519(username: user, privateKey: privateKey),
            hostKeyValidator: .acceptAnything(), reconnect: .never
        )
    }

    let buffer = try await client.executeCommand(command)
    print(String(buffer: buffer))
    try await client.close()
}

// MARK: - Helpers

enum AuthInput {
    case password(String)
    case key(String)
}

func parseTarget(_ args: [String]) throws -> (user: String, host: String, port: Int, auth: AuthInput) {
    guard let target = args.first else {
        throw CLIError.missingTarget
    }

    let parts = target.split(separator: "@", maxSplits: 1)
    let user: String
    let hostPort: String

    if parts.count == 2 {
        user = String(parts[0])
        hostPort = String(parts[1])
    } else {
        user = "root"
        hostPort = target
    }

    let hpParts = hostPort.split(separator: ":", maxSplits: 1)
    let host = String(hpParts[0])
    let port = hpParts.count == 2 ? (Int(hpParts[1]) ?? 22) : 22

    let remaining = Array(args.dropFirst())
    var auth: AuthInput = .password("")

    var i = 0
    while i < remaining.count {
        switch remaining[i] {
        case "-p":
            i += 1
            guard i < remaining.count else { throw CLIError.missingValue("-p") }
            auth = .password(remaining[i])
        case "-k":
            i += 1
            guard i < remaining.count else { throw CLIError.missingValue("-k") }
            auth = .key(remaining[i])
        default:
            break
        }
        i += 1
    }

    return (user, host, port, auth)
}

func hexToData(_ hex: String) throws -> Data {
    var data = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let nextIndex = hex.index(index, offsetBy: 2)
        guard nextIndex <= hex.endIndex,
              let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
            throw CLIError.invalidHex
        }
        data.append(byte)
        index = nextIndex
    }
    return data
}

func printUsage() {
    print("""
    SwiftTerminal CLI — local testing tool

    Usage:
      SwiftTerminalCLI keygen [name]
          Generate Ed25519 key pair, save to <name>.pub and <name>.key

      SwiftTerminalCLI connect user@host[:port] [-p password | -k keyfile]
          Test SSH connection and run uname

      SwiftTerminalCLI exec user@host[:port] "command" [-p password | -k keyfile]
          Execute a command over SSH

    Examples:
      SwiftTerminalCLI keygen myserver
      SwiftTerminalCLI connect root@192.168.1.1 -k myserver.key
      SwiftTerminalCLI exec root@192.168.1.1 "ls -la" -p mypassword
    """)
}

// MARK: - Errors

enum CLIError: LocalizedError {
    case missingTarget
    case missingValue(String)
    case invalidHex

    var errorDescription: String? {
        switch self {
        case .missingTarget: "Missing target (user@host)"
        case .missingValue(let flag): "Missing value for \(flag)"
        case .invalidHex: "Invalid hex string"
        }
    }
}

// MARK: - Data SSH helpers

extension Data {
    mutating func appendSSHString(_ string: String) {
        let bytes = Data(string.utf8)
        appendSSHBytes(bytes)
    }

    mutating func appendSSHBytes(_ bytes: Data) {
        var length = UInt32(bytes.count).bigEndian
        append(Data(bytes: &length, count: 4))
        append(bytes)
    }
}
