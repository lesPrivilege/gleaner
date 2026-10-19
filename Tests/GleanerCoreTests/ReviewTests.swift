import CryptoKit
import Foundation
import Testing
@testable import GleanerCore

/// Verdicts and published marks (docs/design/review.md): each bound to the bytes Gleaner hashed
/// when the person made it, kept in a history nothing rewrites, said to have changed by the
/// file's size and dates and, once read, by its hash; the four states kept apart; and the queue
/// drawn from the person's own acts.
@Suite struct ReviewTests {
    let root: URL
    let folder: URL
    let indexer: Indexer
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("gleaner-review-\(UUID().uuidString)")
        folder = root.appendingPathComponent("series")
        for f in [folder.appendingPathComponent("out"), root.appendingPathComponent("claude"), root.appendingPathComponent("codex")] {
            try fm.createDirectory(at: f, withIntermediateDirectories: true)
        }
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
    }

    // MARK: helpers

    func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }

    /// Writes `text` to the file at `relative`; with `modified`, sets its modification date.
    @discardableResult
    func write(_ relative: String, _ text: String, modified: Date? = nil) throws -> String {
        let url = folder.appendingPathComponent(relative)
        try Data(text.utf8).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url.path
    }

    func sha256(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

    /// A file at `path` delivered once, at `hours`.
    func delivered(_ path: String, at hours: Double = 1) -> Artifact {
        let delivery = Delivery(id: path + "#1", number: 1, path: path, deliveredAt: at(hours), replyLine: 1, provider: .claudeCode,
                                sessionTitle: nil, request: nil, cwd: folder.path, evidence: [], logPath: "/logs/s.jsonl",
                                capture: Capture(sha256: "delivered", size: 1, modifiedAt: nil, observedAt: at(hours), savedAt: nil,
                                                 provenance: .atDelivery, kind: .file))
        return Artifact(path: path, deliveries: [delivery])
    }

    func organize(_ artifacts: [Artifact]) throws -> Organization {
        Organization(artifacts: artifacts, corrections: try indexer.registry.corrections(), units: try indexer.registry.units())
    }

    func reviews() throws -> Reviews { Reviews(try indexer.registry.reviews()) }

    /// What the window knows of a file without reading it again: its size and dates, or a read
    /// it made this session while the file is still as it was then.
    func present(_ path: String, read: [String: (String, FileStat)] = [:]) -> Present {
        guard let file = FileStat(path) else { return .absent }
        if let (sha, then) = read[path], then == file { return .read(sha) }
        return .listed(file)
    }

    /// Reads the file now, as selecting it does.
    func select(_ path: String) -> Present {
        guard let sha = Locator.observe(path).sha256 else { return .absent }
        return .read(sha)
    }

    func verdict(_ work: Work, _ now: Present) throws -> Standing { Review.standing(try reviews().verdicts(of: work), now: now) }
    func published(_ work: Work, _ now: Present) throws -> Standing { Review.standing(try reviews().published(of: work), now: now) }

    // MARK: binding

    @Test func aVerdictBindsToTheBytesHashedWhenItIsMade() throws {
        let video = try write("out/ep00.mp4", "take one")
        let approved = try indexer.review(video, as: .approved, note: "  Good pacing  ", at: at(1))
        #expect(approved.sha256 == sha256("take one") && approved.file == FileStat(video) && approved.note == "Good pacing")
        #expect(try indexer.registry.reviews() == [approved])
        // Making it read the bytes, and saved them as a first read does.
        #expect(indexer.store.has(sha256("take one")))
        let work = try #require(try organize([delivered(video)]).work(containing: video))
        #expect(try verdict(work, present(video)) == .current(approved))
        #expect(try verdict(work, select(video)) == .current(approved))
        #expect(try published(work, present(video)) == Standing.none)
    }

    @Test func aRewriteMayHaveChangedTheBytesUntilReadAndARollbackKeepsTheirVerdict() throws {
        let video = try write("out/ep00.mp4", "take one", modified: at(1))
        let work = try #require(try organize([delivered(video)]).work(containing: video))
        let approved = try indexer.review(video, as: .approved, at: at(2))

        // The same path given other bytes: the verdict stays in the history, never carried (A16).
        try write("out/ep00.mp4", "take two", modified: at(3))
        #expect(try verdict(work, present(video)) == .mayHaveChanged(approved))
        #expect(try verdict(work, select(video)) == .changed(approved))
        let changes = try indexer.review(video, as: .changesRequested, note: "Too quiet", at: at(4))
        #expect(try verdict(work, select(video)) == .current(changes))
        #expect(try reviews().history(of: work) == [changes, approved])

        // Rolled back to the bytes approved: their verdict holds again, at whatever revision.
        try write("out/ep00.mp4", "take one", modified: at(5))
        #expect(try verdict(work, present(video)) == .mayHaveChanged(changes))
        #expect(try verdict(work, select(video)) == .current(approved))
    }

    @Test func aChangeOfDatesAloneKeepsTheVerdictOnceTheBytesAreRead() throws {
        let cover = try write("ov-4x3.png", "cover", modified: at(1))
        try FileManager.default.setAttributes([.creationDate: at(1)], ofItemAtPath: cover)
        let work = try #require(try organize([delivered(cover)]).work(containing: cover))
        let approved = try indexer.review(cover, as: .approved, at: at(2))
        // Touched: the dates moved, the bytes didn't (A18). Not cleared, and not assumed either.
        try FileManager.default.setAttributes([.modificationDate: at(3)], ofItemAtPath: cover)
        #expect(try verdict(work, present(cover)) == .mayHaveChanged(approved))
        #expect(try verdict(work, select(cover)) == .current(approved))
        // Touched back, it is as it was when approved.
        try FileManager.default.setAttributes([.modificationDate: at(1)], ofItemAtPath: cover)
        #expect(try verdict(work, present(cover)) == .current(approved))

        // Replaced by a copy keeping the size and dates, the inode tells: it may have changed, and it did.
        let copy = root.appendingPathComponent("copy.png")
        try Data("COVER".utf8).write(to: copy)
        try FileManager.default.setAttributes([.modificationDate: at(1), .creationDate: at(1)], ofItemAtPath: copy.path)
        #expect(rename(copy.path, cover) == 0)
        let now = try #require(FileStat(cover))
        #expect(now.size == approved.file.size && now.modifiedAt == approved.file.modifiedAt && now.createdAt == approved.file.createdAt)
        #expect(now.inode != approved.file.inode)
        #expect(try verdict(work, present(cover)) == .mayHaveChanged(approved))
        #expect(try verdict(work, select(cover)) == .changed(approved))
    }

    @Test func aVerdictIsMadeOnlyOnAReadableFileAsItWasShown() throws {
        let video = try write("out/ep00.mp4", "take one", modified: at(1))
        let shown = try #require(FileStat(video))
        // Replaced between being shown and being judged: the person may not have seen these bytes (A17).
        try write("out/ep00.mp4", "take two", modified: at(2))
        #expect(throws: Review.Failure.changedSinceShown) { try indexer.review(video, as: .approved, shown: shown, at: at(3)) }
        #expect(try indexer.registry.reviews().isEmpty)
        // As shown, it is made.
        #expect(try indexer.review(video, as: .approved, shown: try #require(FileStat(video)), at: at(3)).sha256 == sha256("take two"))

        #expect(throws: Review.Failure.notAFile(.missing)) { try indexer.review(folder.path + "/gone.wav", as: .approved, at: at(4)) }
        #expect(throws: Review.Failure.notAFile(.directory)) { try indexer.review(folder.path + "/out", as: .approved, at: at(4)) }
        let locked = try write("locked.wav", "voice")
        #expect(chmod(locked, 0) == 0)
        defer { chmod(locked, 0o644) }
        // A file that can't be read is said as unreadable, never as gone.
        #expect(throws: Review.Failure.notAFile(.unreadable)) { try indexer.review(locked, as: .approved, at: at(4)) }
    }

    @Test func theHistoryKeepsEveryVerdictAndUndoTakesBackOne() throws {
        let script = try write("script.md", "# Episode 0")
        let work = try #require(try organize([delivered(script)]).work(containing: script))
        let approved = try indexer.review(script, as: .approved, at: at(1))
        let changes = try indexer.review(script, as: .changesRequested, note: "Name the guest", at: at(2))
        let rejected = try indexer.review(script, as: .rejected, at: at(3))
        #expect(try reviews().history(of: work) == [rejected, changes, approved])
        #expect(try verdict(work, present(script)) == .current(rejected))
        try indexer.registry.undoReviews([rejected.id])
        #expect(try reviews().history(of: work) == [changes, approved])
        #expect(try verdict(work, present(script)) == .current(changes))
    }

    @Test func aWorkOfSeveralFilesKeepsAVerdictOnBytesAnyOfItsFilesHad() throws {
        let draft = try write("report-draft.md", "report")
        let final = root.appendingPathComponent("series/report-final.md").path
        let approved = try indexer.review(draft, as: .approved, at: at(1))
        try FileManager.default.moveItem(atPath: draft, toPath: final)
        try indexer.registry.correct(.sameWork, subject: final, target: draft, at: at(2))
        let work = try #require(try organize([delivered(draft, at: 1), delivered(final, at: 2)]).work(containing: final))
        #expect(work.latest.path == final)
        // Renamed, the same bytes: the person joined the two, so the verdict holds once they are read.
        #expect(try verdict(work, select(final)) == .current(approved))
    }

    // MARK: the four states

    @Test func noStateCompletesAnother() throws {
        // Delivered and not reviewed: nothing said of review or publication.
        let delivered = try write("a.mp4", "a")
        // Published, never reviewed.
        let published = try write("b.mp4", "b")
        // Approved, never published.
        let approved = try write("c.mp4", "c")
        // Approved and published, then gone from this Mac.
        let gone = try write("d.mp4", "d")
        // Approved and published, then given other bytes.
        let changed = try write("e.mp4", "e", modified: at(1))
        // Approved on its first bytes, published on its second.
        let later = try write("f.mp4", "f", modified: at(1))

        let mark = try indexer.review(published, as: .published, note: "https://example.com/watch?v=1", at: at(2))
        let yes = try indexer.review(approved, as: .approved, at: at(2))
        let goneYes = try indexer.review(gone, as: .approved, at: at(2))
        let goneMark = try indexer.review(gone, as: .published, at: at(2))
        let changedYes = try indexer.review(changed, as: .approved, at: at(2))
        let changedMark = try indexer.review(changed, as: .published, note: "the channel", at: at(2))
        let laterYes = try indexer.review(later, as: .approved, at: at(2))
        try FileManager.default.removeItem(atPath: gone)
        try write("e.mp4", "e2", modified: at(3))
        try write("f.mp4", "f2", modified: at(3))
        let laterMark = try indexer.review(later, as: .published, at: at(4))

        let paths = [delivered, published, approved, gone, changed, later]
        let organization = try organize(paths.map { self.delivered($0) })
        func states(_ path: String) throws -> (Standing, Standing) {
            let work = try #require(organization.work(containing: path))
            return (try verdict(work, select(path)), try self.published(work, select(path)))
        }
        #expect(try states(delivered) == (.none, .none))
        #expect(try states(published) == (.none, .current(mark)))
        #expect(mark.note == "https://example.com/watch?v=1")
        #expect(try states(approved) == (.current(yes), .none))
        // A reviewed file need not be on this Mac, nor a published one.
        #expect(try states(gone) == (.unavailable(goneYes), .unavailable(goneMark)))
        #expect(try states(changed) == (.changed(changedYes), .changed(changedMark)))
        #expect(try states(later) == (.changed(laterYes), .current(laterMark)))
    }

    // MARK: the queue

    @Test func theQueueHoldsWhatWaitsOnThePersonGroupedByUnit() throws {
        let registry = indexer.registry
        let series = try registry.addUnit(named: "Series", in: folder.path, at: at(0))
        let one = try registry.addUnit(named: "Episode 1", in: folder.path, inside: series.key, at: at(0))
        let two = try registry.addUnit(named: "Episode 2", in: folder.path, inside: series.key, at: at(0))
        let video1 = try write("out/ep01.mp4", "ep01", modified: at(1))
        let cover1 = try write("out/ep01.png", "cover", modified: at(1))
        let video2 = try write("out/ep02.mp4", "ep02", modified: at(1))
        let voice2 = try write("out/ep02.wav", "voice", modified: at(1))
        let logo = try write("logo.png", "logo", modified: at(1))
        let lost = try write("out/ep01.json", "inputs", modified: at(1))
        let loose = try write("notes.md", "notes", modified: at(1))
        let untouched = try write("readme.md", "readme", modified: at(1))
        let renders = folder.appendingPathComponent("renders").path
        try FileManager.default.createDirectory(atPath: renders, withIntermediateDirectories: true)

        try registry.correct([(.unit, video1, one.key), (.unit, cover1, one.key), (.unit, lost, one.key), (.unit, video2, two.key),
                              (.unit, voice2, two.key), (.unit, logo, series.key), (.unit, renders, series.key)], at: at(2))
        _ = try indexer.review(cover1, as: .approved, at: at(3))
        _ = try indexer.review(video2, as: .approved, at: at(3))
        _ = try indexer.review(logo, as: .approved, at: at(3))
        _ = try indexer.review(loose, as: .approved, at: at(3))
        try write("out/ep02.mp4", "ep02 again", modified: at(4))
        try FileManager.default.setAttributes([.modificationDate: at(4)], ofItemAtPath: logo)
        try write("notes.md", "notes again", modified: at(4))
        try FileManager.default.removeItem(atPath: lost)

        var folderArtifact = delivered(renders)
        folderArtifact = Artifact(path: renders, deliveries: folderArtifact.deliveries.map {
            var d = $0
            d.capture = Capture(sha256: nil, size: nil, modifiedAt: nil, observedAt: at(1), savedAt: nil, provenance: .atDelivery, kind: .directory)
            return d
        })
        let organization = try organize([video1, cover1, video2, voice2, logo, lost, loose, untouched].map { delivered($0) } + [folderArtifact])
        // The window read the new episode 2 cut when it was selected.
        let read = [video2: (sha256("ep02 again"), try #require(FileStat(video2)))]
        let queue = organization.toReview(try reviews()) { present($0.latest.path, read: read) }
        let names = queue.map { group in (group.unit.map(organization.unitName) ?? "none", group.works.map(\.name)) }
        #expect(names.map(\.0) == ["Series", "Episode 1", "Episode 2", "none"])
        // The logo was touched since it was approved: it may have changed until it is read.
        #expect(names[0].1 == ["logo.png"])
        // Never reviewed, in a unit: the video, and the inputs file, gone before anyone judged it.
        #expect(names[1].1 == ["ep01.mp4", "ep01.json"])
        // Approved on other bytes, read now; and the voice, never reviewed.
        #expect(names[2].1 == ["ep02.mp4", "ep02.wav"])
        // Outside any unit, only what was reviewed on other bytes; the readme nobody reviewed isn't
        // there, nor the folder, which has no bytes to judge.
        #expect(names[3].1 == ["notes.md"] && queue[3].project == folder.path)
    }

    // MARK: reading

    @Test func nothingIsReadButForAVerdictOrAMark() throws {
        let video = try write("out/ep00.mp4", "take one", modified: at(1))
        let cover = try write("ov-4x3.png", "cover", modified: at(1))
        let accessed = at(0)
        for path in [video, cover] {
            var times = [timespec(tv_sec: Int(accessed.timeIntervalSince1970), tv_nsec: 0), timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT))]
            #expect(utimensat(AT_FDCWD, path, &times, 0) == 0)
        }
        let unit = try indexer.registry.addUnit(named: "Episode 0", in: folder.path, at: at(0))
        try indexer.registry.correct(.unit, subjects: [video, cover], target: unit.key, at: at(1))
        let organization = try organize([delivered(video), delivered(cover)])
        // The queue, each work's states and the unit's page come from sizes and dates.
        #expect(organization.toReview(try reviews()) { present($0.latest.path) }.first?.works.count == 2)
        for work in organization.works(in: unit.key) { _ = try verdict(work, present(work.latest.path)) }
        for path in [video, cover] {
            var info = Darwin.stat()
            #expect(lstat(path, &info) == 0)
            #expect(info.st_atimespec.tv_sec == Int(accessed.timeIntervalSince1970), "\(path) was read")
        }
        // Approving reads it.
        _ = try indexer.review(cover, as: .approved, at: at(2))
        #expect(indexer.store.has(sha256("cover")) && !indexer.store.has(sha256("take one")))
    }

    @Test func verdictsAndMarksSurviveAnotherConnectionAndAReread() throws {
        let video = try write("out/ep00.mp4", "take one")
        let approved = try indexer.review(video, as: .approved, note: "Ship it", at: at(1))
        let mark = try indexer.review(video, as: .published, note: "the channel", at: at(2))
        try indexer.registry.db.execute("PRAGMA user_version = 1")
        let again = Indexer(registry: try Registry(path: indexer.registry.path), store: indexer.store, sources: indexer.sources)
        _ = try again.run()
        #expect(try again.registry.reviews() == [approved, mark])
        // Undoing every correction leaves them: they judge bytes, not how the library is organized.
        try again.registry.undoAllCorrections()
        #expect(try again.registry.reviews().count == 2)
    }
}
