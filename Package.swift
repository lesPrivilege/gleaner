// swift-tools-version: 6.0
import PackageDescription

#if os(Linux)
let nativeProducts: [Product] = []
let nativeTargets: [Target] = []
let coreExcludes = ["LogWatcher.swift", "MarkdownBlocks.swift"]
let coreTestExcludes = ["LogWatcherTests.swift", "MarkdownBlockTests.swift"]
let portableDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
]
let portableTargets: [Target] = [
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
]
let portableCoreDependencies: [Target.Dependency] = [
    "CSQLite", .product(name: "Crypto", package: "swift-crypto"),
]
let portableCryptoDependencies: [Target.Dependency] = [.product(name: "Crypto", package: "swift-crypto")]
#else
let nativeProducts: [Product] = [.executable(name: "GleanerApp", targets: ["Gleaner"])]
let nativeTargets: [Target] = [
    .target(name: "GleanerUI"),
    .executableTarget(name: "Gleaner", dependencies: ["GleanerCore", "GleanerUI"]),
    .testTarget(name: "GleanerUITests", dependencies: ["GleanerUI"]),
    .testTarget(name: "GleanerTests", dependencies: ["Gleaner", "GleanerCore", "GleanerUI"]),
]
let coreExcludes: [String] = []
let coreTestExcludes: [String] = []
let portableDependencies: [Package.Dependency] = []
let portableTargets: [Target] = []
let portableCoreDependencies: [Target.Dependency] = []
let portableCryptoDependencies: [Target.Dependency] = []
#endif

// Convergence experiments only: never linked by the app, command or MCP and not an
// adopted product API. Keep a typed array so SwiftPM's manifest type checker stays bounded.
let experimentTargets: [Target] = [
    .target(name: "GleanerRetrievalExperiments", dependencies: [.target(name: "GleanerCore")] + portableCryptoDependencies,
            path: "Experiments/GleanerRetrieval"),
    .testTarget(name: "GleanerRetrievalExperimentTests",
                dependencies: ["GleanerCore", "GleanerRetrievalExperiments"],
                path: "Tests/GleanerRetrievalExperimentTests"),
    .testTarget(name: "GleanerRetrievalHeldOutTests",
                dependencies: ["GleanerCore", "GleanerRetrievalExperiments"],
                path: "eval/retrieval/cycle2",
                exclude: ["heldout-labels.json", "heldout-results.json", "heldout-results-first-run.json",
                          "heldout-policy-hashes.json", "native", "results", "measure.py"],
                sources: ["heldout.swift"]),
    .testTarget(name: "GleanerRetrievalCycle3HeldOutTests",
                dependencies: ["GleanerCore", "GleanerRetrievalExperiments"],
                path: "eval/retrieval/cycle3/Tests"),
]

let baseTargets: [Target] = [
        .target(name: "GleanerCore", dependencies: portableCoreDependencies, exclude: coreExcludes),
        .executableTarget(
            name: "gleaner-cli",
            dependencies: [
                "GleanerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(name: "gleaner-spike", dependencies: [.target(name: "GleanerCore")] + portableCryptoDependencies),
        .executableTarget(
            name: "gleaner-index",
            dependencies: ["GleanerCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .testTarget(
            name: "GleanerCoreTests",
            dependencies: [.target(name: "GleanerCore")] + portableCryptoDependencies,
            exclude: coreTestExcludes,
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "GleanerCommandTests", dependencies: ["GleanerCore"]),
]
let allTargets: [Target] = baseTargets + nativeTargets + portableTargets + experimentTargets
let allProducts: [Product] = [
    .library(name: "GleanerCore", targets: ["GleanerCore"]),
    .executable(name: "gleaner", targets: ["gleaner-cli"]),
    .executable(name: "gleaner-spike", targets: ["gleaner-spike"]),
    // A development tool: indexes a synthetic home without the window. Never bundled.
    .executable(name: "gleaner-index", targets: ["gleaner-index"]),
] + nativeProducts
let allDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
    // Logging, which the SDK's Transport names, by the URL the SDK gives, so that the two resolve as one.
    .package(url: "https://github.com/apple/swift-log.git", from: "1.16.1"),
] + portableDependencies
let package = Package(name: "Gleaner", platforms: [.macOS(.v15)],
                      products: allProducts, dependencies: allDependencies, targets: allTargets)
