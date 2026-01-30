#!/bin/bash
# ci_post_clone.sh — Xcode Cloud post-clone script
# Runs after cloning the repo, before dependency resolution and build.
#
# Environment variables available from Xcode Cloud:
#   CI_WORKSPACE        — path to the workspace
#   CI_DERIVED_DATA_PATH — derived data
#   CI_PRODUCT           — the product being built
#   CI_XCODEBUILD_ACTION — build, test, archive, etc.
#   CI_BRANCH            — current branch
#   CI_COMMIT            — current commit SHA

set -euo pipefail

echo "=== SwiftTerminal CI Post-Clone ==="
echo "Branch: ${CI_BRANCH:-unknown}"
echo "Commit: ${CI_COMMIT:-unknown}"
echo "Action: ${CI_XCODEBUILD_ACTION:-unknown}"
echo "Product: ${CI_PRODUCT:-unknown}"
echo "Xcode: $(xcodebuild -version | head -1)"
echo "Swift: $(swift --version | head -1)"
echo "=================================="

# Navigate to the source root
cd "$CI_WORKSPACE"

# ----- Install XcodeGen if project.yml exists but no .xcodeproj -----
if [ -f "project.yml" ] && [ ! -d "SwiftTerminal.xcodeproj" ]; then
    echo "📦 Installing XcodeGen to generate Xcode project..."
    brew install xcodegen
    echo "🔨 Generating Xcode project from project.yml..."
    xcodegen generate
    echo "✅ Xcode project generated."
fi

# ----- Resolve Swift packages -----
# Xcode Cloud handles this automatically, but if you need
# to pre-resolve or configure packages, do it here.

# ----- Set build number from Xcode Cloud -----
# Xcode Cloud sets CI_BUILD_NUMBER automatically.
# If you need to inject it into Info.plist or other config:
if [ -n "${CI_BUILD_NUMBER:-}" ]; then
    echo "Build number: $CI_BUILD_NUMBER"
fi

echo "✅ Post-clone script completed."
