# Xcode Cloud CI/CD Setup

## Architecture

This project uses a **hybrid SwiftPM + XcodeGen** approach:

- **`Package.swift`** — defines dependencies and library/test targets (used by `swift build`/`swift test` for quick CI on GitHub Actions)
- **`project.yml`** — XcodeGen spec that generates a proper `.xcodeproj` with iOS app target, bundle identifier, signing, and deployment config
- **`ci_scripts/ci_post_clone.sh`** — Xcode Cloud post-clone script that generates the Xcode project if needed

## Bundle Identifier

```
com.fortunto2.swift-terminal
```

## Deployment Targets

- iOS 18.0+
- macOS 15.0+

## Initial Setup (on Mac)

### 1. Install XcodeGen

```bash
brew install xcodegen
```

### 2. Generate the Xcode Project

```bash
cd swift-terminal
xcodegen generate
```

This creates `SwiftTerminal.xcodeproj` from `project.yml`.

### 3. Open in Xcode & Configure Signing

```bash
open SwiftTerminal.xcodeproj
```

In Xcode:
- Select the **SwiftTerminal** target
- Go to **Signing & Capabilities**
- Set your **Development Team**
- Xcode will auto-manage signing for Xcode Cloud

### 4. Verify Shared Scheme

Go to **Product → Scheme → Manage Schemes**:
- Ensure **SwiftTerminal** scheme exists and **Shared** checkbox is ✅
- The scheme files are already committed at `.swiftpm/xcode/xcshareddata/xcschemes/`

### 5. Commit the Generated Project

```bash
git add SwiftTerminal.xcodeproj
git commit -m "chore: add Xcode project for Xcode Cloud"
git push
```

### 6. Connect to Xcode Cloud

In Xcode:
1. Go to **Product → Xcode Cloud → Create Workflow**
2. Select the **SwiftTerminal** scheme
3. Configure your workflow:
   - **Start Conditions**: Push to `main` branch
   - **Actions**: Build, Test, Archive
   - **Post-Actions**: Deploy to TestFlight (optional)

## CI Scripts

### `ci_scripts/ci_post_clone.sh`
Runs after Xcode Cloud clones the repo. It:
- Logs environment info (branch, commit, Xcode/Swift versions)
- Installs XcodeGen and regenerates the project if `project.yml` exists but `.xcodeproj` doesn't
- Sets build number from `CI_BUILD_NUMBER`

### Adding More Scripts
Xcode Cloud supports these hook scripts in `ci_scripts/`:
- `ci_post_clone.sh` — after clone, before dependency resolution
- `ci_pre_xcodebuild.sh` — before xcodebuild runs
- `ci_post_xcodebuild.sh` — after xcodebuild completes

## Scheme Configuration

The **SwiftTerminal** scheme is configured for:
- **Build**: All targets (run, test, profile, archive, analyze)
- **Test**: SwiftTerminalTests with code coverage
- **Archive**: Release configuration, revealed in Organizer
- **Profile**: Release configuration

## Project Structure

```
swift-terminal/
├── Package.swift                    # SwiftPM (GitHub Actions CI + dependency def)
├── project.yml                      # XcodeGen spec (generates .xcodeproj)
├── SwiftTerminal.xcodeproj/         # Generated Xcode project (for Xcode Cloud)
├── ci_scripts/
│   └── ci_post_clone.sh             # Xcode Cloud post-clone hook
├── Sources/
│   ├── SwiftTerminal/               # App entry point (@main)
│   └── SwiftTerminalCore/           # Core library (models, services, views)
├── Tests/
│   └── SwiftTerminalTests/
└── .swiftpm/xcode/xcshareddata/
    └── xcschemes/                   # Shared schemes for Xcode Cloud
        ├── SwiftTerminal.xcscheme
        └── SwiftTerminalCore.xcscheme
```

## Troubleshooting

### "No schemes found" in Xcode Cloud
- Ensure `.swiftpm/xcode/xcshareddata/xcschemes/` is committed to git
- Ensure `*.xcodeproj` is NOT in `.gitignore`
- Run `xcodegen generate` and commit the project

### Build fails with signing errors
- Set `DEVELOPMENT_TEAM` in `project.yml` or Xcode project settings
- In Xcode Cloud, signing is managed automatically if your Apple Developer account is connected

### SwiftPM dependency resolution fails
- Check `Package.resolved` is committed
- Ensure network access is available in Xcode Cloud environment
