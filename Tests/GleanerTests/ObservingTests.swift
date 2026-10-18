import Foundation
import Testing
@testable import Gleaner
@testable import GleanerCore

/// The library window's model with what was observed during sessions: candidates beside the
/// deliveries in their project and folder, hidden with their agent, and corrected by the person
/// with decisions that survive a relaunch and can be undone (docs/design/capture.md, layer 1).
@MainActor @Suite struct ObservingTests {
    let root: URL
    let series: URL
    let indexer: Indexer
    /// Half an hour ago: the files, written now, are written while both sessions work.
    let t0 = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 30 * 60).rounded(.down))

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("gleaner-observing-\(UUID().uuidString)")
        series = root.appendingPathComponent("home/series")
        for folder in [series.appendingPathComponent("out/voice"), root.appendingPathComponent("claude/series")] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("handoff")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
        indexer.home = root.appendingPathComponent("home").path

        try file("out/ep01.mp4", at: 20)
        try file("out/ep01.mix.wav", at: 21)
        try file("out/voice/line-1.wav", at: 22)
        try file("cover.png", at: 23)
        try session("one", title: "Episode one", from: 0, to: 40, reply: "The [episode](out/ep01.mp4).")
        try session("two", title: "Covers", from: 10, to: 50, reply: "Covers are done.")
        _ = try indexer.run()
    }

    func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    func file(_ relative: String, at m: Double) throws {
        let url = series.appendingPathComponent(relative)
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.creationDate: minutes(m)], ofItemAtPath: url.path)
        try FileManager.default.setAttributes([.modificationDate: minutes(m)], ofItemAtPath: url.path)
    }

    /// A session in the series folder.
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
        let log = root.appendingPathComponent("claude/series/\(id).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: log, atomically: false, encoding: .utf8)
    }

    func relaunch() -> LibraryModel { LibraryModel(indexer: indexer) }

    @Test func candidatesSitInTheirProjectAndFolderBesideTheDeliveries() throws {
        let model = relaunch()
        let episode = try #require(model.organization.work(containing: series.path + "/out/ep01.mp4"))
        let project = try #require(model.organization.project(episode.project))
        // The delivered video keeps its delivery; both sessions' observations of it sit beside it.
        #expect(episode.deliveries.count == 1)
        #expect(model.organization.observations(of: episode).compactMap(\.sessionTitle).sorted() == ["Covers", "Episode one"])
        let candidates = model.organization.candidates(in: project.key)
        #expect(Set(candidates.map(\.name)) == ["ep01.mix.wav", "line-1.wav", "cover.png"])
        // Listed under the folder the delivery is in, as the outline names it.
        let mix = try #require(candidates.first { $0.name == "ep01.mix.wav" })
        #expect(model.outlineFolder(mix, in: project) == model.outlineFolder(episode, in: project))
        #expect(model.outlineFolder(mix, in: project) == "out")
        #expect(model.outlineFolder(try #require(candidates.first { $0.name == "line-1.wav" }), in: project) == "out/voice")
        #expect(model.outlineFolder(try #require(candidates.first { $0.name == "cover.png" }), in: project) == "")
        // Observations make no work and no delivery.
        #expect(model.organization.works.count == 1)
    }

    @Test func anAgentTurnedOffHasItsObservationsHiddenNotRemoved() async throws {
        let model = relaunch()
        #expect(!model.organization.candidates.isEmpty)
        await model.setSource(.claudeCode, on: false)
        #expect(model.organization.candidates.isEmpty)
        await model.setSource(.claudeCode, on: true)
        #expect(model.organization.candidates.count == 3)
        #expect(try indexer.registry.observations().count == 8)
    }

    @Test func detachingAndRelatingAreDecisionsThatSurviveARelaunchAndUndo() async throws {
        let model = relaunch()
        let cover = series.path + "/cover.png"
        let logs = try #require(model.organization.candidate(cover)?.observations.map(\.logPath))
        #expect(logs.count == 2)
        let one = try #require(model.organization.candidate(cover)?.observations.first { $0.sessionTitle == "Episode one" }?.logPath)

        await model.detach(cover, from: one)
        #expect(model.organization.candidate(cover)?.observations.compactMap(\.sessionTitle) == ["Covers"])
        let episode = try #require(model.organization.work(containing: series.path + "/out/ep01.mp4"))
        await model.relate(cover, to: episode)
        #expect(model.organization.related(to: episode).map(\.path) == [cover])
        #expect(model.correctionGroups.map { model.describe($0) } == ["Related cover.png to ep01.mp4", "Detached cover.png from Episode one"])

        // Read again and relaunched: both decisions stand, and nothing observed changed.
        try indexer.registry.db.execute("PRAGMA user_version = 1")
        let reread = Indexer(registry: try Registry(path: indexer.registry.path), store: indexer.store, sources: indexer.sources)
        reread.home = indexer.home
        _ = try reread.run()
        let again = LibraryModel(indexer: reread)
        #expect(again.organization.candidate(cover)?.observations.compactMap(\.sessionTitle) == ["Covers"])
        #expect(again.organization.related(to: episode).map(\.path) == [cover])
        #expect(try reread.registry.observations().count == 8)

        await again.undo(again.organization.detachments(of: cover))
        await again.undo(again.organization.relations(of: cover))
        #expect(again.organization.candidate(cover)?.observations.count == 2)
        #expect(again.organization.related(to: episode).isEmpty && again.corrections.isEmpty)
    }
}
