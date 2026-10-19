import Foundation
import Testing
import UniformTypeIdentifiers
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
            "Kept and added cover.png to Pilot, observed during Episode one",
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

    // MARK: The window (docs/design/review.md, The window)

    var mix: String { series.path + "/out/ep01.mix.wav" }

    @Test func aCollectionIsAPlaceThatOpensOnItsReviewPage() async throws {
        let model = relaunch()
        let project = try #require(model.organization.work(containing: video)?.project)
        let series = try #require(await model.newUnit(named: "Series", in: project))
        let pilot = try #require(await model.newUnit(named: "Pilot", in: project, inside: series.key))
        await model.add([try #require(model.organization.work(containing: video))], to: try #require(model.organization.unit(pilot.key)))
        await model.add([try #require(model.organization.candidate(cover))], to: try #require(model.organization.unit(series.key)))

        // Opened, the collection's page is shown, and it lists its works and those of the one inside.
        model.place = .unit(series.key)
        #expect(model.currentUnit?.key == series.key && model.outlineSelection == .unit(series.key))
        #expect(Set(model.results.map(\.id)) == [video, cover])
        #expect(model.waiting(in: series.key) == 2 && model.waiting(in: pilot.key) == 1 && model.toReviewCount == 2)
        // The one inside, chosen in the list, has its page shown there; a work, its detail.
        model.outlineSelection = .unit(pilot.key)
        #expect(model.currentUnit?.key == pilot.key && model.place == .unit(series.key))
        model.selection = video
        #expect(model.selected?.work.id == video && model.shownUnit == nil)
        // New Collection from inside one made inside it goes beside it: one level deep.
        model.place = .unit(pilot.key)
        #expect(model.newUnitPlace?.parent == series.key)
        // Deleted while shown, the collection gives way to its project.
        await model.delete(try #require(model.organization.unit(series.key)))
        #expect(model.place == .project(project))
        // A place a relaunch can find again, by the collection's key.
        #expect(LibraryView.decode(LibraryView.encode(.unit(pilot.key))) == .unit(pilot.key))
        #expect(LibraryView.decode(LibraryView.encode(.toReview)) == .toReview)
    }

    @Test func aCollectionIsNamedInPlaceAndTakesWhatWasChosen() async throws {
        let model = relaunch()
        let project = try #require(model.organization.work(containing: video)?.project)
        model.startNewUnit(in: project, adding: [video, cover])
        #expect(model.naming == .new(project: project, parent: nil, adding: [video, cover]))
        await model.commitNaming("  Pilot ")
        let pilot = try #require(model.organization.units.first)
        #expect(model.naming == nil && pilot.name == "Pilot")
        // The work and the observed file, kept, are in it; the window stays where it was.
        #expect(Set(model.organization.works(in: pilot.key).map(\.id)) == [video, cover])
        #expect(model.place == .all)
        // An empty name makes nothing; a collection made for nothing in particular is shown.
        model.startNewUnit(in: project)
        await model.commitNaming(" ")
        #expect(model.organization.units.count == 1)
        model.startNewUnit(in: project)
        await model.commitNaming("Trailer")
        #expect(model.place == .unit(try #require(model.organization.units.first { $0.name == "Trailer" }).key))
        // Renamed in place.
        model.naming = .rename(pilot.key)
        await model.commitNaming("Episode 1")
        #expect(model.organization.unit(pilot.key)?.name == "Episode 1")
        #expect(model.describe(try #require(model.correctionGroups.first)) == "Renamed Pilot to Episode 1")
    }

    @Test func severalChosenRowsAreAddedTogetherAndADraggedOneBringsTheOthers() async throws {
        let model = relaunch()
        await model.keep([try #require(model.organization.candidate(mix))])
        #expect(model.describe(try #require(model.correctionGroups.first)) == "Kept ep01.mix.wav, observed during Episode one")
        let project = try #require(model.organization.work(containing: video)?.project)
        model.place = .project(project)
        model.selectedRows = [.work(video), .work(mix)]
        #expect(Set(model.selectedWorks.map(\.id)) == [video, mix])
        // Dragging one of the rows chosen drags them all, as Finder does; another row, itself.
        #expect(Set(model.dropped([mix]).map(\.id)) == [video, mix])
        model.selectedRows = [.work(video)]
        #expect(model.alsoSelected.isEmpty && model.dropped([mix]).map(\.id) == [mix])
        let unit = try #require(await model.newUnit(named: "Pilot", in: project))
        await model.add(model.dropped([video]), to: try #require(model.organization.unit(unit.key)))
        #expect(model.organization.works(in: unit.key).map(\.id) == [video])
        // A row hands Gleaner its work, whether or not it has anything for another app.
        let work = try #require(model.organization.work(containing: mix))
        let item = model.rowDragItem(work, work.latest, work.latest.latest)
        #expect(item.hasItemConformingToTypeIdentifier(UTType.gleanerWork.identifier))
    }

    @Test func theObservedSectionListsEachFileUnderItsSessionAndKeepsIt() async throws {
        let model = relaunch()
        let project = try #require(model.projects.first)
        // The cover appeared while both sessions worked; it is listed under one, the mix under the first.
        let sessions = model.observedSessions(in: project)
        #expect(sessions.map(\.title) == ["Episode one"])
        #expect(sessions.first?.candidates.map(\.name) == ["cover.png", "ep01.mix.wav"])
        // Not from this session: listed under the other.
        let one = try #require(sessions.first?.logPath)
        await model.detach(cover, from: one)
        #expect(model.observedSessions(in: project).map(\.title) == ["Covers", "Episode one"])
        // Kept, it leaves the section for the outline, as a work kept by you.
        await model.keep([try #require(model.organization.candidate(cover))])
        #expect(model.observedSessions(in: project).map(\.title) == ["Episode one"])
        let kept = try #require(model.organization.work(containing: cover))
        #expect(kept.latest.latest.kept != nil && model.waits(kept) == nil)
        // Kept as observed, it comes into the outline, and nothing waits on it until a collection holds it.
        #expect(model.outline(of: try #require(model.organization.project(project.key))).flatMap(\.items).contains { $0.id == cover })
    }

    @Test func eachWorkSaysWhatWaitsAndWhereItIsAndToReviewKeepsTheOneShown() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let unit = try #require(await model.newUnit(named: "Pilot", in: work.project))
        await model.add([work], to: try #require(model.organization.unit(unit.key)))
        let inUnit = try #require(model.organization.work(containing: video))
        #expect(model.waits(inUnit)?.1 == "To review")
        #expect(model.onThisMac(inUnit).title == "On this Mac")
        model.place = .toReview
        #expect(model.results.map(\.id) == [video])
        model.selection = video
        await model.review([inUnit], as: .approved)
        // Reviewed, it leaves the queue, and stays shown until the person moves on.
        #expect(model.results.isEmpty && model.selected?.work.id == video && model.waits(inUnit) == nil)
        // Gone after its verdict: said as gone, and the verdict stands as made (A20, A22).
        try FileManager.default.removeItem(atPath: video)
        let again = relaunch()
        let gone = try #require(again.organization.work(containing: video))
        #expect(again.onThisMac(gone).title == "Not on disk")
        #expect({ if case .unavailable = again.verdict(of: gone) { true } else { false } }())
        #expect(again.waits(gone) == nil && again.toReview.isEmpty)
    }
}
