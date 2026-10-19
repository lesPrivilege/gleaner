import Foundation
import Testing
@testable import Gleaner
@testable import GleanerCore

/// The window's model with work units, kept files and review (docs/design/review.md): each change
/// a decision listed with the corrections and undone, verdicts on the bytes read when they are
/// made, and the queue drawn from the person's acts, all kept through a reread and a relaunch.
@MainActor @Suite struct ReviewingTests {
    let root: URL
    let series: URL
    let indexer: Indexer
    /// Half an hour ago: the files, written now, are written while both sessions work.
    let t0 = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 30 * 60).rounded(.down))

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("gleaner-reviewing-\(UUID().uuidString)")
        series = root.appendingPathComponent("home/series")
        for folder in [series.appendingPathComponent("out"), root.appendingPathComponent("claude/series")] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("handoff")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
        indexer.home = root.appendingPathComponent("home").path

        try file("out/ep01.mp4", "episode one", at: 20)
        try file("out/ep01.mix.wav", "mix", at: 21)
        try file("cover.png", "cover", at: 23)
        try session("one", title: "Episode one", from: 0, to: 40, reply: "The [episode](out/ep01.mp4).")
        try session("two", title: "Covers", from: 22, to: 50, reply: "Covers are done.")
        _ = try indexer.run()
    }

    func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    func file(_ relative: String, _ text: String, at m: Double) throws {
        let url = series.appendingPathComponent(relative)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.creationDate: minutes(m)], ofItemAtPath: url.path)
        try FileManager.default.setAttributes([.modificationDate: minutes(m)], ofItemAtPath: url.path)
    }

    func session(_ id: String, title: String, from start: Double, to end: Double, reply: String) throws {
        func record(_ object: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) }
        let stamp = { (m: Double) in self.minutes(m).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
        let lines = [
            try record(["type": "user", "sessionId": id, "cwd": series.path, "timestamp": stamp(start), "origin": ["kind": "human"],
                        "message": ["role": "user", "content": "Make the episode"]]),
            try record(["type": "assistant", "sessionId": id, "cwd": series.path, "timestamp": stamp(end),
                        "message": ["role": "assistant", "model": "m", "content": [["type": "text", "text": reply]]]]),
            try record(["type": "custom-title", "sessionId": id, "customTitle": title]),
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: root.appendingPathComponent("claude/series/\(id).jsonl"), atomically: false, encoding: .utf8)
    }

    func relaunch() -> LibraryModel { LibraryModel(indexer: indexer) }

    var video: String { series.path + "/out/ep01.mp4" }
    var cover: String { series.path + "/cover.png" }

    @Test func unitsAndKeptFilesAreDecisionsListedAndUndone() async throws {
        let model = relaunch()
        let project = try #require(model.organization.work(containing: video)?.project)
        let made = try #require(await model.newUnit(named: "Series", in: project))
        let made1 = try #require(await model.newUnit(named: "Episode 1", in: project, inside: made.key))
        let unit = try #require(model.organization.unit(made1.key))
        #expect(model.organization.units(in: project).map(\.name) == ["Series"])

        // Adding an observed file keeps it: a work with one revision, kept by you, in the unit.
        await model.add([try #require(model.organization.candidate(cover))], to: unit)
        let kept = try #require(model.organization.work(containing: cover))
        #expect(kept.unit == unit.key && kept.deliveries.count == 1 && kept.deliveries[0].kept != nil)
        #expect(model.organization.candidate(cover) == nil)
        await model.add([try #require(model.organization.work(containing: video))], to: unit)
        #expect(model.organization.works(in: unit.key).map(\.name) == ["ep01.mp4", "cover.png"])
        await model.rename(unit, to: "Pilot")
        #expect(model.correctionGroups.map { model.describe($0) } == [
            "Renamed Episode 1 to Pilot",
            "Added ep01.mp4 to Pilot",
            "Kept cover.png, observed during Episode one; Added cover.png to Pilot",
        ])

        // Undone, the kept file is a candidate again, and in no unit.
        await model.undo(try #require(model.correctionGroups.last))
        #expect(model.organization.work(containing: cover) == nil && model.organization.candidate(cover) != nil)
        #expect(!model.artifacts.contains { $0.path == cover })
        // Deleted, the episode's work goes back to the project; undone, it is back.
        await model.delete(try #require(model.organization.unit(unit.key)))
        #expect(model.organization.units.map(\.name) == ["Series"])
        #expect(model.organization.work(containing: video)?.unit == nil)
        #expect(model.describe(try #require(model.correctionGroups.first)) == "Deleted Pilot")
        await model.undo(try #require(model.correctionGroups.first))
        #expect(model.organization.work(containing: video)?.unit == unit.key)
        // Making a unit is taken back with what was decided about it.
        await model.unmake(made)
        #expect(model.organization.units.isEmpty && model.corrections.isEmpty)
        #expect(model.organization.work(containing: video)?.unit == nil)
    }

    @Test func verdictsAreOnTheBytesReadAndTheQueueFollowsThem() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let unit = try #require(await model.newUnit(named: "Episode 1", in: work.project))
        await model.add([work], to: try #require(model.organization.unit(unit.key)))
        #expect(model.toReview.flatMap(\.works).map(\.id) == [video])
        #expect(model.verdict(of: work) == .none)

        let approved = try #require(await model.review([work], as: .approved).first)
        #expect(model.toReview.isEmpty && model.verdict(of: work) == .current(approved))
        #expect(model.published(of: work) == .none)

        // Changed on disk: after a relaunch it may have changed, until selecting it reads it.
        try file("out/ep01.mp4", "episode one, recut", at: 45)
        let again = relaunch()
        let shown = try #require(again.organization.work(containing: video))
        #expect(again.verdict(of: shown) == .mayHaveChanged(approved))
        #expect(again.toReview.flatMap(\.works).map(\.id) == [video])
        await again.observe(shown.latest)
        #expect(again.verdict(of: shown) == .changed(approved))
        let changes = try #require(await again.review([shown], as: .changesRequested, note: "Trim the intro").first)
        #expect(again.verdict(of: shown) == .current(changes) && again.toReview.isEmpty)
        #expect(again.reviews.history(of: shown) == [changes, approved])
        // Undone, the verdict before it is on other bytes.
        await again.undo([changes])
        #expect(again.verdict(of: shown) == .changed(approved))

        // A file changed while its bytes were being judged is refused, with why.
        let stale = try #require(FileStat(video))
        try file("out/ep01.mp4", "episode one, final", at: 46)
        #expect(await again.review([shown], as: .approved, shown: [video: stale]).isEmpty)
        #expect(again.reviewFailure == "ep01.mp4 changed since it was shown. Look at it again, then decide.")
    }

    @Test func everyDecisionSurvivesARereadAndARelaunch() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let made = try #require(await model.newUnit(named: "Episode 1", in: work.project))
        let unit = try #require(model.organization.unit(made.key))
        await model.add([work], to: unit)
        await model.add([try #require(model.organization.candidate(cover))], to: unit)
        await model.rename(unit, to: "Pilot")
        let approved = try #require(await model.review([work], as: .approved).first)
        let published = try #require(await model.review([work], as: .published, note: "the channel").first)

        try indexer.registry.db.execute("PRAGMA user_version = 1")
        let reread = Indexer(registry: try Registry(path: indexer.registry.path), store: indexer.store, sources: indexer.sources)
        reread.home = indexer.home
        _ = try reread.run()
        let again = LibraryModel(indexer: reread)
        let shown = try #require(again.organization.work(containing: video))
        #expect(again.organization.unit(made.key)?.name == "Pilot")
        #expect(again.organization.works(in: made.key).map(\.name) == ["ep01.mp4", "cover.png"])
        #expect(again.organization.work(containing: cover)?.deliveries.first?.kept != nil)
        #expect(again.verdict(of: shown) == .current(approved) && again.published(of: shown) == .current(published))
        #expect(again.correctionGroups.count == model.correctionGroups.count)
    }
}
