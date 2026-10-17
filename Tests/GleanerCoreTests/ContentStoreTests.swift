import Foundation
import Testing
@testable import GleanerCore

@Suite struct ContentStoreTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString)")

    func permissions(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func aDeliveredSymlinkNeverChangesTheProjectFile() throws {
        let fm = FileManager.default
        let project = root.appendingPathComponent("project/out")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        let real = project.appendingPathComponent("v3.mp4")
        try "render v3".write(to: real, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: real.path)
        let link = project.appendingPathComponent("latest.mp4")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let store = ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("handoff"))
        let saved = try store.save(link.path)
        #expect(ContentStore.isRegularFile(store.objectURL(saved.sha)))
        let staged = try store.stage(sha: saved.sha, name: "latest.mp4", source: link.path)
        #expect(ContentStore.isRegularFile(staged))
        #expect(permissions(staged) == 0o444)
        #expect(permissions(real) == 0o644)

        // Later renders still land, and the saved copy keeps the delivered bytes.
        try "render v4".write(to: real, atomically: false, encoding: .utf8)
        #expect(try String(contentsOf: store.objectURL(saved.sha), encoding: .utf8) == "render v3")
    }

    @Test func stagingTwoNamesWithTheSameBytesKeepsBoth() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("a.md")
        try "same".write(to: file, atomically: true, encoding: .utf8)
        let store = ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("handoff"))
        let saved = try store.save(file.path)
        let a = try store.stage(sha: saved.sha, name: "a.md", source: nil)
        let b = try store.stage(sha: saved.sha, name: "b.md", source: nil)
        #expect(fm.fileExists(atPath: a.path) && fm.fileExists(atPath: b.path))
    }

    @Test func overlappingStagesOfOneVersionEachHandOverAWholeFile() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("demo.mp4")
        try Data(repeating: 7, count: 1 << 20).write(to: file)
        let sha = try #require(Locator.sha256(file.path))
        let store = ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("handoff"))

        // A row drag and the detail pane can prepare the same version at once.
        let results = await withTaskGroup(of: Result<URL, any Error>.self) { group in
            for _ in 0..<32 {
                group.addTask { Result { try store.stage(sha: sha, name: "demo.mp4", source: file.path) } }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        for result in results {
            let url = try result.get()
            #expect(Locator.sha256(url.path) == sha)
            #expect(permissions(url) == 0o444)
        }
        #expect(try fm.contentsOfDirectory(atPath: store.staging.path) == [sha])
    }
}
