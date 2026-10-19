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
        let outline = model.outline(of: project)
        #expect(outline.map(\.folder) == ["", "notes", "out", "out/frames"] && outline.map(\.count) == [2, 14, 2, 30])
        let folders = Dictionary(grouping: model.results) { model.outlineFolder($0.work, in: project) }

        // Thirty frames handed over in the folder: one row, closed until opened or chosen.
        let frames = try #require(outline.last).items
        #expect(frames.map(\.id) == model.outlineItems(try #require(folders["out/frames"])).map(\.id))
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

    /// A first read changes what Gleaner recorded of one file's bytes and nothing that lists, orders,
    /// folds or finds works: the list and the outline already made keep their rows, with the work
    /// as read now, and are not made again.
    @Test func aFirstReadPutsTheWorkInPlaceInTheListsAlreadyMade() async throws {
        let model = LibraryModel(indexer: indexer)
        let frame = try work(model, "frame-03.png")
        let project = try #require(model.organization.project(frame.project))
        model.place = .project(project.key)
        let outline = model.outline(of: project)
        let version = model.organizationVersion
        model.selection = frame.id
        await model.observe(frame.latest)

        #expect(model.organizationVersion == version)
        let read = try #require(model.results.first { $0.id == frame.id }).work.latest.latest
        #expect(read.capture?.provenance == .atDelivery && read.sha256 != nil)
        #expect(model.selected?.work.latest.latest.sha256 == read.sha256)
        let after = model.outline(of: project)
        #expect(after.map(\.folder) == outline.map(\.folder) && after.map(\.count) == outline.map(\.count))
        #expect(after.map { $0.items.map(\.id) } == outline.map { $0.items.map(\.id) })
        guard case .folded(_, _, let frames)? = after.last?.items.first else { Issue.record("expected the frames folded"); return }
        #expect(frames.first { $0.id == frame.id }?.work.latest.latest.sha256 == read.sha256)
        #expect(frames.filter { $0.work.latest.latest.sha256 != nil }.count == 1)
        // Its row reads from what is recorded now: the file read, nothing to say.
        #expect(model.rowStatus(try #require(model.result(for: try work(model, "frame-03.png")))).mark == nil)
        #expect(model.rowHandoff(try work(model, "frame-03.png").latest, read) == .bytes(sha: read.sha256!))
    }

    /// A file handed over in a folder delivered twice, read once: both listings are completed, and
    /// the newer is the same as the older, in the lists already made.
    @Test func aFileHandedOverTwiceAndReadOnceIsTheSameAsBefore() async throws {
        try session(reply: "The [film](out/).", more: [(70, 80, "The [film](out/) again.")])
        _ = try indexer.run()
        let model = LibraryModel(indexer: indexer)
        let cut = try work(model, "cut.mp4")
        _ = model.results
        let version = model.organizationVersion
        await model.observe(cut.latest)

        #expect(model.organizationVersion == version)
        let read = try #require(model.results.first { $0.id == cut.id }).work
        #expect(read.deliveries.count == 2 && read.deliveries.allSatisfy { $0.sha256 != nil })
        #expect(VersionsSection(work: read, selected: read.deliveries[0]).sameAs(read.deliveries[0])?.id == read.deliveries[1].id)
    }

    /// A file a reply named that Gleaner first reads later is shown, with its bytes, beside the other
    /// files that reply named.
    @Test func aFirstReadOfANamedFileShowsBesideTheFilesItsReplyNamed() async throws {
        try session(reply: "The [brief](brief.md) and the [film](out/).", more: [(70, 80, "The [brief](brief.md) and the [cast](cast.md).")])
        _ = try indexer.run()
        try file("cast.md", text: "cast")
        let model = LibraryModel(indexer: indexer)
        let brief = try work(model, "brief.md"), cast = try work(model, "cast.md")
        #expect(model.siblings[brief.deliveries[0].id]?.map(\.path) == [cast.latest.path])
        #expect(model.siblings[brief.deliveries[0].id]?.first?.sha256 == nil)

        await model.observe(cast.latest)
        let read = try #require(model.siblings[brief.deliveries[0].id]?.first)
        #expect(read.sha256 != nil && read.capture?.provenance == .firstSeenAfterDelivery)
        #expect(read.sha256 == (try work(model, "cast.md")).latest.latest.sha256)
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
        #expect(Wording.sameSizeAndDates(cut.deliveries[1], as: cut.deliveries[0], named: false) == "Same size and dates as 1")
    }

    /// Size, modification and creation dates are compared as far as both deliveries recorded them,
    /// and "dates" is said only when all of them were.
    @Test func sizeAndDatesAreSaidToMatchOnlyAsFarAsBothRecordedThem() {
        func delivery(_ number: Int, created: Date?, member: Bool, provenance: Provenance) -> Delivery {
            var capture = Capture(sha256: nil, size: 3, modifiedAt: t0, observedAt: t0, savedAt: nil, provenance: provenance, kind: .file)
            capture.createdAt = created
            var delivery = Delivery(id: "\(number)", number: number, path: "/p/out/cut.mp4", deliveredAt: t0.addingTimeInterval(Double(number)),
                                    provider: .claudeCode, sessionTitle: nil, request: nil, cwd: "/p", evidence: [], logPath: "/l",
                                    capture: capture)
            if member { delivery.member = Membership(folderDelivery: "f\(number)", folder: "/p/out") }
            return delivery
        }
        let listed = delivery(2, created: t0, member: true, provenance: .listed)
        func said(_ earlier: Delivery) -> String? {
            let work = Work(files: [Artifact(path: listed.path, deliveries: [listed, earlier])], deliveries: [listed, earlier], project: "/p")
            return VersionsSection(work: work, selected: listed).sameSizeAndDates(listed).map {
                Wording.sameSizeAndDates($0, as: listed, named: false)
            }
        }
        #expect(said(delivery(1, created: t0, member: true, provenance: .listed)) == "Same size and dates as 1")
        // A file a reply named records no creation date: its modification date alone is compared.
        #expect(said(delivery(1, created: nil, member: false, provenance: .atDelivery)) == "Same size and modification date as 1")
        // Created at another time, it is another file with the same size and modification date.
        #expect(said(delivery(1, created: t0.addingTimeInterval(-60), member: true, provenance: .listed)) == nil)
    }

    /// A delivery read long after its reply recorded the file's size and dates as they were then,
    /// which say nothing of the file at that delivery: nothing is said to match it.
    @Test func sizeAndDatesReadLaterAreNotSaidToMatch() throws {
        let late = root.appendingPathComponent("home/late")
        try FileManager.default.createDirectory(at: late.appendingPathComponent("out"), withIntermediateDirectories: true)
        try Data("deck".utf8).write(to: late.appendingPathComponent("out/deck.pdf"))
        func log(_ turns: [(Date, String)]) throws {
            let stamp = { (date: Date) in date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
            let lines = try turns.flatMap { at, reply in
                try [["type": "user", "sessionId": "late", "cwd": late.path, "timestamp": stamp(at.addingTimeInterval(-60)),
                      "origin": ["kind": "human"], "message": ["role": "user", "content": "Make the deck"]],
                     ["type": "assistant", "sessionId": "late", "cwd": late.path, "timestamp": stamp(at),
                      "message": ["role": "assistant", "model": "m", "content": [["type": "text", "text": reply]]]]]
                    .map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
            }
            try FileManager.default.createDirectory(at: root.appendingPathComponent("claude/late"), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: root.appendingPathComponent("claude/late/late.jsonl"), atomically: false, encoding: .utf8)
        }
        // Named two hours ago and read now, first seen after; then the folder, handed over just now, listed.
        let first = (Date().addingTimeInterval(-7200), "The [deck](out/deck.pdf).")
        try log([first])
        _ = try indexer.run()
        try log([first, (Date().addingTimeInterval(5), "Everything is in [out](out/).")])
        _ = try indexer.run()
        let model = LibraryModel(indexer: indexer)
        let deck = try work(model, "deck.pdf")
        #expect(deck.deliveries.map { $0.capture?.provenance } == [.listed, .firstSeenAfterDelivery])
        #expect(VersionsSection(work: deck, selected: deck.deliveries[0]).sameSizeAndDates(deck.deliveries[0]) == nil)
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
        let member = Membership(folderDelivery: "f", folder: "/p/out")
        var delivery = Delivery(id: "m", number: 1, path: "/p/out/cut.mp4", deliveredAt: t0, provider: .claudeCode, sessionTitle: nil,
                                request: nil, cwd: "/p", evidence: [], logPath: "/l", capture: listed)
        delivery.member = member
        #expect(Wording.noCopy(delivery, large: false) == "Gleaner listed delivery 1 with its folder and hasn’t read it.")
        #expect(Wording.storage(delivery, hasSaved: false, large: false, now: nil) == (.dashed, "Not saved: listed, not read yet"))
        #expect(Wording.folderName(member) == "out/")
        // A file that isn't as listed is said to be only that, not changed.
        let artifact = Artifact(path: delivery.path, deliveries: [delivery])
        let now = FileObservation(state: LocatorState(kind: .file, size: 5, sha256: "abc", git: .notInRepo), checkedAt: t0)
        let disk = Wording.onDisk(artifact.onDisk(now, hasSaved: { _ in false }), in: artifact, now: now)
        #expect(disk.title == "Can’t verify" && disk.detail.contains("isn’t as listed") && !disk.detail.contains("has changed"))
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
        #expect(Wording.unpacking(repo).detail.contains("points at the project"))
        // Each reason completes "it is", and only a project's says that handing it over points at the project.
        for reason in ["named by a reply without a time", "a folder directly in the home", "inside a hidden folder", "a link"] {
            let detail = Wording.unpacking(Unpacking(listedAt: t0, members: 0, notUnpacked: reason, problems: [])).detail
            #expect(detail == "Gleaner doesn’t list its files as handed over: it is \(reason).")
        }
        // A repository inside the folder, another project, is named where it is.
        let without = Wording.unpacking(Unpacking(listedAt: t0, members: 3, notUnpacked: nil, problems: [], repositories: ["themes/t"]))
        #expect(without.title == "3 files" && without.mark == .done)
        #expect(without.detail.hasSuffix("It was listed without the Git repository inside it, themes/t, which is another project."))
        let package = Unpacking(listedAt: t0, members: 0, notUnpacked: "a package, which Finder shows as one file", problems: [])
        #expect(!package.pointsAtProject && Wording.unpacking(package).detail.hasSuffix("it is a package, which Finder shows as one file."))
        // Folders gone are counted in one row.
        #expect(Wording.foldersGone(1) == "1 folder gone" && Wording.foldersGone(12) == "12 folders gone")
        let partial = Unpacking(listedAt: t0, members: 40, notUnpacked: nil, problems: ["/p/out: stopped after 40 entries"])
        #expect(Wording.unpacking(partial).mark == .attention && Wording.unpacking(partial).title == "40 files, listed in part")
        var source = Indexer.Report.Source(folder: .listed)
        source.folderProblems = ["/p/out: stopped after 40 entries"]
        #expect(Wording.problems(source) == "1 delivered folder problem")
        #expect(Wording.sourcesLine([.claudeCode: source]) == "Claude Code: read with problems (1 delivered folder problem)")
    }
}
