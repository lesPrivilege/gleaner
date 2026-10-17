import Foundation
import Testing
@testable import GleanerCore

/// Cases from the original test matrix: the same bytes delivered again, the same bytes in two
/// projects, and a log that disappears.
@Suite struct OriginMatrixTests {
    let root: URL
    let indexer: Indexer
    let delivered = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-matrix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("claude"), withIntermediateDirectories: true)
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
    }

    // MARK: helpers

    /// A project folder holding `out/<file>` with `text`, written before the first delivery.
    func project(_ name: String, file: String, text: String) throws -> URL {
        let folder = root.appendingPathComponent(name)
        let url = folder.appendingPathComponent("out/" + file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: delivered.addingTimeInterval(-30)], ofItemAtPath: url.path)
        return folder
    }

    func stamp(_ date: Date) -> String { date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }

    /// A session's log: one request, and the reply that answers it, both from `cwd`.
    @discardableResult
    func log(_ session: String, cwd: URL, request: String, reply: String, at date: Date) throws -> URL {
        let folder = root.appendingPathComponent("claude/-" + cwd.lastPathComponent)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"\#(request)"},"origin":{"kind":"human"},"timestamp":"\#(stamp(date.addingTimeInterval(-60)))","cwd":"\#(cwd.path)","sessionId":"\#(session)"}"#,
            #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"text","text":"\#(reply)"}]},"timestamp":"\#(stamp(date))","cwd":"\#(cwd.path)","sessionId":"\#(session)"}"#,
        ]
        let url = folder.appendingPathComponent(session + ".jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The saved copies in the store.
    var savedObjects: [String] {
        (FileManager.default.enumerator(atPath: indexer.store.objects.path)?.allObjects as? [String] ?? [])
            .filter { ContentStore.isRegularFile(indexer.store.objects.appendingPathComponent($0)) }
    }

    // MARK: cases

    @Test func theSameBytesDeliveredFromASecondSessionAddADeliveryNotAVersion() throws {
        let praxis = try project("Praxis", file: "demo.mp4", text: "video v1")
        try log("s1", cwd: praxis, request: "Make the demo video", reply: "Video: [demo](out/demo.mp4)", at: delivered)
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let second = delivered.addingTimeInterval(3600)
        try log("s2", cwd: praxis, request: "Send me the demo again", reply: "Here: [demo](out/demo.mp4)", at: second)
        _ = try indexer.run(now: { second.addingTimeInterval(20) })

        let video = try #require(try indexer.registry.artifacts().first)
        #expect(video.deliveries.map(\.request) == ["Send me the demo again", "Make the demo video"])
        #expect(video.deliveries.allSatisfy { $0.capture?.provenance == .atDelivery })
        #expect(Set(video.deliveries.map(\.sha256)).count == 1)
        #expect(savedObjects.count == 1)
    }

    @Test func theSameBytesInTwoProjectsStayTwoArtifacts() throws {
        let atlas = try project("Atlas", file: "report.md", text: "same report")
        let borealis = try project("Borealis", file: "report.md", text: "same report")
        try log("s1", cwd: atlas, request: "Write the Atlas report", reply: "Report: [report](out/report.md)", at: delivered)
        try log("s2", cwd: borealis, request: "Write the Borealis report", reply: "Report: [report](out/report.md)", at: delivered)
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })

        let artifacts = try indexer.registry.artifacts()
        #expect(artifacts.count == 2)
        #expect(artifacts.allSatisfy { $0.deliveries.count == 1 })
        #expect(Set(artifacts.map(\.latest.sha256)).count == 1)
        #expect(Dictionary(uniqueKeysWithValues: artifacts.map { ($0.project, $0.latest.request) })
                == ["Atlas": "Write the Atlas report", "Borealis": "Write the Borealis report"])
    }

    @Test func aDeletedLogLeavesItsDeliveriesAndEvidence() throws {
        let praxis = try project("Praxis", file: "demo.mp4", text: "video v1")
        let log = try log("s1", cwd: praxis, request: "Make the demo video", reply: "Video: [demo](out/demo.mp4)", at: delivered)
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let before = try #require(try indexer.registry.artifacts().first?.latest)

        // The agent prunes the log; later an extractor change rereads every log still there.
        try FileManager.default.removeItem(at: log)
        _ = try indexer.run()
        try indexer.registry.db.execute("PRAGMA user_version = 1")
        let upgraded = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: indexer.store, sources: indexer.sources)
        _ = try upgraded.run()

        let after = try #require(try upgraded.registry.artifacts().first?.latest)
        #expect(after.id == before.id)
        #expect(after.request == "Make the demo video")
        #expect(after.evidence == before.evidence && after.evidence.first?.line == 2)
        #expect(after.capture == before.capture)
        #expect(indexer.store.has(try #require(after.sha256)))
    }
}
