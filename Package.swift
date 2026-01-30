// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftTerminal",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    targets: [
        .executableTarget(
            name: "SwiftTerminal",
            path: "Sources/SwiftTerminal"
        ),
        .testTarget(
            name: "SwiftTerminalTests",
            dependencies: ["SwiftTerminal"],
            path: "Tests/SwiftTerminalTests"
        ),
    ]
)
