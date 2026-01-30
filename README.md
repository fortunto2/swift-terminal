# SwiftTerminal 🖥️

Lightweight iOS SSH client with one-tap VPS provisioning for Claude Code.

## Requirements
- Swift 6.1+
- Xcode 16.3+
- macOS 15+ / iOS 18+

## Tech Stack
- **SSH:** Citadel (SwiftNIO SSH)
- **Terminal:** SwiftTerm
- **Key Storage:** iOS Keychain + Secure Enclave
- **UI:** SwiftUI

## Quick Start

### Build on Mac (device)
```bash
git clone git@github.com:fortunto2/swift-terminal.git
cd swift-terminal
open Package.swift  # Opens in Xcode
```
In Xcode:
1. Select your iPhone as target device
2. Set your Team in Signing & Capabilities
3. `Cmd+R` to build and run

### Build from CLI
```bash
swift build
swift test
```

### CI Artifacts
Every push to `main` produces a **simulator build** artifact in GitHub Actions.
Download from: Actions → Build & Test → Artifacts → SwiftTerminal-Simulator

## Install on Device

### Option 1: Xcode (easiest)
1. Clone repo on Mac
2. `open Package.swift`
3. Select device, set Team, build

### Option 2: CI + Signing (automated)
Requires adding secrets to GitHub:
- `APPLE_CERTIFICATE` — p12 certificate (base64)
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE` — mobileprovision (base64)
- `APPLE_TEAM_ID`

See `.github/workflows/build.yml` for details.

## Project Structure
```
SwiftTerminal/
├── Package.swift              — Dependencies & targets
├── Sources/SwiftTerminal/
│   ├── SwiftTerminalApp.swift — @main SwiftUI App
│   ├── Models/                — Server, SSHKey, ProvisioningConfig
│   ├── Services/              — SSH, Keychain, Provisioning, ServerStore
│   ├── Views/                 — SwiftUI screens
│   └── Helpers/               — Provisioning shell scripts
└── Tests/
```

## Features (MVP)
- [x] Server management (add/edit/delete)
- [x] SSH connection via Citadel
- [x] Terminal emulator (SwiftTerm)
- [x] SSH key management with Keychain
- [x] One-tap VPS provisioning (security + Claude Code + dev tools)
- [x] GitHub Actions CI
- [ ] Mosh support
- [ ] Files.app integration
- [ ] Cross-device sync
