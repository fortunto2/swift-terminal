// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftTerminal",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.9.0"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.8.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
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
