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
        #expect(d1.model == "m")
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

    @Test func savingACopySaysWhyNothingWasKept() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let build = try artifact("build.dmg")
        #expect(indexer.isLarge(try #require(build.latest.capture)))

        // Rebuilt in place: the file no longer holds delivery 1, so nothing is kept as its copy.
        try write("big build b2, rebuilt in place after delivery", to: "out/build.dmg", modified: Date())
        #expect(throws: ContentStore.Failure.self) { try indexer.saveCopy(of: build.latest, at: Date()) }
        #expect(try artifact("build.dmg").latest.capture?.savedAt == nil)

        // The delivered bytes are back: the copy is kept.
        try write("big build b1, larger than the save limit", to: "out/build.dmg", modified: Date())
        try indexer.saveCopy(of: build.latest, at: Date())
        #expect(try artifact("build.dmg").latest.capture?.savedAt != nil)
        #expect(saved(try #require(build.latest.sha256)))
    }

    @Test func aSmallFileGleanerCouldNotSaveIsNotALargeFile() throws {
        // The store can't be written, so the copy made at capture fails.
        let blocked = root.appendingPathComponent("blocked")
        try "not a folder".write(to: blocked, atomically: true, encoding: .utf8)
        let indexer = Indexer(
            registry: indexer.registry,
            store: ContentStore(objects: blocked.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: indexer.sources)
        indexer.saveLimit = 32
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let capture = try #require(try artifact("demo.mp4").latest.capture)
        #expect(capture.sha256 != nil && capture.savedAt == nil)
        #expect(!indexer.isLarge(capture))
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
        #expect(video.onDisk(now(video.path), hasSaved: saved) == .rolledBack(to: 1, latest: 2, firstSeen: nil))

        // Search for words from the first request opens the first delivery.
        #expect(video.match(["harness"]) == 1)
        #expect(video.match(["intro"]) == 0)
        #expect(video.match(["nothing-like-this"]) == nil)
        // Words that sit in every path (home, Projects) are not a file name.
        #expect(video.match(["users"]) == nil)
        #expect(video.match(["out"]) == 0)

        // Words from two different deliveries don't combine into one match.
        #expect(video.match(["harness", "intro"]) == nil)
        // The file name combines with either delivery's words.
        #expect(video.match(["demo", "harness"]) == 1)
        #expect(video.match(["demo"]) == 0)
    }

    @Test func deliveredWithNamesTheSiblingsDeliveryFromThatReply() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let second = delivered.addingTimeInterval(3600)
        try write("video v2", to: "out/demo.mp4", modified: second.addingTimeInterval(-30))
        try appendLog([
            user("Tighten the intro and render again", at: second.addingTimeInterval(-300)),
            assistant("Rendered again: [demo](out/demo.mp4)", at: second, cwd: project.path),
        ])
        _ = try indexer.run(now: { second.addingTimeInterval(20) })
        let library = Artifact.deliveredWith(try indexer.registry.artifacts())
        let report = try artifact("report.md"), video = try artifact("demo.mp4"), build = try artifact("build.dmg")

        // The report's reply also named the video and the build, in that order: their deliveries
        // from that reply, not the video's later one.
        let siblings = try #require(library[report.latest.id])
        #expect(siblings.map(\.path) == [video.path, build.path])
        #expect(siblings.map(\.id) == [video.deliveries[1].id, build.latest.id])
        // The second reply named the video alone.
        #expect(library[video.latest.id] == nil)
    }

    @Test func deliveredWithKeepsAReplyTogetherAcrossItsRecords() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let later = delivered.addingTimeInterval(600)
        for name in ["summary.md", "notes.md", "chart.png"] {
            try write("\(name) v1", to: "out/\(name)", modified: later.addingTimeInterval(-30))
        }
        // One reply written as two records, seconds apart.
        try appendLog([
            user("Write it up", at: later.addingTimeInterval(-60)),
            assistant("Summary: [summary](out/summary.md)", at: later, cwd: project.path),
            assistant("Notes: [notes](out/notes.md), and the chart: [chart](out/chart.png)",
                      at: later.addingTimeInterval(5), cwd: project.path),
        ])
        _ = try indexer.run(now: { later.addingTimeInterval(20) })
        let library = Artifact.deliveredWith(try indexer.registry.artifacts())
        let summary = try artifact("summary.md"), notes = try artifact("notes.md"), chart = try artifact("chart.png")

        // Every file the reply named, in the order it named them, and nothing from the first reply.
        #expect(library[notes.latest.id]?.map(\.path) == [summary.path, chart.path])
        #expect(library[summary.latest.id]?.map(\.path) == [notes.path, chart.path])
        #expect(library[chart.latest.id]?.map(\.path) == [summary.path, notes.path])
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

    @Test func rollbackToBytesFirstSeenLaterIsStillRecognized() throws {
        let later = delivered.addingTimeInterval(30 * 86400)
        _ = try indexer.run(now: { later })
        let second = delivered.addingTimeInterval(3600)
        try write("video v2", to: "out/demo.mp4", modified: second.addingTimeInterval(-30))
        try appendLog([
            user("Tighten the intro and render again", at: second.addingTimeInterval(-300)),
            assistant("Rendered again: [demo](out/demo.mp4)", at: second, cwd: project.path),
        ])
        _ = try indexer.run(now: { later.addingTimeInterval(60) })
        let video = try artifact("demo.mp4")
        #expect(video.deliveries.allSatisfy { $0.capture?.provenance == .firstSeenAfterDelivery })

        try write("video v1", to: "out/demo.mp4", modified: Date())
        let observation = now(video.path)
        #expect(video.onDisk(observation, hasSaved: saved) == .rolledBack(to: 1, latest: 2, firstSeen: later))
        guard case .ready(_, .savedCopy, _) = video.handoff(video.latest, now: observation, hasSaved: saved) else {
            Issue.record("expected delivery 2's saved copy"); return
        }
    }

    @Test func aMalformedRereadKeepsWhatItCannotReadAndReadsTheLogAgain() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let before = try artifact("demo.mp4").latest.capture
        // The delivering record is damaged in place, as by a write that went wrong; the log is no shorter.
        let log = root.appendingPathComponent("claude/-Praxis/session-1.jsonl")
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        try ([String(lines[0]), lines[1].dropLast() + "!"].joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)

        func partialLogs(_ report: Indexer.Report) -> [String]? {
            report.sources[.claudeCode]?.partialLogs.map { ($0 as NSString).lastPathComponent }
        }
        #expect(partialLogs(try indexer.run(now: { delivered.addingTimeInterval(40) })) == ["session-1.jsonl"])
        #expect(try indexer.registry.artifacts().count == 3)
        #expect(try artifact("demo.mp4").latest.capture == before)
        // Not marked read: the next run reads it again and says so again.
        #expect(partialLogs(try indexer.run()) == ["session-1.jsonl"])

        // Once the log reads whole, and no shorter than it was, what it no longer names is removed.
        try ([String(lines[0]), assistant("Video: [demo](out/demo.mp4)", at: delivered, cwd: project.path),
              user(String(repeating: "And one more thing. ", count: 20), at: delivered.addingTimeInterval(50))]
            .joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)
        #expect(partialLogs(try indexer.run(now: { delivered.addingTimeInterval(60) })) == [])
        #expect(try indexer.registry.artifacts().map(\.name) == ["demo.mp4"])
        #expect(try artifact("demo.mp4").latest.capture == before)
    }

    @Test func aLogShorterThanWhenLastReadRemovesNothing() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        // The log is rewritten shorter: well-formed, but the reply no longer names the report or the build.
        let log = root.appendingPathComponent("claude/-Praxis/session-1.jsonl")
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        try ([String(lines[0]), assistant("Video: [demo](out/demo.mp4)", at: delivered, cwd: project.path)]
            .joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)

        func shortenedLogs(_ report: Indexer.Report) -> [String]? {
            report.sources[.claudeCode]?.shortenedLogs.map { ($0 as NSString).lastPathComponent }
        }
        let report = try indexer.run(now: { delivered.addingTimeInterval(40) })
        #expect(shortenedLogs(report) == ["session-1.jsonl"])
        #expect(report.sources[.claudeCode]?.hasProblems == true)
        // Reading again can't bring the lost records back.
        #expect(report.sources[.claudeCode]?.isIncomplete == false)
        #expect(try indexer.registry.artifacts().map(\.name).sorted() == ["build.dmg", "demo.mp4", "report.md"])
        // Still shorter than when it was read whole, next run too.
        #expect(shortenedLogs(try indexer.run()) == ["session-1.jsonl"])
        #expect(try indexer.registry.artifacts().count == 3)
    }

    @Test func aLogFoundShorterRemovesNothingOnceItGrowsAgain() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        // Replaced by a copy without the delivering reply (a sync or a restore went back), then the
        // session goes on past the size the log had.
        let log = root.appendingPathComponent("claude/-Praxis/session-1.jsonl")
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        try (String(lines[0]) + "\n").write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { delivered.addingTimeInterval(40) })
        try appendLog([user(String(repeating: "And one more thing. ", count: 40), at: delivered.addingTimeInterval(60)),
                       assistant("Noted.", at: delivered.addingTimeInterval(70), cwd: project.path)])

        let report = try indexer.run(now: { delivered.addingTimeInterval(80) })
        // The records it lost stay lost: it never shows a delivery is gone.
        #expect(try indexer.registry.artifacts().map(\.name).sorted() == ["build.dmg", "demo.mp4", "report.md"])
        #expect(report.sources[.claudeCode]?.shortenedLogs.map { ($0 as NSString).lastPathComponent } == ["session-1.jsonl"])
    }

    @Test func aLogShorterSinceAnExtractorUpgradeRemovesNothing() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let log = root.appendingPathComponent("claude/-Praxis/session-1.jsonl")
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        try ([String(lines[0]), assistant("Video: [demo](out/demo.mp4)", at: delivered, cwd: project.path)]
            .joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)
        try indexer.registry.db.execute("PRAGMA user_version = 1")
        let upgraded = Indexer(
            registry: try Registry(path: root.appendingPathComponent("support/registry.sqlite").path),
            store: indexer.store, sources: indexer.sources)
        _ = try upgraded.run(now: { delivered.addingTimeInterval(40) })
        #expect(try upgraded.registry.artifacts().count == 3)
    }

    @Test func aDatabaseErrorFailsOnlyItsOwnLog() throws {
        // The registry refuses one log's delivery; the other log is still read.
        try indexer.registry.db.execute("""
            CREATE TRIGGER refuse BEFORE INSERT ON deliveries WHEN NEW.path LIKE '%refused%'
            BEGIN SELECT RAISE(ABORT, 'refused'); END;
            """)
        try (assistant("Notes: [notes](out/refused.md)", at: delivered, cwd: project.path) + "\n")
            .write(to: root.appendingPathComponent("claude/-Praxis/session-2.jsonl"), atomically: true, encoding: .utf8)

        let report = try indexer.run(now: { delivered.addingTimeInterval(20) })
        #expect(report.sources[.claudeCode]?.failures.count == 1)
        #expect(try indexer.registry.artifacts().count == 3)
        // Not marked read: it is tried again next run.
        #expect(try indexer.run().sources[.claudeCode]?.failures.count == 1)
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
        // A library read before Gleaner kept each reply's model gets it from the reread.
        try indexer.registry.db.execute("UPDATE deliveries SET model = NULL; PRAGMA user_version = 1")
        let upgraded = Indexer(
            registry: try Registry(path: root.appendingPathComponent("support/registry.sqlite").path),
            store: indexer.store, sources: indexer.sources)
        let report = try upgraded.run(now: { delivered.addingTimeInterval(9999) })
        #expect(report.logsRead == 1)
        #expect(report.newDeliveries == 0)
        let after = try #require(try upgraded.registry.artifacts().first { $0.name == "demo.mp4" })
        #expect(after.latest.capture == before)
        #expect(after.latest.model == "m")
    }

    @Test func aRereadThatFindsTheFirstMentionInAnotherRecordKeepsTheDeliveryAndItsCapture() throws {
        let notes = project.appendingPathComponent("out/notes.md")
        try write("notes n1", to: "out/notes.md", modified: delivered.addingTimeInterval(-30))
        // One reply in two records (log lines 4 and 5): the first shows the path inside an example,
        // the second hands the file over.
        let example = "Check it with:\\n````\\n```sh\\ncat \(notes.path)\\n```\\n````"
        try appendLog([
            user("Write the release notes", at: delivered.addingTimeInterval(-60)),
            assistant(example, at: delivered, cwd: project.path),
            assistant("Done: [notes](out/notes.md)", at: delivered.addingTimeInterval(1), cwd: project.path),
        ])
        // An older extractor read the path in the example, so it took the first record's mention as
        // the first: the delivery was recorded, and its bytes captured, under that record.
        let logPath = try #require(try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("claude/-Praxis"), includingPropertiesForKeys: nil).first).path
        let older = SessionLog(
            session: SessionInfo(provider: .claudeCode, id: "s1", title: nil, cwd: project.path, logPath: logPath),
            turns: [Turn(request: "Write the release notes", parts: [
                ReplyPart(text: "Check it with: cat \(notes.path)", line: 4, at: delivered, cwd: project.path),
                ReplyPart(text: "Done: [notes](out/notes.md)", line: 5, at: delivered.addingTimeInterval(1), cwd: project.path),
            ])],
            unknownRecordTypes: [:], malformedLines: 0)
        _ = try indexer.ingest(older, isComplete: true, now: delivered.addingTimeInterval(20))
        let before = try artifact("notes.md").latest
        #expect(before.capture?.provenance == .atDelivery)

        // The file is edited, then the current extractor rereads the log: the example is masked and
        // the reply's first mention is now in the second record.
        try write("notes n2, edited later", to: "out/notes.md", modified: Date())
        _ = try indexer.run(now: { delivered.addingTimeInterval(9999) })
        let after = try artifact("notes.md")
        #expect(after.deliveries.map(\.id) == [before.id])
        #expect(after.latest.capture == before.capture)
        #expect(after.latest.evidence.map(\.line) == [5])
    }

    @Test func aDeliveryAdmittedAgainGetsItsOriginalCaptureBack() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let before = try artifact("demo.mp4").latest
        #expect(before.capture?.provenance == .atDelivery)

        // The reply is reread under a rule that no longer admits the video (a link written inside
        // inline code), and the file is edited meanwhile.
        let log = root.appendingPathComponent("claude/-Praxis/session-1.jsonl")
        let original = try String(contentsOf: log, encoding: .utf8)
        try original.replacingOccurrences(of: "[demo](out/demo.mp4)", with: "`[demo](out/demo.mp4)`")
            .write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { delivered.addingTimeInterval(60) })
        #expect(try indexer.registry.artifacts().map(\.name).sorted() == ["build.dmg", "report.md"])
        try write("video v2, edited after delivery", to: "out/demo.mp4", modified: Date())

        // Admitted again: the same delivery, with what Gleaner saw at delivery, not what is there now.
        try (original + user("Anything else?", at: delivered.addingTimeInterval(90)) + "\n")
            .write(to: log, atomically: true, encoding: .utf8)
        #expect(try indexer.run(now: { delivered.addingTimeInterval(9999) }).newDeliveries == 0)
        let after = try artifact("demo.mp4")
        #expect(after.deliveries.map(\.id) == [before.id])
        #expect(after.latest.capture == before.capture)
    }

    @Test func aFolderInPlaceOfADeliveredFileNeverStandsInForIt() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let fm = FileManager.default
        for name in ["demo.mp4", "build.dmg"] {
            try fm.removeItem(at: project.appendingPathComponent("out/\(name)"))
            try fm.createDirectory(at: project.appendingPathComponent("out/\(name)"), withIntermediateDirectories: false)
        }

        // The delivery was a file: its saved copy is still what a drag hands over.
        let video = try artifact("demo.mp4")
        let observation = now(video.path)
        #expect(video.handoff(video.latest, now: observation, hasSaved: saved)
                == .ready(sha: video.latest.sha256!, from: .savedCopy, firstSeen: nil))
        #expect(video.onDisk(observation, hasSaved: saved) == .changed(since: 1))

        // Without a saved copy the delivery is unavailable; the folder is not offered in its place.
        let build = try artifact("build.dmg")
        #expect(build.handoff(build.latest, now: now(build.path), hasSaved: saved)
                == .unavailable(alternative: nil, currentSha: nil))
    }

    @Test func aDeliveredFolderIsHandedOverOnlyWhileItIsAFolder() throws {
        let site = project.appendingPathComponent("out/site")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        try appendLog([assistant("Site: [site](out/site)", at: delivered.addingTimeInterval(1), cwd: project.path)])
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let folder = try artifact("site")
        #expect(folder.kind == .folder)
        #expect(folder.handoff(folder.latest, now: now(site.path), hasSaved: saved) == .folder)
        #expect(folder.onDisk(now(site.path), hasSaved: saved) == .folder)

        try FileManager.default.removeItem(at: site)
        #expect(folder.handoff(folder.latest, now: now(site.path), hasSaved: saved) == .lost)

        // A file in its place is not the delivered folder.
        try "not the folder".write(to: site, atomically: true, encoding: .utf8)
        let observation = now(site.path)
        #expect(folder.handoff(folder.latest, now: observation, hasSaved: saved)
                == .unavailable(alternative: nil, currentSha: observation.state.sha256))
        #expect(folder.onDisk(observation, hasSaved: saved) == .changed(since: 1))
    }

    @Test func aDeliveredFolderGoneFromDiskIsNeverOfferedFromGit() throws {
        let site = project.appendingPathComponent("out/site")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        try "home".write(to: site.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "site"]
        for args in [["init", "-q"], ["add", "out/site"], commit] {
            #expect(Locator.run(["-C", project.path] + args).status == 0)
        }
        try appendLog([assistant("Site: [site](out/site)", at: delivered.addingTimeInterval(1), cwd: project.path)])
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let folder = try artifact("site")
        try FileManager.default.removeItem(at: site)

        // Git still has a tree at the path, but folders aren't versioned: nothing shows it is the
        // folder that was delivered.
        let observation = now(site.path)
        #expect(observation.state.git == .recoverableFromHead)
        #expect(folder.handoff(folder.latest, now: observation, hasSaved: saved) == .lost)
        #expect(folder.onDisk(observation, hasSaved: saved) == .lost)
    }

    @Test func fileGoneBeforeFirstLookIsNeverObserved() throws {
        try FileManager.default.removeItem(at: project.appendingPathComponent("out/demo.mp4"))
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let video = try artifact("demo.mp4")
        #expect(video.latest.capture?.provenance == .neverObserved)
        #expect(video.latest.capture?.kind == .missing)
        #expect(video.onDisk(now(video.path), hasSaved: saved) == .lost)
        #expect(video.handoff(video.latest, now: now(video.path), hasSaved: saved) == .lost)
    }

    @Test func aFileGleanerCannotReadIsUnreadableUntilItFirstReadsIt() throws {
        let fm = FileManager.default
        let path = project.appendingPathComponent("out/demo.mp4").path
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })

        // There, but never read: no hash, and nothing says it was seen, gone or changed.
        let video = try artifact("demo.mp4")
        let unread = try #require(video.latest.capture)
        #expect(unread.sha256 == nil && unread.savedAt == nil)
        #expect(unread.kind == .unreadable)
        #expect(unread.provenance == .neverObserved)
        let observation = now(path)
        #expect(observation.state.kind == .unreadable)
        #expect(video.onDisk(observation, hasSaved: saved) == .unreadable)
        #expect(video.handoff(video.latest, now: observation, hasSaved: saved) == .unavailable(alternative: nil, currentSha: nil))
        #expect(try !indexer.completeCaptures(of: path, now: delivered.addingTimeInterval(60)))

        // Access is granted: Gleaner's first read completes the capture, as first seen later.
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        let read = delivered.addingTimeInterval(3600)
        #expect(try indexer.completeCaptures(of: path, now: read))
        let completed = try #require(try artifact("demo.mp4").latest.capture)
        #expect(completed.kind == .file)
        #expect(completed.provenance == .firstSeenAfterDelivery)
        #expect(completed.observedAt == read)
        #expect(saved(try #require(completed.sha256)))
        #expect(try artifact("demo.mp4").onDisk(now(path), hasSaved: saved) == .unchangedSinceFirstSeen(read))

        // Once: a capture with a hash is never rewritten.
        try write("video v2", to: "out/demo.mp4", modified: Date())
        #expect(try !indexer.completeCaptures(of: path, now: Date()))
        #expect(try artifact("demo.mp4").latest.capture == completed)
    }

    @Test func aFileThatAppearsLaterIsFirstSeenLater() throws {
        let path = project.appendingPathComponent("out/demo.mp4").path
        try FileManager.default.removeItem(atPath: path)
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        #expect(try artifact("demo.mp4").latest.capture?.kind == .missing)

        try write("video v1", to: "out/demo.mp4", modified: Date())
        let read = delivered.addingTimeInterval(3600)
        #expect(try indexer.completeCaptures(of: path, now: read))
        let video = try artifact("demo.mp4")
        #expect(video.latest.capture?.provenance == .firstSeenAfterDelivery)
        #expect(video.handoff(video.latest, now: now(path), hasSaved: saved)
                == .ready(sha: try #require(video.latest.sha256), from: .original, firstSeen: read))
    }

    @Test func aPipeAtFirstLookIsNotARegularFile() throws {
        let path = project.appendingPathComponent("out/demo.mp4").path
        try FileManager.default.removeItem(atPath: path)
        #expect(mkfifo(path, 0o600) == 0)
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let capture = try #require(try artifact("demo.mp4").latest.capture)
        #expect(capture.kind == .special && capture.sha256 == nil && capture.provenance == .neverObserved)
    }

    @Test func aLaterDeliveryThatReadsTheFileCompletesAnEarlierOneNeverSeen() throws {
        try FileManager.default.removeItem(at: project.appendingPathComponent("out/demo.mp4"))
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let second = delivered.addingTimeInterval(3600)
        try write("video v2", to: "out/demo.mp4", modified: second.addingTimeInterval(-30))
        try appendLog([
            user("Render it again", at: second.addingTimeInterval(-300)),
            assistant("Rendered again: [demo](out/demo.mp4)", at: second, cwd: project.path),
        ])
        _ = try indexer.run(now: { second.addingTimeInterval(20) })

        // Gleaner first read the file for delivery 2: for delivery 1 that is what it first saw, later.
        let video = try artifact("demo.mp4")
        #expect(video.latest.capture?.provenance == .atDelivery)
        let first = try #require(video.deliveries[1].capture)
        #expect(first.provenance == .firstSeenAfterDelivery)
        #expect(first.sha256 == video.latest.sha256)
    }

    // MARK: sources

    @Test func eachSourceSaysWhetherItsFolderWasThere() throws {
        let report = try indexer.run(now: { delivered.addingTimeInterval(20) })
        #expect(report.sources[.claudeCode] == Indexer.Report.Source(folder: .listed))
        #expect(report.sources[.codex] == Indexer.Report.Source(folder: .listed))

        try FileManager.default.removeItem(at: root.appendingPathComponent("codex/sessions"))
        #expect(try indexer.run().sources[.codex]?.folder == .absent)
    }

    @Test func anUnreadableFolderIsNeverTakenForAnEmptyOne() throws {
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        let fm = FileManager.default
        let denied = [root.appendingPathComponent("claude"), root.appendingPathComponent("codex/sessions")]
        for folder in denied { try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path) }
        defer { for folder in denied { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) } }

        let report = try indexer.run()
        for provider in Provider.allCases {
            guard case .unreadable = report.sources[provider]?.folder else {
                Issue.record("\(provider) read as if its folder were listed"); continue
            }
        }
        // What the library already holds stays.
        #expect(try indexer.registry.artifacts().count == 3)
    }

    @Test func aFolderInsideASourceThatCannotBeListedLeavesTheRestRead() throws {
        let fm = FileManager.default
        // Codex delivered from a readable day; another day, and a Claude project folder, can't be listed.
        let day = root.appendingPathComponent("codex/sessions/2026/10/17")
        try fm.createDirectory(at: day, withIntermediateDirectories: true)
        try [#"{"type":"session_meta","payload":{"id":"t1","cwd":"\#(project.path)"}}"#,
             #"{"type":"response_item","timestamp":"\#(stamp(delivered))","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Notes: [notes](out/codex.md)"}]}}"#]
            .joined(separator: "\n").write(to: day.appendingPathComponent("rollout-1.jsonl"), atomically: true, encoding: .utf8)
        let denied = [root.appendingPathComponent("claude/-Locked"), root.appendingPathComponent("codex/sessions/2025")]
        for folder in denied {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path)
        }
        defer { for folder in denied { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) } }

        let report = try indexer.run(now: { delivered.addingTimeInterval(20) })
        for provider in Provider.allCases {
            #expect(report.sources[provider]?.folder == .listed)
            #expect(report.sources[provider]?.unlistedFolders.count == 1)
            #expect(report.sources[provider]?.hasProblems == true)
        }
        #expect(report.logsRead == 2)
        #expect(try indexer.registry.artifacts().map(\.name).sorted() == ["build.dmg", "codex.md", "demo.mp4", "report.md"])
    }

    @Test func unknownRecordTypesAreReportedForTheirOwnSource() throws {
        try appendLog([#"{"type":"brand-new-record","sessionId":"s1"}"#])
        let report = try indexer.run(now: { delivered.addingTimeInterval(20) })
        #expect(report.sources[.claudeCode]?.unknownRecordTypes == ["brand-new-record": 1])
        #expect(report.sources[.claudeCode]?.hasProblems == true)
        #expect(report.sources[.codex]?.hasProblems == false)
    }

    @Test func unknownRecordTypesAreReportedOnEveryRunNotOnlyTheOneThatReadThem() throws {
        try appendLog([#"{"type":"brand-new-record","sessionId":"s1"}"#])
        _ = try indexer.run(now: { delivered.addingTimeInterval(20) })
        // The log is unchanged, so it isn't read again; the format change is still there.
        let again = try indexer.run()
        #expect(again.logsRead == 0)
        #expect(again.sources[.claudeCode]?.unknownRecordTypes == ["brand-new-record": 1])
        // So it is after a relaunch.
        let relaunched = Indexer(
            registry: try Registry(path: root.appendingPathComponent("support/registry.sqlite").path),
            store: indexer.store, sources: indexer.sources)
        #expect(try relaunched.run().sources[.claudeCode]?.unknownRecordTypes == ["brand-new-record": 1])
    }
}

private extension String {
    func creatingParent() throws -> String {
        try FileManager.default.createDirectory(
            atPath: (self as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        return self
    }
}
