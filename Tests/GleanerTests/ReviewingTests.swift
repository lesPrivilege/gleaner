import AppKit
import Foundation
import SwiftUI
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

    func session(_ id: String, title: String, from start: Double, to end: Double, reply: String, in folder: URL? = nil) throws {
        func record(_ object: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) }
        let stamp = { (m: Double) in self.minutes(m).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
        let cwd = (folder ?? series).path
        let lines = [
            try record(["type": "user", "sessionId": id, "cwd": cwd, "timestamp": stamp(start), "origin": ["kind": "human"],
                        "message": ["role": "user", "content": "Make the episode"]]),
            try record(["type": "assistant", "sessionId": id, "cwd": cwd, "timestamp": stamp(end),
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
        #expect(await again.review([shown], as: .approved, shown: [video: stale], from: shown.id).isEmpty)
        let refusal = try #require(again.reviewRefusal)
        #expect(refusal.place == shown.id && Wording.refusal(refusal).title == "Nothing recorded")
        #expect(refusal.reason(video) == "ep01.mp4 changed since it was shown. Look at it again, then decide.")
        // Said where it was asked for, until the person shows something else.
        again.selection = cover
        #expect(again.reviewRefusal == nil)
    }

    @Test func severalAskedForTogetherSayWhatWasRecordedAndWhatWasntWhereTheyWereAsked() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let made = try #require(await model.newUnit(named: "Pilot", in: work.project))
        await model.add([work], to: try #require(model.organization.unit(made.key)))
        await model.add([try #require(model.organization.candidate(cover))], to: try #require(model.organization.unit(made.key)))
        model.place = .unit(made.key)
        let works = model.organization.works(in: made.key)
        let shown = Dictionary(uniqueKeysWithValues: works.compactMap { work in FileStat(work.latest.path).map { (work.latest.path, $0) } })
        #expect(shown.count == 2)
        // The cover is touched after the page drew it.
        try file("cover.png", "cover, again", at: 47)
        #expect(await model.review(works, as: .approved, shown: shown, from: made.key).map(\.path) == [video])
        let refusal = try #require(model.reviewRefusal)
        #expect(Wording.refusal(refusal).title == "Approved 1 work, 1 not recorded")
        #expect(refusal.place == made.key && refusal.reason(cover)?.hasPrefix("cover.png changed since it was shown") == true)
        // Another collection's page, or a work's detail, doesn't say it.
        model.place = .toReview
        #expect(model.reviewRefusal == nil)
    }

    @Test func aPageSaysWhatItDrewOfAFileRewrittenOutsideAnySession() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let made = try #require(await model.newUnit(named: "Pilot", in: work.project))
        await model.add([work], to: try #require(model.organization.unit(made.key)))
        let inUnit = try #require(model.organization.work(containing: video))
        let approved = try #require(await model.review([inUnit], as: .approved).first)
        // Rendered again by hand: no log changes, so no run tells the model.
        try file("out/ep01.mp4", "episode one, rendered by hand", at: 48)
        let shown = try #require(model.organization.work(containing: video))
        #expect(model.verdict(of: shown) == .current(approved))
        // The page draws it, and says what it drew.
        model.noteShown(video, FileStat(video))
        #expect(model.verdict(of: shown) == .mayHaveChanged(approved))
        #expect(model.toReview.flatMap(\.works).map(\.id) == [video])
        // Gone when the page looks again: said as gone, and nothing is there to review.
        try FileManager.default.removeItem(atPath: video)
        model.noteShown(video, FileStat(video))
        #expect(model.onThisMac(shown).title == "Not on disk" && model.hasNoFile(shown))
    }

    @Test func aRecutGoneFromDiskKeepsNoVerdictNoOneMadeOnIt() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let made = try #require(await model.newUnit(named: "Pilot", in: work.project))
        await model.add([work], to: try #require(model.organization.unit(made.key)))
        let inUnit = try #require(model.organization.work(containing: video))
        let approved = try #require(await model.review([inUnit], as: .approved).first)
        // The agent recuts it and a reply names the recut; the run reads its bytes.
        try file("out/ep01.mp4", "episode one, recut", at: 49)
        try session("three", title: "Recut", from: 48, to: 50, reply: "The [recut](out/ep01.mp4).")
        _ = try indexer.run()
        try FileManager.default.removeItem(atPath: video)
        let again = relaunch()
        let recut = try #require(again.organization.work(containing: video))
        #expect(recut.deliveries.count == 2 && recut.deliveries[0].sha256 != approved.sha256)
        // Gone, the recut nobody judged isn't approved, and it waits (A16, A24).
        #expect(again.verdict(of: recut) == .changed(approved))
        #expect(again.toReview.flatMap(\.works).map(\.id) == [video] && again.onThisMac(recut).title == "Not on disk")
    }

    @Test func aRecutGoneFromDiskWhileGleanerRunsIsChangedAsAfterARelaunch() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let made = try #require(await model.newUnit(named: "Pilot", in: work.project))
        await model.add([work], to: try #require(model.organization.unit(made.key)))
        let inUnit = try #require(model.organization.work(containing: video))
        let approved = try #require(await model.review([inUnit], as: .approved).first)
        // The recut is delivered while Gleaner runs: the library takes the size and dates its
        // delivery recorded as it shows it.
        try file("out/ep01.mp4", "episode one, recut", at: 49)
        try session("three", title: "Recut", from: 48, to: 50, reply: "The [recut](out/ep01.mp4).")
        model.reindex()
        try await TourTests.until { model.organization.work(containing: video)?.deliveries.count == 2 }
        try FileManager.default.removeItem(atPath: video)
        await model.observe(try #require(model.organization.work(containing: video)).latest)
        // Gone: the bytes the delivery recorded decide, as after a relaunch, not "may have changed".
        let recut = try #require(model.organization.work(containing: video))
        #expect(model.verdict(of: recut) == .changed(approved) && model.toReview.flatMap(\.works).map(\.id) == [video])
    }

    @Test func aFileThatCantBeReadIsSaidAsUnreadableAndCantBeReviewed() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let made = try #require(await model.newUnit(named: "Pilot", in: work.project))
        await model.add([work], to: try #require(model.organization.unit(made.key)))
        #expect(chmod(video, 0) == 0)
        defer { chmod(video, 0o644) }
        let again = relaunch()
        let locked = try #require(again.organization.work(containing: video))
        // Never "On this Mac", never gone (A20); and with nothing to judge, not "To review" either.
        #expect(again.onThisMac(locked).title == "Can’t read")
        #expect(again.hasNoFile(locked) && again.waits(locked)?.1 == "Can’t be reviewed")
        #expect(FileStat(video) == nil)
    }

    @Test func eachCollectionDecisionIsMadeOnceAndAsOneLine() async throws {
        let model = relaunch()
        let project = try #require(model.organization.work(containing: video)?.project)
        let one = try #require(await model.newUnit(named: "One", in: project))
        let two = try #require(await model.newUnit(named: "Two", in: project))
        await model.add([try #require(model.organization.work(containing: video))], to: try #require(model.organization.unit(one.key)))
        // Dropped on the collection it is already in: nothing is decided again.
        await model.add([try #require(model.organization.work(containing: video))], to: try #require(model.organization.unit(one.key)))
        #expect(model.correctionGroups.map { model.describe($0) } == ["Added ep01.mp4 to One"])
        await model.add([try #require(model.organization.candidate(cover))], to: try #require(model.organization.unit(two.key)))
        // Taken out of both together: one decision, one line, one Undo.
        let both = [video, cover].compactMap { model.organization.work(containing: $0) }
        await model.remove(both)
        #expect(model.describe(try #require(model.correctionGroups.first)) == "Removed ep01.mp4 from One; Removed cover.png from Two")
        #expect(both.allSatisfy { model.organization.work(containing: $0.id)?.unit == nil })
        await model.undo(try #require(model.correctionGroups.first))
        #expect(model.organization.work(containing: video)?.unit == one.key && model.organization.work(containing: cover)?.unit == two.key)
    }

    @Test func undoingAKeepTakesBackWhatWasDecidedAboutTheFileSince() async throws {
        let model = relaunch()
        let project = try #require(model.organization.work(containing: video)?.project)
        await model.keep([try #require(model.organization.candidate(cover))])
        let keep = try #require(model.correctionGroups.first)
        let made = try #require(await model.newUnit(named: "Pilot", in: project))
        await model.add([try #require(model.organization.work(containing: cover))], to: try #require(model.organization.unit(made.key)))
        #expect(model.correctionGroups.count == 2)
        // Undone, the keep takes its collection with it: nothing is left listed with nothing to act on.
        await model.undo(keep)
        #expect(model.corrections.isEmpty && model.organization.candidate(cover) != nil)
        // Kept again, it is only kept.
        await model.keep([try #require(model.organization.candidate(cover))])
        #expect(model.organization.work(containing: cover)?.unit == nil)
        #expect(model.organization.works(in: made.key).isEmpty)
    }

    @Test func aProjectDeletedSaysWhichCollectionsGoWithIt() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        await model.move(work, toNewProject: "Channel")
        let channel = try #require(model.userProjects.first)
        let series = try #require(await model.newUnit(named: "Series", in: channel.key))
        _ = try #require(await model.newUnit(named: "Episode 1", in: channel.key, inside: series.key))
        #expect(model.unitsDeleted(with: channel.key) == 2)
        #expect(Wording.deletingProject(units: 2).contains("Its 2 collections are deleted, and you can’t undo this."))
        #expect(Wording.deletingProject(units: 0) == "Each work goes back to the project it was in before. No file changes.")
    }

    @Test func aProjectDeletedSendsEachWorkBackToTheProjectItWasInBefore() async throws {
        let model = relaunch()
        let found = try #require(model.organization.work(containing: video)?.project)
        await model.move(try #require(model.organization.work(containing: video)), toNewProject: "One")
        let one = try #require(model.userProjects.first { $0.name == "One" })
        await model.move(try #require(model.organization.work(containing: video)), toNewProject: "Two")
        let made = try #require(model.userProjects.first { $0.name == "Two" })
        let two = try #require(model.organization.project(made.key))
        #expect(model.organization.work(containing: video)?.project == two.key)
        // Not where Gleaner found it: the project it was in before, as the words say.
        await model.remove(two)
        #expect(model.organization.work(containing: video)?.project == one.key && one.key != found)
    }

    @Test func selectingAFileNoReviewStateIsShownForLeavesTheQueueAsItWas() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let made = try #require(await model.newUnit(named: "Pilot", in: work.project))
        await model.add([try #require(model.organization.candidate(cover))], to: try #require(model.organization.unit(made.key)))
        _ = model.toReview
        let version = model.reviewsVersion
        // The episode is in no collection and has no verdict: reading it moves nothing the queue shows.
        await model.observe(try #require(model.organization.work(containing: video)).latest)
        #expect(model.reviewsVersion == version)
        // The kept cover is in one: reading it does.
        await model.observe(try #require(model.organization.work(containing: cover)).latest)
        #expect(model.reviewsVersion > version)
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

    @Test func aPageDrawsEachFileThatSharesOnlyAStemAndNamesARenderBesideItsSource() throws {
        func work(_ name: String) -> Work {
            let path = "/w/series/ep01/" + name
            let delivery = Delivery(id: path + "#1", number: 1, path: path, deliveredAt: t0, replyLine: 1, provider: .claudeCode,
                                    sessionTitle: nil, request: nil, cwd: "/w/series", evidence: [], logPath: "/logs/s.jsonl", capture: nil)
            let file = Artifact(path: path, deliveries: [delivery])
            return Work(files: [file], deliveries: file.deliveries, project: "/w/series")
        }
        let names = ["ep01.mp4", "ep01.vertical.mp4", "ep01.cover-4x3.png", "ep01.cover-3x4.png", "ov-4x3.png", "ov-4x3.svg",
                     "ep01.script.md", "ep01.inputs.json"]
        let layout = ReviewLayout(names.map(work))
        // Both cuts, both covers and the script are each drawn; only the source of a render is
        // named beside it, and what a program reads is under Other Files.
        #expect(layout.items.map(\.lead.name) == ["ep01.mp4", "ep01.vertical.mp4", "ep01.cover-4x3.png", "ep01.cover-3x4.png",
                                                  "ov-4x3.png", "ep01.script.md"])
        #expect(layout.items.first { $0.lead.name == "ov-4x3.png" }?.beside.map(\.name) == ["ov-4x3.svg"])
        #expect(layout.items.filter { $0.lead.name != "ov-4x3.png" }.allSatisfy { $0.beside.isEmpty })
        #expect(layout.others.map(\.name) == ["ep01.inputs.json"])
        // A picture too tall or too wide to see in a tile isn't counted as shown.
        #expect(ImageTile.legible(CGSize(width: 1920, height: 1080)) && ImageTile.legible(CGSize(width: 1080, height: 1440)))
        #expect(!ImageTile.legible(CGSize(width: 1080, height: 20000)) && !ImageTile.legible(CGSize(width: 20000, height: 800)))
    }

    @Test func aReviewPageReadsOnlyTheImagesThatScrollIntoView() async throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let count = 60
        let paths = (0..<count).map { series.path + String(format: "/stills/still-%02d.png", $0) }
        try FileManager.default.createDirectory(atPath: series.path + "/stills", withIntermediateDirectories: true)
        for path in paths { try png.write(to: URL(fileURLWithPath: path)) }
        try session("three", title: "Stills", from: 24, to: 29, reply: "The stills: " + (0..<count).map { String(format: "[%02d](stills/still-%02d.png)", $0, $0) }.joined(separator: ", "))
        _ = try indexer.run()
        let model = relaunch()
        let stills = model.organization.works.filter { $0.latest.path.contains("/stills/") }
        #expect(stills.count == count)
        let first = try #require(stills.first)
        let made = try #require(await model.newUnit(named: "Stills", in: first.project))
        await model.add(stills, to: try #require(model.organization.unit(made.key)))
        // Not read since a while ago, so a read shows.
        let past = 1_700_000_000
        func read() -> Int {
            paths.filter { path in
                var info = Darwin.stat()
                return lstat(path, &info) == 0 && info.st_atimespec.tv_sec != past
            }.count
        }
        for path in paths {
            var times = [timespec(tv_sec: past, tv_nsec: 0), timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT))]
            #expect(utimensat(AT_FDCWD, path, &times, 0) == 0)
        }
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 880, height: 860),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: ReviewPage(unit: try #require(model.organization.unit(made.key))).environment(model))
        window.orderBack(nil)
        for _ in 0..<30 { try await TourTests.settle(0.05) }
        // A few rows of images are on screen: those are read, and only those (each counts for Review All).
        #expect(read() < count / 3, "\(read()) of \(count) read")
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

    // MARK: Before layer 3 lands

    /// A 65 MiB file a Git repository ignores, delivered by a reply: over the save limit, so its
    /// bytes are hashed and not kept.
    func ignoredMaster() throws -> String {
        let repo = root.appendingPathComponent("home/renders")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        #expect(Locator.run(["-C", repo.path, "init", "-q"]).status == 0)
        try "*.mov\n".write(to: repo.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        let master = repo.appendingPathComponent("master.mov").path
        try master65(master, first: 1)
        try session("renders", title: "Renders", from: 0, to: 40, reply: "The [master](master.mov) is rendered.", in: repo)
        _ = try indexer.run()
        return master
    }

    /// 65 MiB, all zeros but the first byte.
    func master65(_ path: String, first: UInt8) throws {
        var data = Data(count: 65 << 20)
        data[0] = first
        try data.write(to: URL(fileURLWithPath: path))
    }

    @Test func bytesJudgedButNotKeptSaySoAndSaveACopyKeepsThemThroughARewrite() async throws {
        let master = try ignoredMaster()
        let model = relaunch()
        let work = try #require(model.organization.work(containing: master))
        let delivered = try #require(work.latest.latest.sha256)
        #expect(work.latest.latest.capture?.savedAt == nil && !indexer.store.has(delivered))
        // Before the verdict, its note sheet says these bytes won't be kept.
        #expect(model.wouldNotKeep([work], shown: [master: try #require(FileStat(master))]).map(\.size) == [65 << 20])

        // Approved as it is: the verdict's row, and its item on a page, say the bytes aren't kept.
        let approved = try #require(await model.review([work], as: .approved).first)
        #expect(approved.sha256 == delivered)
        await model.lookUpGit([master])
        let size = ByteCountFormatter.string(fromByteCount: 65 << 20, countStyle: .file)
        #expect(model.notKept(approved)?.title == "Not kept · \(size) · ignored by Git")
        #expect(ReviewStates(work: try #require(model.organization.work(containing: master)), model: model).notKept?.title
                == "Not kept · \(size) · ignored by Git")
        // Save a Copy, from the verdict's row, while the file still holds them: kept.
        #expect(model.mayStillHold(approved))
        #expect(await model.saveCopy(of: approved) == nil)
        #expect(indexer.store.has(delivered) && model.notKept(approved) == nil)

        // Rewritten; the sheet's Save a Copy, on for Request Changes, keeps what was judged.
        try master65(master, first: 2)
        await model.observe(try #require(model.organization.work(containing: master)).latest)
        let recut = try #require(model.organization.work(containing: master))
        let recutFile = try #require(FileStat(master))
        let changes = try #require(await model.review([recut], as: .changesRequested, note: "Shorter", shown: [master: recutFile], save: true).first)
        #expect(changes.sha256 != delivered && indexer.store.has(changes.sha256) && model.notKept(changes) == nil)
        #expect(NoteSheet.savesByDefault(.changesRequested) && !NoteSheet.savesByDefault(.rejected) && !NoteSheet.savesByDefault(.published))

        // The agent renders over it again: both verdicts' bytes can still be compared and handed over.
        try master65(master, first: 3)
        let again = try #require(model.organization.work(containing: master))
        await model.observe(again.latest)
        let file = again.latest, delivery = file.deliveries.first { $0.sha256 == delivered }!
        #expect(model.compareEnd(delivery, artifact: file)?.source == "saved copy")
        let observation = try #require(model.observations[master])
        #expect(file.handoff(delivery, now: observation, hasSaved: model.hasSaved).sha == delivered)
        for review in [approved, changes] {
            let end = try #require(model.reviewEnd(review))
            #expect(end.source == "saved copy" && Locator.sha256(end.url.path) == review.sha256)
            let staged = try indexer.store.stage(sha: review.sha256, name: "master.mov", source: nil)
            #expect(Locator.sha256(staged.path) == review.sha256)
        }
        // The window offers them: bytes no revision recorded are compared from the verdict's row,
        // the others under Versions; each verdict's row drags its own bytes out.
        #expect(model.reviewComparison(changes)?.from.sha == changes.sha256 && model.reviewComparison(approved) == nil)
        #expect(model.reviewItem(changes) != nil && model.reviewItem(approved) != nil)
    }

    @Test func gitIsSaidOfTheBytesJudgedOnlyWhileTheFileMayStillHoldThem() async throws {
        // A 65 MiB master committed in a Git repository, delivered by a reply.
        let repo = root.appendingPathComponent("home/renders")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        #expect(Locator.run(["-C", repo.path, "init", "-q"]).status == 0)
        let master = repo.appendingPathComponent("master.mov").path
        try master65(master, first: 1)
        #expect(Locator.run(["-C", repo.path, "add", "master.mov"]).status == 0)
        #expect(Locator.run(["-C", repo.path, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "master"]).status == 0)
        try session("renders", title: "Renders", from: 0, to: 40, reply: "The [master](master.mov) is rendered.", in: repo)
        _ = try indexer.run()
        let model = relaunch()
        let work = try #require(model.organization.work(containing: master))
        let approved = try #require(await model.review([work], as: .approved).first)
        await model.lookUpGit([master])
        let size = ByteCountFormatter.string(fromByteCount: 65 << 20, countStyle: .file)
        // Committed, and still in the file: Git's history keeps the bytes judged, and the label says so.
        let committed = try #require(model.notKept(approved))
        #expect(committed.title == "Not kept · \(size) · committed" && committed.detail.contains("Git has these bytes committed"))
        #expect(!committed.detail.contains("nothing can"))
        // Rendered over and selected: Git now speaks of other bytes, so nothing of Git is said of these.
        try master65(master, first: 2)
        await model.observe(try #require(model.organization.work(containing: master)).latest)
        #expect(model.gitStates[master] == .modified && !model.mayStillHold(approved))
        let rewritten = try #require(model.notKept(approved))
        #expect(rewritten.title == "Not kept · \(size)" && !rewritten.detail.contains("Git") && !rewritten.detail.contains("uncommitted"))
    }

    @Test func aCopyAskedForThatCouldntBeSavedIsSaidNotDropped() async throws {
        let master = try ignoredMaster()
        let model = relaunch()
        let work = try #require(model.organization.work(containing: master))
        // The store can't be written: a full disk would do the same.
        let objects = root.appendingPathComponent("objects").path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: objects)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: objects) }
        let shown = try #require(FileStat(master))
        let changes = try #require(await model.review([work], as: .changesRequested, shown: [master: shown], save: true).first)
        // The verdict is made; the copy asked for isn't, and its label says why, not "without asking".
        #expect(!indexer.store.has(changes.sha256) && model.reviewRefusal == nil)
        let notKept = try #require(model.notKept(changes))
        #expect(notKept.detail.hasPrefix("You asked Gleaner to keep the bytes judged, and it couldn’t save them: "))
        #expect(!notKept.detail.contains("without asking"))
    }

    @Test func saveACopyOfBytesNoLongerThereKeepsNothing() async throws {
        let master = try ignoredMaster()
        let model = relaunch()
        let work = try #require(model.organization.work(containing: master))
        let approved = try #require(await model.review([work], as: .approved).first)
        // Rewritten in place and not looked at since: the row still offers Save a Copy, which finds other bytes.
        try master65(master, first: 2)
        #expect(model.mayStillHold(approved))
        #expect(await model.saveCopy(of: approved) == "The file has changed since, so those bytes are no longer there to save.")
        // Nothing nobody judged is left in the store, not even half moved in.
        let objects = root.appendingPathComponent("objects").path
        #expect(!indexer.store.has(try #require(Locator.sha256(master))) && !indexer.store.has(approved.sha256))
        #expect(try FileManager.default.contentsOfDirectory(atPath: objects).allSatisfy { !$0.hasPrefix(".incoming") })
        #expect(model.notKept(approved)?.detail.hasPrefix("You asked Gleaner to keep the bytes judged, but the file changed") == true)
    }

    @Test func theNoteSheetSaysNothingOfBytesGleanerAlreadyKeeps() async throws {
        let master = try ignoredMaster()
        let model = relaunch()
        let work = try #require(model.organization.work(containing: master))
        await model.saveCopy(of: work.latest.latest, artifact: work.latest)
        #expect(model.hasSaved(try #require(work.latest.latest.sha256)))
        // Relaunched, nothing read yet: the file still has the size and date its revision recorded,
        // and Gleaner saved those bytes, so a verdict on it keeps them.
        let again = relaunch()
        let kept = try #require(again.organization.work(containing: master))
        #expect(again.wouldNotKeep([kept], shown: [master: try #require(FileStat(master))]).isEmpty)
        // Rewritten, its new bytes aren't kept.
        try master65(master, first: 2)
        #expect(again.wouldNotKeep([kept], shown: [master: try #require(FileStat(master))]).map(\.size) == [65 << 20])
    }

    @Test func collectionsLeadTheOutlineAndEachWorkNamesItsCollection() async throws {
        let model = relaunch()
        let project = try #require(model.organization.work(containing: video)?.project)
        let launch = try #require(await model.newUnit(named: "Launch", in: project))
        let teaser = try #require(await model.newUnit(named: "Teaser", in: project, inside: launch.key))
        await model.add([try #require(model.organization.work(containing: video))], to: try #require(model.organization.unit(teaser.key)))
        let work = try #require(model.organization.work(containing: video))
        // Each work's row names its collection, with the one it is inside.
        #expect(model.collectionPath(work) == "Launch › Teaser")
        // The outline lists the project's collections; choosing one shows its page and keeps the outline.
        model.place = .project(project)
        #expect(model.organization.units(in: project).map(\.name) == ["Launch"])
        #expect(model.organization.works(in: launch.key, inner: true).map(\.id) == [video])
        model.outlineSelection = .unit(launch.key)
        #expect(model.currentUnit?.key == launch.key && model.place == .project(project) && model.selection == nil)
    }

    @Test func aSearchFindsWorksByTheirCollectionsNames() async throws {
        let model = relaunch()
        let project = try #require(model.organization.work(containing: video)?.project)
        let launch = try #require(await model.newUnit(named: "Launch", in: project))
        let teaser = try #require(await model.newUnit(named: "Teaser", in: project, inside: launch.key))
        await model.add([try #require(model.organization.work(containing: video))], to: try #require(model.organization.unit(teaser.key)))
        await model.keep([try #require(model.organization.candidate(cover))])
        // Its collection's name, and the name of the one that is inside, beside the project's.
        model.query = "teaser"
        #expect(model.results.map(\.id) == [video])
        model.query = "launch"
        #expect(model.results.map(\.id) == [video])
        // A result names its collection.
        #expect(model.results.first.flatMap { model.collectionPath($0.work) } == "Launch › Teaser")
        // Words still combine within one work only, and a renamed collection is found by its new name.
        model.query = "launch cover"
        #expect(model.results.isEmpty)
        await model.rename(try #require(model.organization.unit(teaser.key)), to: "Trailer")
        model.query = "trailer"
        #expect(model.results.map(\.id) == [video])
    }

    @Test func aCollectionMadeFromAGroupHoldsExactlyItAndOneUndoTakesItBack() async throws {
        let model = relaunch()
        let undo = UndoManager()
        model.undoManager = undo
        let projectKey = try #require(model.organization.work(containing: video)?.project)
        model.place = .project(projectKey)
        let project = try #require(model.organization.project(projectKey))
        // A folder of the outline, and a session's observed files: what the window shows together.
        let folder = try #require(model.outline(of: project).first { $0.folder == "out" })
        let works = folder.items.flatMap(\.works)
        let observed = try #require(model.observedSessions(in: project).first).candidates
        #expect(works.map(\.id) == [video] && Set(observed.map(\.path)) == [cover, mix])
        model.newCollection(from: works, observed)
        #expect(model.naming == .new(project: projectKey, parent: nil, adding: [video] + observed.map(\.path), command: "New Collection from These"))
        await model.commitNaming("Pilot")
        let pilot = try #require(model.organization.units.first)
        // Exactly those works, the observed files kept among them; nothing else, nothing inferred.
        #expect(Set(model.organization.works(in: pilot.key).map(\.id)) == [video, cover, mix])
        #expect(model.organization.candidates(in: projectKey).isEmpty && model.correctionGroups.count == 1)
        // On Edit › Undo under the command's own name.
        #expect(undo.canUndo && undo.undoActionName == "New Collection from These")
        // One Undo takes back the making and the adding: the files observed are candidates again.
        undo.undo()
        try await TourTests.until { model.organization.units.isEmpty }
        try await TourTests.settle(0.1)
        #expect(model.organization.units.isEmpty && model.corrections.isEmpty)
        #expect(model.organization.candidate(cover) != nil && model.organization.candidate(mix) != nil)
        #expect(model.organization.work(containing: video)?.unit == nil && !undo.canUndo)

        // Files shown together on a collection's page make one inside it, which takes them out of
        // the one they were in, as its help says; works in two projects make none.
        let series = try #require(await model.newUnit(named: "Series", in: projectKey))
        await model.add([try #require(model.organization.work(containing: video))], to: try #require(model.organization.unit(series.key)))
        let inSeries = [try #require(model.organization.work(containing: video))]
        #expect(Wording.fromThese(files: 1, takingOut: model.unitsHolding(inSeries)) == "A collection of exactly this file. Takes it out of Series. No file changes.")
        model.newCollection(from: inSeries, inside: series.key)
        #expect(model.naming == .new(project: projectKey, parent: series.key, adding: [video], command: "New Collection from These"))
        await model.commitNaming("Cut")
        let cut = try #require(model.organization.units.first { $0.name == "Cut" })
        #expect(model.organization.work(containing: video)?.unit == cut.key && model.organization.works(in: series.key).isEmpty)
        #expect(model.describe(try #require(model.correctionGroups.first)) == "Added ep01.mp4 to Cut")
        await model.keep([try #require(model.organization.candidate(cover))])
        await model.move(try #require(model.organization.work(containing: cover)), toNewProject: "Elsewhere")
        let two = [video, cover].compactMap { model.organization.work(containing: $0) }
        #expect(model.project(of: two) == nil)
        model.newCollection(from: two)
        #expect(model.naming == nil)
    }

    @Test func reviewAllLeavesVideoAndAudioToTheirOwnVerdicts() throws {
        func work(_ name: String) -> Work {
            let path = "/w/project/" + name
            let delivery = Delivery(id: path + "#1", number: 1, path: path, deliveredAt: t0, replyLine: 1, provider: .claudeCode,
                                    sessionTitle: nil, request: nil, cwd: "/w/project", evidence: [], logPath: "/logs/s.jsonl", capture: nil)
            let file = Artifact(path: path, deliveries: [delivery])
            return Work(files: [file], deliveries: file.deliveries, project: "/w/project")
        }
        let works = ["intro.mp4", "intro.wav", "chart.png", "notes.md", "brief.pdf", "inputs.json", "scene.usdz", "outro.mp4"].map(work)
        let stat = FileStat(size: 1, createdAt: t0, modifiedAt: t0, inode: 1)
        // The page drew all but the last video, further down and not scrolled to yet.
        let shown = Dictionary(uniqueKeysWithValues: works.dropLast().map { ($0.latest.path, stat) })
        // Every form played or drawn, but the PDF, which Quick Look draws; what a program reads and a
        // model, drawn as their icons, are never passed with others either.
        let drawn = Set(works.dropLast().map(\.latest.path)).subtracting(["/w/project/brief.pdf"])
        let all = ReviewAll(works, drawn: drawn, shown: shown, hasFile: { _ in true }) { _ in .none }
        #expect(all.approve.map(\.name) == ["chart.png", "notes.md"] && all.changes.map(\.name) == ["chart.png", "notes.md"])
        // Every video and audio file waiting is counted, drawn yet or not.
        #expect(all.videos == 2 && all.audio == 1 && all.oneByOne == "2 videos and 1 audio file to review one by one")
        // A video with a verdict on its bytes no longer waits one by one, nor one with no file there.
        let approved = Review(id: 1, kind: .approved, path: works[0].latest.path, note: nil, sha256: "a", file: stat, madeAt: t0)
        let after = ReviewAll(works, drawn: drawn, shown: shown, hasFile: { $0.name != "outro.mp4" }) {
            $0.name == "intro.mp4" ? .current(approved) : .none
        }
        #expect(after.videos == 0 && after.oneByOne == "1 audio file to review one by one")
    }

    @Test func aHiddenFileIsNeverObservedSoNeverOfferedKeep() async throws {
        try file(".env", "API_KEY=synthetic", at: 24)
        try file(".DS_Store", "finder", at: 24)
        try session("three", title: "Settings", from: 23, to: 45, reply: "Settings are written.")
        _ = try indexer.run()
        let model = relaunch()
        let project = try #require(model.projects.first)
        let observed = model.observedSessions(in: project).flatMap(\.candidates).map(\.name)
        #expect(!observed.isEmpty && !observed.contains { $0.hasPrefix(".") })
        #expect(model.organization.candidate(series.path + "/.env") == nil && model.organization.candidate(series.path + "/.DS_Store") == nil)
    }

    @Test func aReviewedFileSeenChangedThenDeletedStaysChangedForTheSession() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let made = try #require(await model.newUnit(named: "Pilot", in: work.project))
        await model.add([work], to: try #require(model.organization.unit(made.key)))
        let inUnit = try #require(model.organization.work(containing: video))
        let approved = try #require(await model.review([inUnit], as: .approved).first)
        // Selected after a rewrite: other bytes read. Deleted afterwards: still changed, still waiting (A16).
        try file("out/ep01.mp4", "episode one, rewritten", at: 45)
        await model.observe(try #require(model.organization.work(containing: video)).latest)
        #expect(model.verdict(of: try #require(model.organization.work(containing: video))) == .changed(approved))
        try FileManager.default.removeItem(atPath: video)
        await model.observe(try #require(model.organization.work(containing: video)).latest)
        let gone = try #require(model.organization.work(containing: video))
        #expect(model.verdict(of: gone) == .changed(approved) && model.toReview.flatMap(\.works).map(\.id) == [video])
        // After a relaunch Gleaner no longer knows what it saw: the verdict stands as made.
        let again = relaunch()
        #expect(again.verdict(of: try #require(again.organization.work(containing: video))) == .unavailable(approved))
    }

    @Test func aReviewedFileAPageDrewChangedThenDeletedMayStillHaveChanged() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let made = try #require(await model.newUnit(named: "Pilot", in: work.project))
        await model.add([work], to: try #require(model.organization.unit(made.key)))
        let inUnit = try #require(model.organization.work(containing: video))
        let approved = try #require(await model.review([inUnit], as: .approved).first)
        try file("out/ep01.mp4", "episode one, rewritten by hand", at: 46)
        model.noteShown(video, FileStat(video))
        try FileManager.default.removeItem(atPath: video)
        model.noteShown(video, FileStat(video))
        let gone = try #require(model.organization.work(containing: video))
        #expect(model.verdict(of: gone) == .mayHaveChanged(approved) && model.toReview.flatMap(\.works).map(\.id) == [video])
    }

    @Test func aReviewedFileDrawnAsJudgedThenDeletedKeepsItsVerdict() async throws {
        let model = relaunch()
        let work = try #require(model.organization.work(containing: video))
        let made = try #require(await model.newUnit(named: "Pilot", in: work.project))
        await model.add([work], to: try #require(model.organization.unit(made.key)))
        let inUnit = try #require(model.organization.work(containing: video))
        let approved = try #require(await model.review([inUnit], as: .approved).first)
        model.noteShown(video, FileStat(video))
        try FileManager.default.removeItem(atPath: video)
        model.noteShown(video, FileStat(video))
        // Seen as judged, then gone: the verdict stands as made, and nothing waits (A22).
        #expect(model.verdict(of: try #require(model.organization.work(containing: video))) == .unavailable(approved))
        #expect(model.toReview.isEmpty)
    }

    @Test func anImageNothingCanDrawIsSaidAsSuchNotAsLoading() async throws {
        let path = series.path + "/broken.png"
        try Data("not an image".utf8).write(to: URL(fileURLWithPath: path))
        #expect(await ImageFile.load(path, pixels: 200) == nil)
    }
}
