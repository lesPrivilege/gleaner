// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gleaner",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GleanerCore", targets: ["GleanerCore"]),
        .executable(name: "gleaner-spike", targets: ["gleaner-spike"]),
        .executable(name: "Gleaner", targets: ["Gleaner"]),
    ],
    targets: [
        .target(name: "GleanerCore"),
        .executableTarget(name: "gleaner-spike", dependencies: ["GleanerCore"]),
        .executableTarget(name: "Gleaner", dependencies: ["GleanerCore"]),
        .testTarget(
            name: "GleanerCoreTests",
            dependencies: ["GleanerCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "GleanerTests", dependencies: ["Gleaner", "GleanerCore"]),
    ]
)
