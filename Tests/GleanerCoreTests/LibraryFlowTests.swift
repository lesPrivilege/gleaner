import Foundation
import Testing
@testable import GleanerCore

/// The P0 flow on a synthetic machine: an agent delivers files, they change or vanish, and the
/// library still says the truth and hands over exactly the version asked for.
@Suite struct LibraryFlowTests {
    let root: URL
    let project: URL
    let worktree: URL
    let indexer: Indexer
    let delivered = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-flow-\(UUID().uuidString)")
        project = root.appendingPathComponent("Praxis")
        worktree = project.appendingPathComponent(".claude/worktrees/ch3")
        let fm = FileManager.default
        try fm.createDirectory(at: project.appendingPathComponent("out"), withIntermediateDirectories: true)
        try fm.createDirectory(at: worktree.appendingPathComponent("out"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("claude/-Praxis"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("codex/sessions"), withIntermediateDirectories: true)

        let before = delivered.addingTimeInterval(-30)
        try Self.write("video v1", to: project.appendingPathComponent("out/demo.mp4"), modified: before)
        try Self.write("report r1", to: worktree.appendingPathComponent("out/report.md"), modified: before)
        try Self.write("big build b1, larger than the save limit", to: project.appendingPathComponent("out/build.dmg"), modified: before)

        let support = root.appendingPathComponent("support")
        let registry = try Registry(path: support.appendingPathComponent("registry.sqlite").path.creatingParent())
        indexer = Indexer(
            registry: registry,
            store: ContentStore(objects: support.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
        indexer.saveLimit = 32 // demo.mp4 and report.md are saved; build.dmg is tracked by hash only

        try appendLog([
            user("Make the chapter 3 explainer video about the agent harness loop", at: delivered.addingTimeInterval(-600)),
            assistant("Video: [demo](out/demo.mp4). Report: `\(worktree.path)/out/report.md`. Build: [dmg](out/build.dmg)",
                      at: delivered, cwd: project.path),
        ])
    }

    // MARK: helpers

    static func write(_ text: String, to url: URL, modified: Date) throws {
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    func write(_ text: String, to relative: String, modified: Date) throws {
        try Self.write(text, to: project.appendingPathComponent(relative), modified: modified)
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

    func assistant(_ text: String, at date: Date, cwd: String) -> String {
        #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"text","text":"\#(text)"}]},"timestamp":"\#(stamp(date))","cwd":"\#(cwd)","sessionId":"s1"}"#
    }

    func artifact(_ name: String) throws -> Artifact {
        try #require(try indexer.registry.artifacts().first { $0.name == name })
    }

    func now(_ path: String) -> FileObservation { FileObservation(state: Locator.observe(path), checkedAt: Date()) }
    var saved: (String) -> Bool { indexer.store.has }

    // MARK: flow

    @Test func liveCaptureThenConcurrentEditHandsOverTheDeliveredBytes() throws {
        #expect(try indexer.run(now: { delivered.addingTimeInterval(20) }).newDeliveries == 3)
        let video = try artifact("demo.mp4")
        let d1 = video.latest
        #expect(d1.capture?.provenance == .atDelivery)
        #expect(d1.request == "Make the chapter 3 explainer video about the agent harness loop")
        #expect(saved(try #require(d1.sha256)))

        // An agent rewrites the file after delivery.
        try write("video v2 silently", to: "out/demo.mp4", modified: Date())
        let observation = now(video.path)
        #expect(video.onDisk(observation, hasSaved: saved) == .changed(since: 1))
        #expect(video.handoff(d1, now: observation, hasSaved: saved) == .ready(sha: d1.sha256!, from: .savedCopy, firstSeen: nil))

        let staged = try indexer.store.stage(sha: d1.sha256!, name: video.name, source: video.path)
        #expect(try String(contentsOf: staged, encoding: .utf8) == "video v1")
        #expect(staged.lastPathComponent == "demo.mp4")
    }

    @Test func deletedWorktreeStillHandsOverTheSavedCopy() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let report = try artifact("report.md")
        #expect(report.place == "worktree ch3")
        #expect(report.project == "Praxis")
        let outside = Artifact(path: "/Users/u/Projects/Praxis/kit/a.md", deliveries: [Delivery(
            id: "x", number: 1, path: "/Users/u/Projects/Praxis/kit/a.md", deliveredAt: nil, provider: .claudeCode,
            sessionTitle: nil, request: nil, cwd: "/Users/u/Projects/gleaner", evidence: [], logPath: "", capture: nil)])
        #expect(outside.project == "Praxis")
        #expect(outside.folder == "~/Projects/Praxis/kit" || outside.folder.hasSuffix("Praxis/kit"))
        try FileManager.default.removeItem(at: worktree)

        let observation = now(report.path)
        #expect(report.onDisk(observation, hasSaved: saved) == .missingWithSavedCopy(of: 1, firstSeen: nil))
        guard case .ready(let sha, .savedCopy, nil) = report.handoff(report.latest, now: observation, hasSaved: saved) else {
            Issue.record("expected the saved copy"); return
        }
        let staged = try indexer.store.stage(sha: sha, name: report.name, source: nil)
        #expect(try String(contentsOf: staged, encoding: .utf8) == "report r1")
    }

    @Test func largeFileTrackedByHashIsUnavailableOnceChanged() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let build = try artifact("build.dmg")
        let sha = try #require(build.latest.sha256)
        #expect(build.latest.capture?.savedAt == nil)

        try write("big build b2, rebuilt in place after delivery", to: "out/build.dmg", modified: Date())
        let observation = now(build.path)
        #expect(build.handoff(build.latest, now: observation, hasSaved: saved)
                == .unavailable(alternative: nil, currentSha: observation.state.sha256))
        #expect(throws: ContentStore.Failure.self) {
            try indexer.store.stage(sha: sha, name: build.name, source: build.path)
        }
    }

    @Test func secondDeliveryThenRollback() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let second = delivered.addingTimeInterval(3600)
        try write("video v2", to: "out/demo.mp4", modified: second.addingTimeInterval(-30))
        try appendLog([
            user("Tighten the intro and render again", at: second.addingTimeInterval(-300)),
            assistant("Rendered again: [demo](out/demo.mp4)", at: second, cwd: project.path),
        ])
        #expect(try indexer.run(now: { second.addingTimeInterval(20) }).newDeliveries == 1)
        let video = try artifact("demo.mp4")
        #expect(video.deliveries.map(\.number) == [2, 1])
        #expect(video.onDisk(now(video.path), hasSaved: saved) == .same(as: 2))

        // Someone restores the first render.
        try write("video v1", to: "out/demo.mp4", modified: Date())
        #expect(video.onDisk(now(video.path), hasSaved: saved) == .rolledBack(to: 1, latest: 2))

        // Search for words from the first request opens the first delivery.
        #expect(video.match(["harness"])?.deliveryIndex == 1)
        #expect(video.match(["intro"])?.deliveryIndex == 0)
        #expect(video.match(["nothing-like-this"]) == nil)

        // Words from two different deliveries don't combine into one match.
        #expect(video.match(["harness", "intro"]) == nil)
        // The file name combines with either delivery's words.
        #expect(video.match(["demo", "harness"])?.deliveryIndex == 1)
        #expect(video.match(["demo"])?.deliveryIndex == 0)
    }

    @Test func backfillIsNeverCalledTheDeliveredVersion() throws {
        let later = delivered.addingTimeInterval(30 * 86400)
        _ = try indexer.run(now: { later })
        let video = try artifact("demo.mp4")
        #expect(video.latest.capture?.provenance == .firstSeenAfterDelivery)
        let observation = now(video.path)
        #expect(video.onDisk(observation, hasSaved: saved) == .unchangedSinceFirstSeen(later))
        #expect(video.handoff(video.latest, now: observation, hasSaved: saved)
                == .ready(sha: video.latest.sha256!, from: .original, firstSeen: later))
    }

    @Test func unchangedLogsAreNotReread() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let again = try indexer.run(now: { delivered.addingTimeInterval(40) })
        #expect(again.logsRead == 0)
        #expect(again.newDeliveries == 0)
    }

    @Test func extractorUpgradeRereadsLogsButKeepsCaptures() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let before = try artifact("demo.mp4").latest.capture
        try indexer.registry.db.execute("PRAGMA user_version = 1")
        let upgraded = Indexer(
            registry: try Registry(path: root.appendingPathComponent("support/registry.sqlite").path),
            store: indexer.store, sources: indexer.sources)
        let report = try upgraded.run(now: { delivered.addingTimeInterval(9999) })
        #expect(report.logsRead == 1)
        #expect(report.newDeliveries == 0)
        let after = try #require(try upgraded.registry.artifacts().first { $0.name == "demo.mp4" })
        #expect(after.latest.capture == before)
    }

    @Test func fileGoneBeforeFirstLookIsNeverObserved() throws {
        try FileManager.default.removeItem(at: project.appendingPathComponent("out/demo.mp4"))
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let video = try artifact("demo.mp4")
        #expect(video.latest.capture?.provenance == .neverObserved)
        #expect(video.onDisk(now(video.path), hasSaved: saved) == .lost)
        #expect(video.handoff(video.latest, now: now(video.path), hasSaved: saved) == .lost)
    }
}

private extension String {
    func creatingParent() throws -> String {
        try FileManager.default.createDirectory(
            atPath: (self as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        return self
    }
}
