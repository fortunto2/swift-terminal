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
            case "sync":
                try await syncTest(args: Array(args.dropFirst()))
            case "restore-test":
                try await restoreTest(args: Array(args.dropFirst()))
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

// MARK: - Sync Test (mirrors SessionManager.restoreSessionsIfNeeded probe logic)

/// Tests the exact same SSH probe → tmux list → parse flow used by SessionManager.
/// This validates the sync logic without needing SwiftUI/SwiftData.
func syncTest(args: [String]) async throws {
    let (user, host, port, authMethod) = try parseTarget(args)

    print("🔍 SYNC TEST — probing \(user)@\(host):\(port)")
    print("   (Same logic as SessionManager.restoreSessionsIfNeeded)\n")

    // Step 1: Connect probe (same as SessionManager's `let probe = SSHService()`)
    print("Step 1: SSH probe connect...")
    let client = try await connectClient(user: user, host: host, port: port, auth: authMethod)
    print("   ✓ Connected\n")

    // Step 2: Execute tmux list-sessions (same as probe.execute())
    print("Step 2: Query tmux sessions...")
    let tmuxOutput: String
    do {
        let buffer = try await client.executeCommand(
            "tmux list-sessions -F '#{session_name}' 2>/dev/null"
        )
        tmuxOutput = String(buffer: buffer)
        print("   Raw output: \(tmuxOutput.debugDescription)")
    } catch {
        print("   ✗ tmux query failed: \(error)")
        print("   → Would fall back to SwiftData cache")
        try await client.close()
        return
    }

    // Step 3: Parse st-* names (same logic as SessionManager)
    let targetNames = tmuxOutput.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.hasPrefix("st-") }
        .sorted()

    print("   Parsed st-* sessions: \(targetNames)\n")

    // Step 4: Validate each session index
    print("Step 3: Validate session indices...")
    for name in targetNames {
        let indexStr = name.replacingOccurrences(of: "st-", with: "")
        if let idx = Int(indexStr) {
            print("   ✓ \(name) → index \(idx)")
        } else {
            print("   ✗ \(name) → INVALID INDEX '\(indexStr)' — would be SKIPPED!")
        }
    }

    // Step 5: Check what's running in each session
    print("\nStep 4: Check running processes in each session...")
    for name in targetNames {
        do {
            let paneCmd = try await client.executeCommand(
                "tmux list-panes -t '\(name)' -F '#{pane_current_command}' 2>/dev/null"
            )
            let cmd = String(buffer: paneCmd).trimmingCharacters(in: .whitespacesAndNewlines)

            let captureBuf = try await client.executeCommand(
                "tmux capture-pane -t '\(name)' -p 2>/dev/null | tail -5"
            )
            let lastLines = String(buffer: captureBuf).trimmingCharacters(in: .whitespacesAndNewlines)

            print("   \(name): running '\(cmd)'")
            if !lastLines.isEmpty {
                for line in lastLines.split(separator: "\n").suffix(3) {
                    print("      │ \(line)")
                }
            }
        } catch {
            print("   \(name): ✗ could not inspect (\(error))")
        }
    }

    // Step 6: Disconnect probe
    print("\nStep 5: Disconnect probe...")
    try await client.close()
    print("   ✓ Done\n")

    // Summary
    print("═══════════════════════════════════════")
    print("RESULT: Server has \(targetNames.count) st-* sessions")
    print("   Sessions: \(targetNames.joined(separator: ", "))")
    print("   → SessionManager would create \(targetNames.count) Session objects")
    let maxIdx = targetNames.compactMap { Int($0.replacingOccurrences(of: "st-", with: "")) }.max() ?? -1
    print("   → nextIndex would be set to \(maxIdx + 1)")
    print("═══════════════════════════════════════")
}

/// Full restore test: create sessions on server, simulate app restart, verify.
func restoreTest(args: [String]) async throws {
    var testArgs = args
    var sessionCount = 3

    // Parse -n flag for session count
    if let nIdx = testArgs.firstIndex(of: "-n"), nIdx + 1 < testArgs.count {
        sessionCount = Int(testArgs[nIdx + 1]) ?? 3
        testArgs.remove(at: nIdx + 1)
        testArgs.remove(at: nIdx)
    }

    let (user, host, port, authMethod) = try parseTarget(testArgs)

    print("🧪 RESTORE TEST — \(sessionCount) sessions on \(user)@\(host):\(port)\n")

    let client = try await connectClient(user: user, host: host, port: port, auth: authMethod)

    // Step 1: Clean up existing st-* sessions
    print("Step 1: Kill existing st-* sessions...")
    let existingBuf = try await client.executeCommand(
        "tmux list-sessions -F '#{session_name}' 2>/dev/null || true"
    )
    let existing = String(buffer: existingBuf).split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.hasPrefix("st-") }

    for name in existing {
        _ = try await client.executeCommand("tmux kill-session -t '\(name)' 2>/dev/null || true")
        print("   Killed \(name)")
    }
    if existing.isEmpty { print("   (none to kill)") }

    // Step 2: Create test sessions with unique markers
    print("\nStep 2: Create \(sessionCount) test sessions with unique commands...")
    let commands: [(name: String, cmd: String, marker: String)] = (0..<sessionCount).map { i in
        let name = "st-\(i)"
        let marker = "MARKER_\(name.uppercased().replacingOccurrences(of: "-", with: "_"))_\(Int.random(in: 1000...9999))"
        let cmd: String
        switch i % 4 {
        case 0: cmd = "echo '\(marker)' && watch -n2 'echo \(marker) && date'"
        case 1: cmd = "echo '\(marker)' && top -b -d 5"
        case 2: cmd = "echo '\(marker)' && htop 2>/dev/null || top -b -d 3"
        case 3: cmd = "echo '\(marker)' && vmstat 2"
        default: cmd = "echo '\(marker)'"
        }
        return (name, cmd, marker)
    }

    for (name, cmd, marker) in commands {
        _ = try await client.executeCommand("tmux new-session -d -s '\(name)' 2>/dev/null")
        _ = try await client.executeCommand("tmux send-keys -t '\(name)' \"\(cmd)\" Enter 2>/dev/null")
        print("   ✓ Created \(name) — marker: \(marker)")
    }

    // Wait for commands to start
    try await Task.sleep(for: .seconds(2))

    // Step 3: Run probe sync (same as SessionManager would do on restore)
    print("\nStep 3: Probe sync (SessionManager logic)...")
    let tmuxBuf = try await client.executeCommand(
        "tmux list-sessions -F '#{session_name}' 2>/dev/null"
    )
    let targetNames = String(buffer: tmuxBuf).split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.hasPrefix("st-") }
        .sorted()

    print("   Server returns: \(targetNames)")
    print("   Expected: \(commands.map(\.name))")

    if targetNames == commands.map(\.name) {
        print("   ✓ MATCH — all sessions found")
    } else {
        print("   ✗ MISMATCH!")
        let expected = Set(commands.map(\.name))
        let actual = Set(targetNames)
        let missing = expected.subtracting(actual)
        let extra = actual.subtracting(expected)
        if !missing.isEmpty { print("   Missing: \(missing.sorted())") }
        if !extra.isEmpty { print("   Extra: \(extra.sorted())") }
    }

    // Step 4: Verify markers are visible in each session
    print("\nStep 4: Verify markers in session panes...")
    var allMarkersFound = true
    for (name, _, marker) in commands {
        let captureBuf = try await client.executeCommand(
            "tmux capture-pane -t '\(name)' -p 2>/dev/null"
        )
        let content = String(buffer: captureBuf)
        if content.contains(marker) {
            print("   ✓ \(name): marker '\(marker)' found")
        } else {
            print("   ✗ \(name): marker '\(marker)' NOT FOUND")
            allMarkersFound = false
        }

        let cmdBuf = try await client.executeCommand(
            "tmux list-panes -t '\(name)' -F '#{pane_current_command}' 2>/dev/null"
        )
        let running = String(buffer: cmdBuf).trimmingCharacters(in: .whitespacesAndNewlines)
        print("     Running: \(running)")
    }

    // Step 5: Simulate app disconnect + reconnect
    print("\nStep 5: Simulate disconnect → reconnect (app restart)...")
    try await client.close()
    print("   Disconnected probe")

    try await Task.sleep(for: .seconds(1))

    let client2 = try await connectClient(user: user, host: host, port: port, auth: authMethod)
    print("   Reconnected probe")

    let tmuxBuf2 = try await client2.executeCommand(
        "tmux list-sessions -F '#{session_name}' 2>/dev/null"
    )
    let afterNames = String(buffer: tmuxBuf2).split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.hasPrefix("st-") }
        .sorted()

    print("   Sessions after reconnect: \(afterNames)")

    if afterNames == targetNames {
        print("   ✓ All sessions survived disconnect!")
    } else {
        let lost = Set(targetNames).subtracting(Set(afterNames))
        print("   ✗ Lost sessions: \(lost.sorted())")
    }

    // Verify markers still there
    print("\nStep 6: Verify markers survived disconnect...")
    for (name, _, marker) in commands {
        guard afterNames.contains(name) else {
            print("   ✗ \(name): session gone!")
            continue
        }
        let captureBuf = try await client2.executeCommand(
            "tmux capture-pane -t '\(name)' -p 2>/dev/null"
        )
        let content = String(buffer: captureBuf)
        if content.contains(marker) {
            print("   ✓ \(name): marker preserved")
        } else {
            print("   ✗ \(name): marker LOST (process may have crashed)")
        }
    }

    try await client2.close()

    // Summary
    print("\n═══════════════════════════════════════")
    print("RESTORE TEST RESULT:")
    print("   Created: \(commands.count) sessions")
    print("   Found after probe: \(targetNames.count)")
    print("   Survived reconnect: \(afterNames.count)")
    print("   Markers OK: \(allMarkersFound ? "ALL" : "SOME MISSING")")
    if afterNames.count == commands.count && allMarkersFound {
        print("   ✓ PASS — restore logic would work correctly")
    } else {
        print("   ✗ FAIL — some sessions or state lost")
    }
    print("═══════════════════════════════════════")
}

/// Connect a Citadel SSH client (shared helper).
func connectClient(user: String, host: String, port: Int, auth: AuthInput) async throws -> SSHClient {
    switch auth {
    case .password(let password):
        return try await SSHClient.connect(
            host: host, port: port,
            authenticationMethod: .passwordBased(username: user, password: password),
            hostKeyValidator: .acceptAnything(), reconnect: .never
        )
    case .key(let keyPath):
        let hexString = try String(contentsOfFile: keyPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let keyData = try hexToData(hexString)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        return try await SSHClient.connect(
            host: host, port: port,
            authenticationMethod: .ed25519(username: user, privateKey: privateKey),
            hostKeyValidator: .acceptAnything(), reconnect: .never
        )
    }
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

      SwiftTerminalCLI sync user@host[:port] [-k keyfile]
          Test SessionManager probe sync logic — query server tmux sessions

      SwiftTerminalCLI restore-test user@host[:port] [-k keyfile] [-n count]
          Full restore test — create sessions, verify survive disconnect

    Examples:
      SwiftTerminalCLI keygen myserver
      SwiftTerminalCLI connect root@192.168.1.1 -k myserver.key
      SwiftTerminalCLI exec root@192.168.1.1 "ls -la" -p mypassword
      SwiftTerminalCLI sync user@203.0.113.10 -k test.key
      SwiftTerminalCLI restore-test user@203.0.113.10 -k test.key -n 4
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
