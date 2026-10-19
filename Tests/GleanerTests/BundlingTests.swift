import AppKit
import GleanerUI
import Testing
@testable import Gleaner
@testable import GleanerCore

/// The library window's model with folders handed over (SPEC §5.4): a folder's files listed where
/// works are, folded when they crowd their folder, found by name, read on the person's action, and
/// corrected as any work; and what the window says of them.
@MainActor @Suite struct BundlingTests {
    let root: URL
    let film: URL
    let indexer: Indexer
    /// Twenty minutes ago: the reply, at `minutes(60)`, comes after every file is written.
    let t0 = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 20 * 60).rounded(.down))

    /// A film's folder handed over with thirty frames, a cut and its edit list, beside a brief and
    /// fourteen notes the reply named one by one.
    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("gleaner-bundling-\(UUID().uuidString)")
        film = root.appendingPathComponent("home/film")
        try fm.createDirectory(at: root.appendingPathComponent("claude/film"), withIntermediateDirectories: true)
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("handoff")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
        indexer.home = root.appendingPathComponent("home").path

        for n in 0..<30 { try file(String(format: "out/frames/frame-%02d.png", n), text: "frame \(n)") }
        try file("out/cut.mp4", text: "cut")
        try file("out/edl.json", text: "{}")
        try file("brief.md", text: "brief")
        let notes = (0..<14).map { String(format: "notes/n-%02d.md", $0) }
        for note in notes { try file(note, text: note) }
        try session(reply: "The [brief](brief.md), the [film](out/) and " + notes.map { "[\($0)](\($0))" }.joined(separator: ", "))
        _ = try indexer.run()
    }

    func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    func file(_ relative: String, text: String) throws {
        let url = film.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.creationDate: minutes(10), .modificationDate: minutes(10)], ofItemAtPath: url.path)
    }

    /// The film's session: asked at the start, answered at `minutes(60)`, then each of `more`.
    func session(reply: String, more: [(asked: Double, replied: Double, reply: String)] = []) throws {
        func record(_ object: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) }
        let stamp = { (m: Double) in self.minutes(m).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
        var lines: [String] = []
        for turn in [(asked: 0.0, replied: 60.0, reply: reply)] + more {
            lines.append(try record(["type": "user", "sessionId": "film", "cwd": film.path, "timestamp": stamp(turn.asked),
                                     "origin": ["kind": "human"], "message": ["role": "user", "content": "Cut the trailer and export its frames"]]))
            lines.append(try record(["type": "assistant", "sessionId": "film", "cwd": film.path, "timestamp": stamp(turn.replied),
                                     "message": ["role": "assistant", "model": "m", "content": [["type": "text", "text": turn.reply]]]]))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: root.appendingPathComponent("claude/film/film.jsonl"), atomically: false, encoding: .utf8)
    }

    func work(_ model: LibraryModel, _ name: String) throws -> Work {
        try #require(model.organization.works.first { $0.name == name })
    }

    func dropped(_ provider: NSItemProvider?) async throws -> String {
        let provider = try #require(provider)
        let type = try #require(provider.registeredTypeIdentifiers.first)
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                continuation.resume(with: Result {
                    guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                    return try String(contentsOf: url, encoding: .utf8)
                })
            }
        }
    }

    // MARK: The outline

    @Test func theOutlineFoldsWhatNoReplyNamedWhenItCrowdsAFolder() throws {
        let model = LibraryModel(indexer: indexer)
        let project = try #require(model.organization.project(try work(model, "brief.md").project))
        model.place = .project(project.key)
        let folders = Dictionary(grouping: model.results) { model.outlineFolder($0.work, in: project) }
        #expect(Set(folders.keys) == ["", "notes", "out", "out/frames"])

        // Thirty frames handed over in the folder: one row, closed until opened or chosen.
        let frames = model.outlineItems(try #require(folders["out/frames"]))
        guard frames.count == 1, case .folded(let key, .image, let results) = frames[0] else {
            Issue.record("expected the frames folded: \(frames.map(\.id))"); return
        }
        #expect(results.count == 30)
        #expect(!model.isUnfolded(key, results))
        model.selection = results[3].work.id
        #expect(model.isUnfolded(key, results))
        model.unfolded[key] = false
        #expect(!model.isUnfolded(key, results))

        // Fourteen notes the reply named one by one never fold.
        let notes = model.outlineItems(try #require(folders["notes"]))
        #expect(notes.count == 14 && notes.allSatisfy { if case .work = $0 { true } else { false } })
        // What a person opens before what a program reads; one reply's files share its time, and
        // are then in name order. The folder itself is listed where it is, beside the brief.
        #expect(model.outlineItems(try #require(folders["out"])).map(\.id) == [film.path + "/out/cut.mp4", film.path + "/out/edl.json"])
        #expect(model.outlineItems(try #require(folders[""])).map(\.id) == [film.path + "/brief.md", film.path + "/out"])
    }

    @Test func searchFindsAFileHandedOverInAFolderByItsName() throws {
        let model = LibraryModel(indexer: indexer)
        model.query = "frame-07"
        #expect(model.results.map(\.work.name) == ["frame-07.png"])
        // By its folder; the request asked for frames too, so the word alone finds what the reply named.
        model.query = "out/frames"
        #expect(model.results.count == 30)
        // The request's words find what the reply named, not each file in the folder.
        model.query = "trailer"
        #expect(Set(model.results.map(\.work.name)) == Set(["out", "brief.md"] + (0..<14).map { String(format: "n-%02d.md", $0) }))
    }

    // MARK: Reading on the person's action

    @Test func aListedFileIsReadWhenChosenAndNamesTheFolderItCameIn() async throws {
        let model = LibraryModel(indexer: indexer)
        let frame = try work(model, "frame-03.png")
        let member = try #require(frame.latest.latest.member)
        #expect(frame.latest.latest.capture?.provenance == .listed)
        #expect(model.folderDelivery(member)?.path == film.path + "/out")
        // A row hands over the file read at the drop: nothing to verify before.
        #expect(model.rowHandoff(frame.latest, frame.latest.latest) == .unread)
        #expect(model.rowStatus(try #require(model.result(for: frame))).mark == nil)

        // Chosen, it is checked as any file is, which is Gleaner's first read of it: within the
        // live window of a reply after its last write, at delivery.
        model.selection = frame.id
        await model.observe(frame.latest)
        let read = try #require(model.selected).work.latest.latest
        #expect(read.capture?.provenance == .atDelivery && read.sha256 != nil)
        let handoff = try #require(model.selectedHandoff)
        #expect(handoff.plan == .ready(sha: read.sha256!, from: .original, firstSeen: nil))
    }

    @Test func aListedRowHandsOverTheFileAsReadAtTheDropAndOnlyWhileItIsAsListed() async throws {
        let model = LibraryModel(indexer: indexer)
        let frame = try work(model, "frame-05.png")
        #expect(try await dropped(model.dragItem(frame.latest, frame.latest.latest)) == "frame 5")
        let member = try #require(frame.latest.latest.member)
        #expect(try indexer.registry.sha256(of: member, path: frame.latest.path) != nil)

        // Written since it was listed: not the delivered file, so the drop hands over nothing.
        let other = try work(model, "frame-06.png")
        try Data("frame 6, repainted".utf8).write(to: URL(fileURLWithPath: other.latest.path))
        await #expect(throws: (any Error).self) { try await dropped(model.dragItem(other.latest, other.latest.latest)) }
    }

    // MARK: Versions and corrections

    @Test func aFolderDeliveredAgainGivesEachFileAVersionWithSizeAndDatesCompared() throws {
        try session(reply: "The [film](out/).", more: [(70, 80, "The [film](out/) again.")])
        _ = try indexer.run()
        let model = LibraryModel(indexer: indexer)
        let cut = try work(model, "cut.mp4")
        #expect(cut.deliveries.map(\.number) == [2, 1])
        // Before Gleaner reads them, only their size and dates are said to match.
        let versions = VersionsSection(work: cut, selected: cut.deliveries[0])
        #expect(versions.sameAs(cut.deliveries[0]) == nil)
        #expect(versions.sameSizeAndDates(cut.deliveries[0])?.id == cut.deliveries[1].id)
        #expect(Wording.sameSizeAndDates(cut.deliveries[1], named: false) == "Same size and dates as 1")
    }

    @Test func aFileHandedOverInAFolderMovesAndComesBackAsAnyWork() async throws {
        let model = LibraryModel(indexer: indexer)
        let cut = try work(model, "cut.mp4")
        let found = cut.project
        await model.move(cut, toNewProject: "Trailer")
        let moved = try work(model, "cut.mp4")
        #expect(moved.project != found && model.organization.projectName(moved.project) == "Trailer")
        await model.join(cut.latest.path, film.path + "/brief.md")
        #expect(try work(model, "cut.mp4").files.count == 2)

        // Relaunched, the decisions stand; undone, it is back where Gleaner found it.
        let again = LibraryModel(indexer: indexer)
        #expect(try work(again, "cut.mp4").files.count == 2)
        await again.undoAllCorrections()
        let back = try work(again, "cut.mp4")
        #expect(back.project == found && back.files.count == 1)
    }

    // MARK: Wording

    @Test func theWindowSaysAFileWasListedWithItsFolderAndNotRead() throws {
        let listed = Capture(sha256: nil, size: 4, modifiedAt: t0, observedAt: t0, savedAt: nil, provenance: .listed, kind: .file)
        #expect(Wording.provenanceShort(listed) == (.dashed, "Listed, not read"))
        #expect(Wording.provenance(listed).1.hasPrefix("Listed with its folder"))
        let member = Membership(folderDelivery: "f", folder: "/p/out", changedSince: false)
        var delivery = Delivery(id: "m", number: 1, path: "/p/out/cut.mp4", deliveredAt: t0, provider: .claudeCode, sessionTitle: nil,
                                request: nil, cwd: "/p", evidence: [], logPath: "/l", capture: listed)
        delivery.member = member
        #expect(Wording.noCopy(delivery, large: false) == "Gleaner listed delivery 1 with its folder and hasn’t read it.")
        #expect(Wording.storage(delivery, hasSaved: false, large: false, now: nil) == (.dashed, "Not saved: listed, not read yet"))
        #expect(Wording.folderName(member) == "out/")
        #expect(Wording.changedSince(member) == nil)
        #expect(Wording.changedSince(Membership(folderDelivery: "f", folder: "/p/out", changedSince: true))?.title == "May have changed since")
        // A row without a check says nothing; one Gleaner couldn't read says why in a few words.
        #expect(Wording.row(delivery, latest: 1, now: nil, changed: false, available: true).mark == nil)
        #expect(Wording.row(delivery, latest: 1, now: .unreadable, changed: false, available: false).mark?.1 == "Unavailable · not read")
    }

    @Test func theWindowSaysWhatListingAFolderFound() {
        #expect(Wording.unpacking(nil).title == "Not listed yet")
        let listed = Unpacking(listedAt: t0, members: 32, notUnpacked: nil, problems: [])
        #expect(Wording.unpacking(listed).title == "32 files" && Wording.unpacking(listed).mark == .done)
        let repo = Unpacking(listedAt: t0, members: 0, notUnpacked: "a Git checkout’s folder", problems: [])
        #expect(Wording.unpacking(repo).title == "Not unpacked" && Wording.unpacking(repo).detail.contains("it is a Git checkout’s folder."))
        let partial = Unpacking(listedAt: t0, members: 40, notUnpacked: nil, problems: ["/p/out: stopped after 40 entries"])
        #expect(Wording.unpacking(partial).mark == .attention && Wording.unpacking(partial).title == "40 files, listed in part")
        var source = Indexer.Report.Source(folder: .listed)
        source.folderProblems = ["/p/out: stopped after 40 entries"]
        #expect(Wording.problems(source) == "1 delivered folder problem")
        #expect(Wording.sourcesLine([.claudeCode: source]) == "Claude Code: read with problems (1 delivered folder problem)")
    }
}
