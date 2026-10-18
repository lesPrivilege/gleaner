// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gleaner",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GleanerCore", targets: ["GleanerCore"]),
        .executable(name: "gleaner", targets: ["gleaner-cli"]),
        .executable(name: "gleaner-spike", targets: ["gleaner-spike"]),
        // Not "Gleaner": on a case-insensitive disk it would be the same file as the `gleaner` command.
        .executable(name: "GleanerApp", targets: ["Gleaner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
        // Logging, which the SDK's Transport names, by the URL the SDK gives, so that the two resolve as one.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.16.1"),
    ],
    targets: [
        .target(name: "GleanerCore"),
        .executableTarget(
            name: "gleaner-cli",
            dependencies: [
                "GleanerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(name: "gleaner-spike", dependencies: ["GleanerCore"]),
        .executableTarget(name: "Gleaner", dependencies: ["GleanerCore"]),
        .testTarget(
            name: "GleanerCoreTests",
            dependencies: ["GleanerCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "GleanerTests", dependencies: ["Gleaner", "GleanerCore"]),
        .testTarget(name: "GleanerCommandTests", dependencies: ["GleanerCore"]),
    ]
)
