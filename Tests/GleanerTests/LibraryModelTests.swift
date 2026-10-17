import Foundation
import Testing
@testable import Gleaner
@testable import GleanerCore

/// The library window's decisions on a synthetic machine: which delivery a click lands on, which
/// bytes Quick Look and Compare show, and what stays shown when a read fails.
@MainActor @Suite struct LibraryModelTests {
    let root: URL
    let project: URL
    let indexer: Indexer
    let delivered = Date(timeIntervalSince1970: 1_790_000_000)

    /// A video delivered three times (1 and 2 the same bytes, 1 first seen later, 3 new bytes), and
    /// notes delivered with the first.
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-model-\(UUID().uuidString)")
        project = root.appendingPathComponent("Praxis")
        let fm = FileManager.default
        try fm.createDirectory(at: project.appendingPathComponent("out"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("claude/-Praxis"), withIntermediateDirectories: true)
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))

        let second = delivered.addingTimeInterval(3600), third = delivered.addingTimeInterval(7200)
        try write("video v1", to: "out/demo.mp4", modified: delivered.addingTimeInterval(-30))
        try write("notes n1", to: "out/notes.md", modified: delivered.addingTimeInterval(-30))
        try appendLog([
            user("Make the demo video", at: delivered.addingTimeInterval(-600)),
            assistant("Video: [demo](out/demo.mp4). Notes: [notes](out/notes.md)", at: delivered),
            user("Render it again", at: second.addingTimeInterval(-300)),
            assistant("Rendered again: [demo](out/demo.mp4)", at: second),
        ])
        _ = try indexer.run(now: { second.addingTimeInterval(20) })
        try write("video v2", to: "out/demo.mp4", modified: third.addingTimeInterval(-30))
        try appendLog([
            user("Make it shorter", at: third.addingTimeInterval(-300)),
            assistant("Shorter: [demo](out/demo.mp4)", at: third),
        ])
        _ = try indexer.run(now: { third.addingTimeInterval(20) })
    }

    // MARK: helpers

    func write(_ text: String, to relative: String, modified: Date) throws {
        let url = project.appendingPathComponent(relative)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    func appendLog(_ lines: [String]) throws {
        let url = root.appendingPathComponent("claude/-Praxis/session-1.jsonl")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try (existing + lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func stamp(_ date: Date) -> String { date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }

    func user(_ text: String, at date: Date) -> String {
        #"{"type":"user","message":{"role":"user","content":"\#(text)"},"origin":{"kind":"human"},"timestamp":"\#(stamp(date))","cwd":"\#(project.path)","sessionId":"s1"}"#
    }

    func assistant(_ text: String, at date: Date) -> String {
        #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"text","text":"\#(text)"}]},"timestamp":"\#(stamp(date))","cwd":"\#(project.path)","sessionId":"s1"}"#
    }

    func artifact(_ model: LibraryModel, _ name: String) throws -> Artifact {
        try #require(model.artifacts.first { $0.name == name })
    }

    /// The video selected and checked, as the detail view does.
    func selectVideo(_ model: LibraryModel) async throws -> Artifact {
        let video = try artifact(model, "demo.mp4")
        model.selection = video.path
        await model.observe(video)
        return video
    }

    func text(_ url: URL?) throws -> String {
        try String(contentsOf: try #require(url), encoding: .utf8)
    }

    // MARK: Delivered with (D6)

    @Test func aFileDeliveredWithAnotherOpensOnItsDeliveryFromThatReply() throws {
        let model = LibraryModel(indexer: indexer)
        let video = try artifact(model, "demo.mp4"), notes = try artifact(model, "notes.md")
        // The notes came with the first render, not the latest.
        let sibling = try #require(model.siblings[notes.latest.id]?.first)
        #expect(sibling.id == video.deliveries[2].id)

        // A filter hides the video: following the link clears it and lands on that delivery.
        model.kind = .document
        model.selection = notes.path
        model.select(sibling)
        #expect(model.kind == nil)
        #expect(model.selected?.artifact.path == video.path)
        #expect(model.selected.map(model.delivery(in:))?.id == sibling.id)
    }

    // MARK: Quick Look (N1)

    @Test func quickLookShowsOnlyTheSelectedDeliverysPreparedBytes() async throws {
        let model = LibraryModel(indexer: indexer)
        let video = try await selectVideo(model)
        let (third, first) = (video.deliveries[0], video.deliveries[2])
        await model.stage(sha: try #require(third.sha256), artifact: video)
        model.toggleQuickLook()
        #expect(try text(model.quickLookURL) == "video v2")

        // Another version is picked: until its bytes are prepared, Quick Look has nothing to show.
        model.chosenDelivery = first.id
        #expect(model.quickLookURL == nil)
        await model.stage(sha: try #require(first.sha256), artifact: video)
        #expect(try text(model.quickLookURL) == "video v1")
    }

    // MARK: Compare (D3)

    @Test func aComparisonIsShownOnlyForThePairItWasAskedFor() {
        func end(_ title: String, _ sha: String) -> Comparison.End {
            Comparison.End(title: title, source: "saved copy", sha: sha, url: URL(fileURLWithPath: "/objects/\(sha)"))
        }
        let asked = ComparePane.Request(from: end("Delivery 1", "a"), to: end("Delivery 3", "c"), kind: .media)
        let loaded = (request: asked, content: Comparison.Content.failed("loaded for 1 → 3"))
        #expect(ComparePane.content(loaded, for: asked) == loaded.content)
        #expect(ComparePane.content(loaded, for: ComparePane.Request(from: end("Delivery 2", "a"), to: end("Delivery 3", "c"), kind: .media)) == nil)
        #expect(ComparePane.content(loaded, for: ComparePane.Request(from: end("Delivery 1", "b"), to: end("Delivery 3", "c"), kind: .media)) == nil)
        #expect(ComparePane.content(nil, for: asked) == nil)
    }

    @Test func compareEndsSayWhenBytesWereFirstSeenLater() throws {
        let model = LibraryModel(indexer: indexer)
        let video = try artifact(model, "demo.mp4")
        #expect(video.deliveries[2].capture?.provenance == .firstSeenAfterDelivery)
        #expect(model.compareEnd(video.deliveries[2], artifact: video)?.title == "Delivery 1 (first seen later)")
        #expect(model.compareEnd(video.deliveries[1], artifact: video)?.title == "Delivery 2")
    }

    // MARK: Hand-off copies (N2)

    @Test func clearingHandOffCopiesDropsAPreparationAndPreparesTheSelectionAgain() async throws {
        let model = LibraryModel(indexer: indexer)
        let video = try await selectVideo(model)
        let sha = try #require(video.latest.sha256)
        let generation = model.stagingGeneration
        let preparing = Task { await model.stage(sha: sha, artifact: video) }
        await Task.yield()
        #expect(model.staging(for: sha) == .preparing(sha: sha))
        model.clearHandoffCopies()
        await preparing.value
        // What was being prepared before the clear is never shown after it; the new generation
        // makes the detail view prepare the selection again.
        #expect(model.staging(for: sha) == .idle)
        #expect(model.stagingGeneration == generation + 1)
        await model.stage(sha: sha, artifact: video)
        #expect(try text(model.selectedHandoffURL) == "video v2")
    }
}
