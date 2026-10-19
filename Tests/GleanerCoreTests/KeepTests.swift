#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Testing
@testable import GleanerCore

/// Keeping a file observed during a session (docs/design/review.md): the person's admission, a
/// work whose one revision is the file as the session's observation recorded it, listed by size
/// and dates and read when the person acts on it, undone back to a candidate.
@Suite struct KeepTests {
    let root: URL
    let home: URL
    let series: URL
    let indexer: Indexer
    /// Twenty minutes ago; a session runs from here to ten minutes from now, so a file written
    /// now falls inside it.
    let t0 = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 20 * 60).rounded(.down))

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("gleaner-keep-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        series = home.appendingPathComponent("Projects/series")
        for folder in [series.appendingPathComponent("covers"), root.appendingPathComponent("claude/series")] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
        indexer.home = home.path
    }

    func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    /// A file in the series, written now; with `at`, created and last written then.
    @discardableResult
    func file(_ relative: String, _ text: String, at m: Double? = nil) throws -> String {
        let url = series.appendingPathComponent(relative)
        try Data(text.utf8).write(to: url)
        if let m {
            try FileManager.default.setAttributes([.creationDate: minutes(m)], ofItemAtPath: url.path)
            try FileManager.default.setAttributes([.modificationDate: minutes(m)], ofItemAtPath: url.path)
        }
        return url.path
    }

    /// A Claude Code session in the series folder, asked at `start` and replying at `end`.
    func session(_ id: String, title: String, from start: Double, to end: Double, reply: String) throws {
        func record(_ object: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) }
        let stamp = { (m: Double) in self.minutes(m).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
        let lines = [
            try record(["type": "user", "sessionId": id, "cwd": series.path, "timestamp": stamp(start), "origin": ["kind": "human"],
                        "message": ["role": "user", "content": "Make the covers"]]),
            try record(["type": "assistant", "sessionId": id, "cwd": series.path, "timestamp": stamp(end),
                        "message": ["role": "assistant", "model": "m", "content": [["type": "text", "text": reply]]]]),
            try record(["type": "custom-title", "sessionId": id, "customTitle": title]),
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: root.appendingPathComponent("claude/series/\(id).jsonl"), atomically: false, encoding: .utf8)
    }

    func organization() throws -> Organization {
        Organization(artifacts: try indexer.registry.artifacts(), observed: Candidate.files(try indexer.registry.observations()),
                     corrections: try indexer.registry.corrections(), units: try indexer.registry.units())
    }

    func sha256(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

    /// Keeps the candidate at `path`, from its latest session, as the window does.
    func keep(_ path: String, at date: Date = Date()) throws {
        let candidate = try #require(try organization().candidate(path))
        try indexer.registry.correct(.kept, subject: path, target: candidate.latest.logPath, at: date)
    }

    @Test func keepingMakesAWorkWhoseOneRevisionIsTheFileAsObserved() throws {
        let cover = try file("covers/ov-4x3.png", "cover", at: 5)
        try session("covers", title: "Covers", from: 0, to: 30, reply: "The covers are done.")
        _ = try indexer.run()
        let observed = try #require(try organization().candidate(cover)?.latest)
        #expect(try organization().works.isEmpty)

        let keptAt = Date()
        try keep(cover, at: keptAt)
        let organization = try organization()
        #expect(organization.candidate(cover) == nil)
        let work = try #require(organization.work(containing: cover))
        let revision = try #require(work.deliveries.first)
        #expect(work.deliveries.count == 1 && revision.number == 1)
        #expect(revision.kept?.observed == .appeared)
        #expect(abs(try #require(revision.kept?.keptAt).timeIntervalSince(keptAt)) < 0.001)
        #expect(revision.sessionTitle == "Covers" && revision.logPath == observed.logPath && revision.provider == .claudeCode)
        // Dated by the write the observation recorded, carrying its size and dates, not read.
        #expect(revision.deliveredAt == observed.modifiedAt)
        #expect(revision.capture?.provenance == .listed && revision.sha256 == nil)
        #expect(revision.capture?.size == observed.size && revision.capture?.createdAt == observed.createdAt)
        #expect(revision.capture?.modifiedAt == observed.modifiedAt)
        // No reply's words: found by its name, folder and project.
        #expect(revision.request == nil && revision.evidence.isEmpty)
        #expect(work.match(["covers"], project: "series") != nil && work.match(["done"], project: "series") == nil)
        // Its observation is beside it, as a delivered file's is.
        #expect(organization.observations(of: work).map(\.logPath) == [observed.logPath])
        #expect(work.project == series.path)

        // Undone, it is a candidate again, and nothing observed changed.
        try indexer.registry.undo(try #require(try indexer.registry.corrections().first).id)
        #expect(try self.organization().work(containing: cover) == nil)
        #expect(try self.organization().candidate(cover)?.latest == observed)
    }

    @Test func aKeptFileIsReadOnThePersonsActionWhileStillAsObserved() throws {
        let fresh = try file("covers/ov-3x4.png", "fresh")
        let older = try file("covers/ov-4x3.png", "older", at: 5)
        let changed = try file("covers/ov-1x1.png", "changed", at: 6)
        try session("covers", title: "Covers", from: 0, to: 30, reply: "The covers are done.")
        _ = try indexer.run()
        for path in [fresh, older, changed] { try keep(path) }
        // Changed since it was observed: not the file kept, so not read as it.
        try file("covers/ov-1x1.png", "changed again", at: 7)

        #expect(try indexer.completeCaptures(of: fresh, now: Date()))
        #expect(try indexer.completeCaptures(of: older, now: Date()))
        #expect(try !indexer.completeCaptures(of: changed, now: Date()))
        let artifacts = Dictionary(uniqueKeysWithValues: try indexer.registry.artifacts().map { ($0.path, $0.latest) })
        // Written moments ago, read within the live window of that write: seen as kept.
        #expect(artifacts[fresh]?.sha256 == sha256("fresh") && artifacts[fresh]?.capture?.provenance == .atDelivery)
        // Written a quarter of an hour before it was read: first seen after.
        #expect(artifacts[older]?.sha256 == sha256("older") && artifacts[older]?.capture?.provenance == .firstSeenAfterDelivery)
        #expect(artifacts[changed]?.sha256 == nil && artifacts[changed]?.capture?.provenance == .listed)
        // A small file's bytes are saved, as any first read saves them.
        #expect(indexer.store.has(sha256("older")) && artifacts[older]?.capture?.savedAt != nil)
        #expect(try indexer.registry.sha256(ofListed: try #require(artifacts[older])) == sha256("older"))

        // Undone and kept again, the read stands: it is of the observation, which never changes.
        let keep = try #require(try indexer.registry.corrections().first { $0.subject == older })
        try indexer.registry.undo(keep.id)
        #expect(try indexer.registry.artifact(at: older) == nil)
        try self.keep(older)
        #expect(try indexer.registry.artifact(at: older)?.latest.sha256 == sha256("older"))
    }

    @Test func addingAnObservedFileToAUnitKeepsIt() throws {
        let cover = try file("covers/ov-4x3.png", "cover", at: 5)
        try session("covers", title: "Covers", from: 0, to: 30, reply: "The covers are done.")
        _ = try indexer.run()
        let unit = try indexer.registry.addUnit(named: "Episode 0", in: series.path, at: Date())
        let candidate = try #require(try organization().candidate(cover))
        try indexer.registry.correct([(.kept, cover, candidate.latest.logPath), (.unit, cover, unit.key)], at: Date())
        let organization = try organization()
        #expect(organization.works(in: unit.key).map(\.id) == [cover])
        #expect(organization.candidates.isEmpty)
    }

    @Test func aKeptFileThatAReplyLaterNamesHasBothRevisions() throws {
        let cover = try file("covers/ov-4x3.png", "cover", at: 5)
        try session("covers", title: "Covers", from: 0, to: 30, reply: "The covers are done.")
        _ = try indexer.run()
        try keep(cover)
        try session("final", title: "Final pass", from: 31, to: 32, reply: "Here is the [cover](covers/ov-4x3.png).")
        _ = try indexer.run()
        let work = try #require(try organization().work(containing: cover))
        #expect(work.deliveries.map(\.number) == [2, 1])
        #expect(work.deliveries.map { $0.kept != nil } == [false, true])
        // The reply's capture read the file, as it was observed: the kept revision is read too.
        #expect(work.deliveries.allSatisfy { $0.sha256 == sha256("cover") })
    }

    @Test func keptFilesSurviveARereadAndARelaunch() throws {
        let cover = try file("covers/ov-4x3.png", "cover", at: 5)
        try session("covers", title: "Covers", from: 0, to: 30, reply: "The covers are done.")
        _ = try indexer.run()
        try keep(cover)
        _ = try indexer.completeCaptures(of: cover, now: Date())
        try indexer.registry.db.execute("PRAGMA user_version = 1")
        let reread = Indexer(registry: try Registry(path: indexer.registry.path), store: indexer.store, sources: indexer.sources)
        reread.home = indexer.home
        _ = try reread.run()
        let organization = Organization(artifacts: try reread.registry.artifacts(), observed: Candidate.files(try reread.registry.observations()),
                                        corrections: try reread.registry.corrections())
        let revision = try #require(organization.work(containing: cover)?.deliveries.first)
        #expect(revision.kept != nil && revision.sha256 == sha256("cover"))
        #expect(organization.candidates.isEmpty)
    }

    @Test func keepingReadsNoBytes() throws {
        let cover = try file("covers/ov-4x3.png", "cover", at: 5)
        try session("covers", title: "Covers", from: 0, to: 30, reply: "The covers are done.")
        _ = try indexer.run()
        // A read would move the access time, set before the modification time, to now.
        let accessed = minutes(-60)
        var times = [timespec(tv_sec: Int(accessed.timeIntervalSince1970), tv_nsec: 0), timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT))]
        #expect(utimensat(AT_FDCWD, cover, &times, 0) == 0)
        try keep(cover)
        _ = try organization()
        _ = try indexer.run()
        var info = SystemStat()
        #expect(lstat(cover, &info) == 0)
        #expect(info.st_atimespec.tv_sec == Int(accessed.timeIntervalSince1970))
        #expect(!indexer.store.has(sha256("cover")))
    }
}
