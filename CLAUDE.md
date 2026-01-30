# SwiftTerminal — iOS SSH Client for Claude Code

## Product Summary
Lightweight (<15MB) iOS SSH client with one-tap VPS provisioning for Claude Code.

## Target Audience
- 115,000+ active Claude Code developers
- Professional devs on Claude Max ($100-200/mo)
- Indie hackers / solopreneurs

## Unique Value Proposition
"The only SSH client with one-tap VPS setup for Claude Code"

## Tech Stack
| Component | Choice | Size |
|-----------|--------|------|
| SSH | SwiftNIO SSH + Citadel | ~3-4 MB |
| Terminal | SwiftTerm | ~1-2 MB |
| Key Storage | iOS Keychain + Secure Enclave | 0 MB |
| **Total** | | **5-8 MB** |

## Project Structure

```
swift-terminal/
├── Sources/
│   ├── SwiftTerminal/           # App entry point
│   │   └── SwiftTerminalApp.swift
│   ├── SwiftTerminalCore/       # All models, services, views
│   │   ├── Models/
│   │   │   ├── Server.swift
│   │   │   ├── SSHKey.swift
│   │   │   └── ProvisioningConfig.swift
│   │   ├── Services/
│   │   │   ├── SSHService.swift         # Citadel SSH + interactive PTY shell
│   │   │   ├── SSHKeyGenerator.swift    # Real Ed25519/ECDSA/RSA via CryptoKit
│   │   │   ├── KeychainService.swift    # iOS Keychain with biometric protection
│   │   │   ├── ServerStore.swift        # Persistence in Keychain (survives reinstall)
│   │   │   └── ProvisioningService.swift
│   │   ├── Views/
│   │   │   ├── LockScreenView.swift     # Face ID / Touch ID lock
│   │   │   ├── ServerListView.swift     # Main server list
│   │   │   ├── AddServerView.swift      # Add/edit server
│   │   │   ├── TerminalView.swift       # SwiftTerm ↔ SSH PTY bridge
│   │   │   ├── KeyManagementView.swift  # Generate/import SSH keys
│   │   │   ├── ProvisioningView.swift
│   │   │   └── SettingsView.swift
│   │   └── Helpers/
│   │       └── ProvisioningScripts.swift
│   └── SwiftTerminalCLI/        # macOS CLI for local testing
│       └── CLI.swift
├── Tests/SwiftTerminalTests/
├── Package.swift                # SPM (Core lib + App + CLI + Tests)
├── project.yml                  # XcodeGen → .xcodeproj for iOS
├── .mcp.json                    # MCP XcodeBuildMCP for Claude Code builds
└── ci_scripts/ci_post_clone.sh  # Xcode Cloud CI
```

## Build & Run

### iOS (XcodeGen)
```bash
# Generate Xcode project and build
xcodegen generate
xcodebuild -project SwiftTerminal.xcodeproj -scheme SwiftTerminal \
  -destination 'platform=iOS,id=00008120-0011754C2208201E' build

# Or open in Xcode
open SwiftTerminal.xcodeproj
```

### CLI (SPM, macOS)
```bash
swift run SwiftTerminalCLI help
swift run SwiftTerminalCLI keygen mykey
swift run SwiftTerminalCLI connect user@203.0.113.10 -k mykey.key
swift run SwiftTerminalCLI exec user@203.0.113.10 "uname -a" -k mykey.key
```

### MCP Build (Claude Code)
```
mcp__XcodeBuildMCP__build_device   # Build for Rust's iPhone
```

## Test Server
```
Host: 203.0.113.10
User: rustam
Auth: Ed25519 key (no password)
Device ID: 00008120-0011754C2208201E (Rust's iPhone)
```
В DEBUG режиме сервер добавляется автоматически при пустом списке.

## Architecture

### Single App Target
Все исходники (`Sources/SwiftTerminal` + `Sources/SwiftTerminalCore`) объединены в один таргет `SwiftTerminal` для быстрого запуска (без dynamic framework).

### SSH Connection Flow
1. `SSHService.connect()` → Citadel `SSHClient.connect()` (password или Ed25519 key)
2. `SSHService.startShell()` → `client.withPTY()` открывает интерактивный PTY
3. `TerminalViewRepresentable.Coordinator` (TerminalViewDelegate) мостит SwiftTerm ↔ SSH:
   - Ввод с клавиатуры → `shellWriter.write()` → SSH канал
   - SSH output → `terminal.feed()` → экран
   - Resize → `shellWriter.resize()` → PTY resize

### Key Generation
`SSHKeyGenerator` использует CryptoKit:
- **Ed25519**: `Curve25519.Signing.PrivateKey()` — рекомендуемый
- **ECDSA P-256**: `P256.Signing.PrivateKey()` — Secure Enclave совместимый
- **RSA 4096**: `SecKeyCreateRandomKey()` — через Security framework

Публичный ключ в OpenSSH формате, fingerprint SHA256, автокопирование в буфер.

### Security
- **Face ID / Touch ID** — блокировка на старте, повторная при уходе в фон
- **Keychain** — приватные ключи с `.biometryCurrentSet`, данные выживают переустановку
- **NSFaceIDUsageDescription** в Info.plist

### Persistence
`ServerStore` хранит серверы и метаданные ключей в Keychain (не UserDefaults) — данные сохраняются после удаления и переустановки приложения.

## Swift 6 / Concurrency

- **Swift 6.0** со `SWIFT_STRICT_CONCURRENCY: complete`
- `SSHService` — `@MainActor @Observable`
- `ShellWriter` — `@unchecked Sendable` с `NSLock` для thread-safe PTY I/O
- PTY shell в `Task.detached`, UI на MainActor
- `@preconcurrency import Citadel` и `NIOSSH` для совместимости

## Настройки проекта

| Параметр | Значение |
|----------|----------|
| Bundle ID | `com.fortunto2.swift-terminal` |
| Min iOS | 18.0 |
| Swift | 6.0 |
| Dev Team | `8N495BBBLM` |
| Signing | Automatic |

## Roadmap

### MVP (3-4 months)
1. ~~SSH connection (Citadel + SwiftNIO SSH)~~ ✅
2. ~~SwiftTerm interactive terminal~~ ✅
3. ~~iOS Keychain + biometrics for keys~~ ✅
4. Basic VPS provisioning script (security + Claude Code)

### V1.1 (+2 months)
5. Files.app integration (File Provider)
6. Cross-device sync (iCloud or custom)
7. One-tap snippets

### V2.0
8. Push notifications ("Claude needs your input")
9. Voice-to-prompt (dictation)
10. GitHub/GitLab integration

## Monetization
| Tier | Price |
|------|-------|
| Free | $0 — basic SSH, 3 servers |
| Pro Monthly | $4.99/mo |
| Pro Annual | $39.99/yr |
| Lifetime | $79.99 |

## Key Differentiators vs Competition
- **VPS auto-provisioning** — nobody has it
- **Claude Code optimized UX** — not generic SSH
- **App size <15MB** — vs 80-100MB Termius
- **Lifetime pricing** — $79.99 vs $100 Prompt 3
- **Files.app integration** included

## Competitors
- Termius (Free/$10/mo) — 80-100MB, SFTP only in paid
- Prompt 3 ($20/yr or $100) — expensive, slow updates
- Blink Shell ($20/yr) — open source, VS Code integration
- Secure ShellFish ($15/yr or $30) — Files.app, tmux
- Shelly (Free/$4-5) — PuTTY-based, lightweight
- Happy Coder — free, open-source, E2E encrypted (main competitor)

## iOS Constraints
- Background connections killed after 20-30 seconds
- Solution: Mosh + tmux + auto-reconnect
- Secure Enclave supports only P256 — Ed25519/RSA in encrypted Keychain

## References
- Full research PDF: [docs/research-prd.pdf](docs/research-prd.pdf)
