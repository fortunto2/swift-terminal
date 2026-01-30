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

## Roadmap

### MVP (3-4 months)
1. SSH/SFTP connection (Citadel + SwiftNIO SSH)
2. SwiftTerm terminal with Mosh support
3. iOS Keychain + biometrics for keys
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

## Revenue Forecast
- Year 1: $45,000-$60,000 net
- Year 2+: $80,000-$120,000 net

## References
- Full research PDF: [docs/research-prd.pdf](docs/research-prd.pdf)
