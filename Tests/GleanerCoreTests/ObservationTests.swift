import Foundation
import Testing
@testable import GleanerCore

/// What appeared or changed in a session's workspace during its span, on a synthetic machine, in
/// several kinds of work: kept as observations beside the deliveries, never as deliveries, read
/// from metadata only, and corrected only by appending (docs/design/capture.md, layer 1).
@Suite struct ObservationTests {
    let root: URL
    /// The synthetic home: a session working here has no workspace walked.
    let home: URL
    let indexer: Indexer
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("gleaner-observe-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        for folder in [home, root.appendingPathComponent("claude"), root.appendingPathComponent("codex/sessions")] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
        indexer.home = home.path
    }

    // MARK: helpers

    func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    /// A Claude Code session working in `cwd`: asked at `start`, replied at `end`. Its log is dated
    /// as an agent's is: created with its first record, last written with its last.
    @discardableResult
    func session(_ id: String, in cwd: URL, from start: Date, to end: Date, reply: String, title: String? = nil) throws -> String {
        let folder = root.appendingPathComponent("claude/\(id)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func line(_ object: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) }
        let stamp = { (date: Date) in date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
        var lines = [
            try line(["type": "user", "sessionId": id, "cwd": cwd.path, "timestamp": stamp(start), "origin": ["kind": "human"],
                      "message": ["role": "user", "content": "Make the next part"]]),
            try line(["type": "assistant", "sessionId": id, "cwd": cwd.path, "timestamp": stamp(end),
                      "message": ["role": "assistant", "model": "m", "content": [["type": "text", "text": reply]]]]),
        ]
        if let title { lines.append(try line(["type": "custom-title", "sessionId": id, "customTitle": title])) }
        let log = folder.appendingPathComponent("\(id).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: log, atomically: false, encoding: .utf8)
        try Self.date(log, created: start, modified: end)
        // As listing the agent's folder spells it, which keys the session: `/private/var`, not `/var`.
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent == log.lastPathComponent }?.path ?? log.path
    }

    static func date(_ url: URL, created: Date, modified: Date) throws {
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    /// A file at `relative` in `folder`, created and last written at these times.
    @discardableResult
    func file(_ relative: String, in folder: URL, created: Date, modified: Date? = nil, text: String = "x") throws -> String {
        let url = folder.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try Self.date(url, created: created, modified: modified ?? created)
        return url.path
    }

    func folder(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func observed() throws -> [Observed] { try indexer.registry.observations() }

    func organization() throws -> Organization {
        Organization(artifacts: try indexer.registry.artifacts(), observations: try observed(), corrections: try indexer.registry.corrections())
    }

    func names(_ paths: some Sequence<String>) -> [String] { paths.map { ($0 as NSString).lastPathComponent }.sorted() }

    // MARK: kinds of work

    @Test func aVideoSeriesWhoseReplyNamesOnlyAFolder() throws {
        let series = try folder("Projects/series")
        try file("README.md", in: series, created: minutes(-600))
        try file("episodes/00-overview/notes.md", in: series, created: minutes(5))
        for (n, name) in ["ep00.mp4", "ep00.mix.wav", "ep00.narration.wav", "ep00.inputs.json"].enumerated() {
            try file("out/" + name, in: series, created: minutes(30 + Double(n)))
        }
        try file("covers/ov-4x3.svg", in: series, created: minutes(40))
        try file("covers/ov-4x3.png", in: series, created: minutes(41))
        try file("scripts/render.py", in: series, created: minutes(2))
        for n in 0..<300 { try file(String(format: "out/segments/seg-%03d.ts", n), in: series, created: minutes(10 + Double(n) / 20)) }
        try session("series", in: series, from: t0, to: minutes(60), reply: "Everything is in [out](out/).", title: "Reading list series")
        let report = try indexer.run()
        #expect(report.sources[.claudeCode]?.workspaceProblems == [])

        let observed = try observed()
        // Every file whose creation date falls in the span, whatever its kind; nothing older.
        #expect(observed.count == 1 + 4 + 2 + 1 + 300)
        #expect(observed.allSatisfy { $0.kind == .appeared && $0.sessionTitle == "Reading list series" && $0.workspace == series.path })
        #expect(!observed.contains { $0.path.hasSuffix("README.md") })

        let organization = try organization()
        // The reply handed over the folder; the files in it are candidates beside it, not deliveries.
        #expect(organization.works.map(\.name) == ["out"])
        #expect(organization.candidates.count == observed.count)
        #expect(organization.candidates.allSatisfy { $0.project == series.path && !$0.inRepository })
        #expect(organization.candidates(in: series.path).count == observed.count)

        let entries = organization.candidates.map(Listing.Entry.candidate)
        let rows = Listing.rows(entries)
        let folded = rows.compactMap { row -> (String, Int)? in
            if case .folded(let folder, _, let candidates) = row { (folder, candidates.count) } else { nil }
        }
        #expect(folded.count == 1 && folded[0].0 == series.path + "/out/segments" && folded[0].1 == 300)
        let together = rows.compactMap { row -> (String, [String])? in
            if case .together(let stem, let members) = row { (stem, members.map { ($0.path as NSString).lastPathComponent }) } else { nil }
        }
        #expect(together.map(\.0).sorted() == ["ep00", "ov-4x3"])
        // What a person opens comes before what a program reads, each newest first.
        #expect(together.first { $0.0 == "ep00" }?.1 == ["ep00.narration.wav", "ep00.mix.wav", "ep00.mp4", "ep00.inputs.json"])
        // Showing them together joins nothing.
        #expect(organization.suggestions.isEmpty && organization.works.count == 1)
    }

    @Test func aReportWithMarkdownPDFAndCharts() throws {
        let report = try folder("Projects/q3-report")
        try file("style.css", in: report, created: minutes(-300), modified: minutes(20))
        try file("report.md", in: report, created: minutes(10))
        try file("report.pdf", in: report, created: minutes(50))
        try file("charts/revenue.png", in: report, created: minutes(30))
        try file("charts/costs.png", in: report, created: minutes(31))
        try file("charts/make_charts.py", in: report, created: minutes(25))
        try file("data/q3.csv", in: report, created: minutes(15))
        try session("q3", in: report, from: t0, to: minutes(60), reply: "The [report](report.md) is ready.")
        _ = try indexer.run()

        let organization = try organization()
        let work = try #require(organization.work(containing: report.path + "/report.md"))
        let kinds = Dictionary(uniqueKeysWithValues: try observed().map { (($0.path as NSString).lastPathComponent, $0.kind) })
        #expect(kinds["style.css"] == .changed && kinds["report.md"] == .appeared && kinds.count == 7)
        let entries = [Listing.Entry.work(work)] + organization.candidates.map(Listing.Entry.candidate)
        // Handed over first; then what a person opens, newest first; then what a program reads.
        #expect(Listing.ordered(entries).map { ($0.path as NSString).lastPathComponent }
                == ["report.md", "report.pdf", "costs.png", "revenue.png", "make_charts.py", "style.css", "q3.csv"])
    }

    @Test func aSlideDeckWithItsExportedSlides() throws {
        let deck = try folder("Projects/board-deck")
        try file("deck.pptx", in: deck, created: minutes(40))
        try file("notes.md", in: deck, created: minutes(20))
        for n in 1...20 { try file("slides/slide-\(n).png", in: deck, created: minutes(30 + Double(n) / 10)) }
        try session("deck", in: deck, from: t0, to: minutes(45), reply: "The [deck](deck.pptx).")
        _ = try indexer.run()

        let organization = try organization()
        let work = try #require(organization.work(containing: deck.path + "/deck.pptx"))
        let rows = Listing.rows([.work(work)] + organization.candidates.map(Listing.Entry.candidate))
        guard rows.count == 3, case .entry(.work) = rows[0], case .folded(_, .image, let slides) = rows[1], case .entry(.candidate(let notes)) = rows[2]
        else { Issue.record("expected the deck, the folded slides, then the notes: \(rows)"); return }
        #expect(slides.count == 20 && notes.name == "notes.md")
    }

    @Test func aDataAnalysisWithCSVFiguresAndANotebook() throws {
        let analysis = try folder("Projects/churn")
        try file("data/raw.csv", in: analysis, created: minutes(-1000), modified: minutes(12))
        try file("data/clean.csv", in: analysis, created: minutes(14))
        try file("analysis.ipynb", in: analysis, created: minutes(5), modified: minutes(55))
        for n in 1...4 { try file("figures/fig\(n).png", in: analysis, created: minutes(40 + Double(n))) }
        try session("churn", in: analysis, from: t0, to: minutes(60), reply: "Open the [notebook](analysis.ipynb).")
        _ = try indexer.run()

        let organization = try organization()
        let work = try #require(organization.work(containing: analysis.path + "/analysis.ipynb"))
        #expect(organization.observations(of: work).map(\.kind) == [.appeared])
        #expect(organization.candidate(analysis.path + "/data/raw.csv")?.latest.kind == .changed)
        #expect(organization.candidate(analysis.path + "/data/clean.csv")?.latest.kind == .appeared)
        let order = Listing.ordered([.work(work)] + organization.candidates.map(Listing.Entry.candidate))
        #expect(order.map { ($0.path as NSString).lastPathComponent }
                == ["analysis.ipynb", "fig4.png", "fig3.png", "fig2.png", "fig1.png", "clean.csv", "raw.csv"])
    }

    @Test func aCodeChangeInAGitRepository() throws {
        let repo = try folder("Projects/app")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try file(".git/index", in: repo, created: minutes(-500), modified: minutes(20))
        try file("Package.swift", in: repo, created: minutes(-500))
        try file("Sources/App/App.swift", in: repo, created: minutes(-500), modified: minutes(15))
        try file("Tests/AppTests/AppTests.swift", in: repo, created: minutes(16))
        try file(".build/debug/App", in: repo, created: minutes(17))
        try file("node_modules/left-pad/index.js", in: repo, created: minutes(17))
        try file("dist/bundle.js", in: repo, created: minutes(17))
        try file("Sources/App/__pycache__/x.pyc", in: repo, created: minutes(17))
        // A linked folder is not followed: its files are not the workspace's.
        let elsewhere = try folder("Elsewhere")
        try file("linked.txt", in: elsewhere, created: minutes(18))
        try FileManager.default.createSymbolicLink(at: repo.appendingPathComponent("Linked"), withDestinationURL: elsewhere)
        // The agent worked in a folder inside the repository: the repository is the workspace.
        try session("code", in: repo.appendingPathComponent("Sources"), from: t0, to: minutes(30), reply: "Done; see `Sources/App/App.swift:3`.")
        _ = try indexer.run()

        let observed = try observed()
        #expect(Set(observed.map(\.path)) == [repo.path + "/Sources/App/App.swift", repo.path + "/Tests/AppTests/AppTests.swift"])
        #expect(observed.allSatisfy { $0.workspace == repo.path && $0.repository == repo.path && $0.checkout == repo.path })
        let candidate = try #require(try organization().candidate(repo.path + "/Sources/App/App.swift"))
        #expect(candidate.latest.kind == .changed && candidate.inRepository && candidate.project == repo.path)
    }

    // MARK: rules

    @Test func readingTheLogAgainFindsTheSameObservations() throws {
        let work = try folder("Projects/again")
        try file("a.md", in: work, created: minutes(10))
        try file("b.png", in: work, created: minutes(-100), modified: minutes(20))
        let log = try session("again", in: work, from: t0, to: minutes(30), reply: "Done.")
        _ = try indexer.run()
        let first = try observed()
        #expect(first.count == 2)

        // Written again after the session: its new dates are outside the span, and the first
        // sight stands.
        try file("a.md", in: work, created: minutes(10), modified: minutes(500), text: "edited later")
        try FileManager.default.setAttributes([.modificationDate: minutes(31)], ofItemAtPath: log)
        #expect(try indexer.run().logsRead == 1)
        #expect(try observed() == first)
        let reopened = Indexer(registry: try Registry(path: indexer.registry.path), store: indexer.store, sources: indexer.sources)
        #expect(try reopened.registry.observations() == first)
    }

    @Test func aLaterSessionEditingAFileAddsItsOwnObservation() throws {
        let work = try folder("Projects/notes")
        let notes = try file("notes.md", in: work, created: minutes(10))
        try session("first", in: work, from: t0, to: minutes(60), reply: "Started the notes.", title: "First")
        _ = try indexer.run()
        try file("notes.md", in: work, created: minutes(10), modified: minutes(330), text: "revised")
        try session("second", in: work, from: minutes(300), to: minutes(360), reply: "Revised the notes.", title: "Second")
        _ = try indexer.run()

        let candidate = try #require(try organization().candidate(notes))
        #expect(candidate.observations.map(\.sessionTitle) == ["Second", "First"])
        #expect(candidate.observations.map(\.kind) == [.changed, .appeared])
        // The first session's record is as it was first seen, never rewritten.
        #expect(candidate.observations[1].modifiedAt == minutes(10))
    }

    @Test func twoOverlappingSessionsBothListAFile() throws {
        let work = try folder("Projects/mix")
        let both = try file("a.wav", in: work, created: minutes(90))
        try file("b.wav", in: work, created: minutes(30))
        try file("c.wav", in: work, created: minutes(150))
        try session("one", in: work, from: t0, to: minutes(120), reply: "Mixed.", title: "One")
        try session("two", in: work, from: minutes(60), to: minutes(180), reply: "Mastered.", title: "Two")
        _ = try indexer.run()

        let organization = try organization()
        #expect(organization.candidate(both)?.observations.compactMap(\.sessionTitle).sorted() == ["One", "Two"])
        #expect(organization.candidate(work.path + "/b.wav")?.observations.compactMap(\.sessionTitle) == ["One"])
        #expect(organization.candidate(work.path + "/c.wav")?.observations.compactMap(\.sessionTitle) == ["Two"])
    }

    @Test func theHomeFolderAndSystemFoldersAreNotWalked() throws {
        try file("Desktop/today.png", in: home, created: minutes(10))
        try file("loose.txt", in: home, created: minutes(11))
        try session("home", in: home, from: t0, to: minutes(30), reply: "Done.")
        _ = try indexer.run()
        #expect(try observed().isEmpty)

        for skipped in ["/", "/Users", "/var", "/tmp", "/private", "/Applications", "/System/Library", "/usr/local/src",
                        "/Library/Caches", home.path, home.path + "/Library/Mobile Documents", NSHomeDirectory()] {
            #expect(Workspace.isSkipped(skipped, home: home.path), "\(skipped)")
        }
        for walked in [home.path + "/Projects/x", "/tmp/x", "/var/folders/ab/T/x", "/opt/project"] {
            #expect(!Workspace.isSkipped(walked, home: home.path), "\(walked)")
        }
    }

    @Test func aWalkStopsAtItsBoundAndSaysSoOnEveryRun() throws {
        let work = try folder("Projects/crowd")
        for n in 0..<100 { try file(String(format: "f%03d.txt", n), in: work, created: minutes(10)) }
        try session("crowd", in: work, from: t0, to: minutes(30), reply: "Done.")
        indexer.walkLimit = 40
        let report = try indexer.run()
        let problems = try #require(report.sources[.claudeCode]?.workspaceProblems)
        #expect(problems == ["\(work.path): stopped after 40 entries"])
        #expect(report.sources[.claudeCode]?.hasProblems == true && report.sources[.claudeCode]?.isIncomplete == false)
        #expect(try observed().count == 40)
        // Reported again by a run that walks nothing: the observations are still incomplete.
        #expect(try indexer.run().sources[.claudeCode]?.workspaceProblems == problems)
    }

    @Test func discoveryReadsNoBytes() throws {
        let work = try folder("Projects/media")
        let files = try (0..<4).map { try file("clip-\($0).mov", in: work, created: minutes(10 + Double($0)), text: "frames \($0)") }
        let locked = try file("locked.wav", in: work, created: minutes(15))
        let large = work.appendingPathComponent("render.mp4")
        #expect(FileManager.default.createFile(atPath: large.path, contents: nil))
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 742 << 20)
        try handle.close()
        try Self.date(large, created: minutes(20), modified: minutes(20))
        #expect(mkfifo(work.appendingPathComponent("pipe").path, 0o600) == 0)
        try session("media", in: work, from: t0, to: minutes(30), reply: "Rendered.")

        // A read would move each file's access time, set before its modification time, to now.
        let accessed = minutes(-60)
        for path in files + [large.path] {
            var times = [timespec(tv_sec: Int(accessed.timeIntervalSince1970), tv_nsec: 0), timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT))]
            #expect(utimensat(AT_FDCWD, path, &times, 0) == 0)
        }
        #expect(chmod(locked, 0) == 0)
        defer { chmod(locked, 0o644) }
        _ = try indexer.run()

        let observed = try observed()
        #expect(Set(observed.map(\.path)) == Set(files + [locked, large.path]))
        #expect(observed.first { $0.path == large.path }?.size == 742 << 20)
        for path in files + [large.path] {
            var info = Darwin.stat()
            #expect(lstat(path, &info) == 0)
            #expect(info.st_atimespec.tv_sec == Int(accessed.timeIntervalSince1970), "\(path) was read")
        }
        // Nothing was captured or saved: observations carry no hash.
        let saved = (try? FileManager.default.contentsOfDirectory(atPath: indexer.store.objects.path)) ?? []
        #expect(saved.isEmpty)
    }

    @Test func aHandedOverFileKeepsItsDeliveryWithItsObservationBeside() throws {
        let folder = try folder("Projects/brief")
        let brief = try file("brief.md", in: folder, created: minutes(20))
        let log = try session("brief", in: folder, from: t0, to: minutes(30), reply: "The [brief](brief.md).", title: "Brief")
        _ = try indexer.run()

        let artifact = try #require(try indexer.registry.artifacts().first { $0.path == brief })
        #expect(artifact.deliveries.count == 1 && artifact.latest.capture?.sha256 != nil)
        let organization = try organization()
        let work = try #require(organization.work(containing: brief))
        #expect(organization.observations(of: work).map(\.logPath) == [log])
        #expect(organization.observations(of: work).first?.kind == .appeared)
        #expect(organization.candidate(brief) == nil && organization.candidates.isEmpty)
    }

    @Test func correctionsAreAppendedAndUndoneWithoutTouchingObservations() throws {
        let work = try folder("Projects/episode")
        let delivered = try file("ep01.mp4", in: work, created: minutes(50))
        let voice = try file("voice/ep01.wav", in: work, created: minutes(70))
        let cover = try file("cover.png", in: work, created: minutes(40))
        let one = try session("one", in: work, from: t0, to: minutes(90), reply: "The [episode](ep01.mp4).", title: "One")
        let two = try session("two", in: work, from: minutes(60), to: minutes(120), reply: "Voiced it.", title: "Two")
        _ = try indexer.run()
        let rows = try observed()
        let registry = indexer.registry

        try registry.correct(.notFromSession, subject: voice, target: one, at: minutes(200))
        #expect(try organization().candidate(voice)?.observations.map(\.logPath) == [two])
        #expect(try organization().detachments(of: voice).map(\.target) == [one])
        try registry.correct(.notFromSession, subject: voice, target: two, at: minutes(201))
        #expect(try organization().candidate(voice) == nil)
        // Saying it again replaces it: one decision per session.
        try registry.correct(.notFromSession, subject: voice, target: two, at: minutes(202))
        #expect(try registry.corrections().filter { $0.kind == .notFromSession }.count == 2)

        try registry.correct(.related, subject: cover, target: delivered, at: minutes(203))
        var organization = try organization()
        let episode = try #require(organization.work(containing: delivered))
        #expect(organization.related(to: episode).map(\.path) == [cover])
        // Related, never one of its versions.
        #expect(episode.files.map(\.path) == [delivered] && episode.deliveries.count == 1)
        #expect(organization.relations(of: cover).count == 1)

        try registry.undo(try registry.corrections().filter { $0.kind == .notFromSession && $0.target == two }.map(\.id))
        organization = try self.organization()
        #expect(organization.candidate(voice)?.observations.map(\.logPath) == [two])
        try registry.undoAllCorrections()
        organization = try self.organization()
        #expect(organization.candidate(voice)?.observations.count == 2 && organization.related(to: episode).isEmpty)
        // Corrections never edit what was observed.
        #expect(try observed() == rows)
    }

    // MARK: the span and the workspace

    @Test func theSpanRunsFromTheFirstRecordToTheLastReply() {
        func log(_ times: [Date?], cwds: [String?] = []) -> SessionLog {
            SessionLog(session: SessionInfo(provider: .codex, id: "s", cwd: "/private/var/w", logPath: "/l"),
                       turns: times.enumerated().map { i, at in
                           Turn(request: nil, parts: [ReplyPart(text: "r", line: i + 1, at: at, cwd: i < cwds.count ? cwds[i] : nil)])
                       },
                       unknownRecordTypes: [:], malformedLines: 0)
        }
        let replies = log([minutes(20), minutes(50)])
        #expect(replies.span(logCreated: t0, logModified: minutes(900), grace: 60) == DateInterval(start: minutes(-1), end: minutes(51)))
        // A log copied later was created after its records: its first reply bounds the start.
        #expect(replies.span(logCreated: minutes(5000), logModified: minutes(5000), grace: 0) == DateInterval(start: minutes(20), end: minutes(50)))
        // No reply: the log's last write ends it.
        #expect(log([]).span(logCreated: t0, logModified: minutes(40), grace: 0) == DateInterval(start: t0, end: minutes(40)))
        #expect(log([nil]).span(logCreated: nil, logModified: nil, grace: 60) == nil)
        // Where the records say it worked, in one spelling, each once.
        #expect(log([nil, nil, nil], cwds: ["/var/w", "/private/var/w/sub", nil]).workingFolders == ["/var/w", "/var/w/sub"])
    }

    @Test func aWorkspaceIsTheCheckoutHoldingTheFolder() throws {
        let repo = try folder("Projects/repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let inner = try folder("Projects/repo/Sources/deep")
        let plain = try folder("Projects/plain/sub")
        #expect(Workspace.root(of: inner.path) == repo.path)
        #expect(Workspace.root(of: plain.path) == plain.path)
        #expect(Workspace.root(of: home.path + "/Projects/gone") == nil)
    }
}
