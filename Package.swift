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
        // Gleaner's components: marks, status, surfaces, controls, motion. SwiftUI and AppKit only;
        // the app binds them to its library (docs/design/components.md).
        .target(name: "GleanerUI"),
        .executableTarget(name: "gleaner-spike", dependencies: ["GleanerCore"]),
        .executableTarget(name: "Gleaner", dependencies: ["GleanerCore", "GleanerUI"]),
        .testTarget(
            name: "GleanerCoreTests",
            dependencies: ["GleanerCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "GleanerUITests", dependencies: ["GleanerUI"]),
        .testTarget(name: "GleanerTests", dependencies: ["Gleaner", "GleanerCore", "GleanerUI"]),
    ]
)
