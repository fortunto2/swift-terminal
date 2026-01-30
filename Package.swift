// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftTerminal",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SwiftTerminalCore",
            targets: ["SwiftTerminal"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.9.0"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.8.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "SwiftTerminal",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/SwiftTerminal"
        ),
        .testTarget(
            name: "SwiftTerminalTests",
            dependencies: ["SwiftTerminal"],
            path: "Tests/SwiftTerminalTests"
        ),
    ]
)
