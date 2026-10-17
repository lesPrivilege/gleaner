import Testing
@testable import GleanerCore

@Suite struct KindTests {
    @Test(arguments: [
        ("mp4", Artifact.Kind.media), ("mov", .media), ("m4a", .media), ("wav", .media), ("mp3", .media),
        ("png", .image), ("svg", .image), ("heic", .image), ("gif", .image),
        ("html", .web), ("htm", .web),
        ("md", .document), ("pdf", .document), ("txt", .document), ("docx", .document), ("pptx", .document), ("key", .document),
        ("swift", .code), ("py", .code), ("css", .code), ("js", .code), ("mjs", .code), ("ts", .code), ("tsx", .code), ("sh", .code), ("patch", .code),
        ("json", .data), ("csv", .data), ("tsv", .data), ("xlsx", .data), ("yaml", .data), ("sqlite", .data),
        ("stl", .model), ("step", .model), ("dwg", .model), ("usdz", .model), ("glb", .model),
        ("dmg", .build), ("zip", .build), ("pkg", .build), ("tar", .build), ("gz", .build),
        ("", .other), ("weirdext", .other),
    ])
    func kinds(_ ext: String, _ kind: Artifact.Kind) {
        #expect(Artifact.kind(ofExtension: ext) == kind, "\(ext)")
    }
}
