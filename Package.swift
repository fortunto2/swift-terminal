// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftTerminal",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.12.0"),
        .package(url: "https://github.com/fortunto2/SwiftTerm.git", branch: "stable-1.5.1-sync-output"),
    ],
    targets: [
        // Core library — all models, services, views
        .target(
            name: "SwiftTerminalCore",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/SwiftTerminalCore"
        ),
        // App entry point
        .executableTarget(
            name: "SwiftTerminal",
            dependencies: ["SwiftTerminalCore"],
            path: "Sources/SwiftTerminal"
        ),
        // CLI for local macOS testing
        .executableTarget(
            name: "SwiftTerminalCLI",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
            ],
            path: "Sources/SwiftTerminalCLI"
        ),
        // Tests depend on core library only
        .testTarget(
            name: "SwiftTerminalTests",
            dependencies: ["SwiftTerminalCore"],
            path: "Tests/SwiftTerminalTests"
        ),
    ]
)
