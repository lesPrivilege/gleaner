import Foundation
import Testing
@testable import GleanerCore

/// The query core on a synthetic home: the library the app wrote, read by an agent without
/// changing it (docs/design/query-core.md).
@Suite struct CatalogTests {
    let home: URL
    let project: URL
    let delivered = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-catalog-\(UUID().uuidString)")
        project = home.appendingPathComponent("Projects/Praxis")
        let fm = FileManager.default
        try fm.createDirectory(at: project.appendingPathComponent("out"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".claude/projects/-Praxis"), withIntermediateDirectories: true)

        let before = delivered.addingTimeInterval(-30)
        try write(Data("# Notes\nline two\nline three: café\n".utf8), to: "out/notes.md", modified: before)
        try write(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D]), to: "out/frame.png", modified: before)
        try write(Data("a build larger than the save limit, so Gleaner keeps only its hash".utf8), to: "out/build.dmg", modified: before)

        try appendLog([
            user("Write the release notes and render the frame", at: delivered.addingTimeInterval(-600)),
            assistant("Notes: [notes](out/notes.md). Frame: [frame](out/frame.png). Build: [dmg](out/build.dmg)", at: delivered),
        ])
    }

    // MARK: helpers

    var support: URL { home.appendingPathComponent("Library/Application Support/Gleaner") }
    var library: String { support.appendingPathComponent("registry.sqlite").path }
    var log: String { home.appendingPathComponent(".claude/projects/-Praxis/s1.jsonl").path }

    /// Indexes the home as the app does, then closes the library, as quitting the app would.
    @discardableResult
    func index(at date: Date) throws -> Indexer.Report {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let indexer = Indexer(
            registry: try Registry(path: library),
            store: ContentStore(objects: support.appendingPathComponent("objects"),
                                staging: home.appendingPathComponent("Library/Caches/Gleaner/handoff")),
            sources: LogSources(claudeProjects: home.appendingPathComponent(".claude/projects"),
                                codexHome: home.appendingPathComponent(".codex")))
        indexer.saveLimit = 64 // notes.md and frame.png are saved; build.dmg is tracked by hash only
        return try indexer.run(now: { date })
    }

    func write(_ data: Data, to relative: String, modified: Date) throws {
        let url = project.appendingPathComponent(relative)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    func appendLog(_ lines: [String]) throws {
        let existing = (try? String(contentsOfFile: log, encoding: .utf8)) ?? ""
        try (existing + lines.joined(separator: "\n") + "\n").write(toFile: log, atomically: true, encoding: .utf8)
    }

    func stamp(_ date: Date) -> String { date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }

    func user(_ text: String, at date: Date) -> String {
        #"{"type":"user","message":{"role":"user","content":"\#(text)"},"origin":{"kind":"human"},"timestamp":"\#(stamp(date))","cwd":"\#(project.path)","sessionId":"s1"}"#
    }

    func assistant(_ text: String, at date: Date) -> String {
        #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"text","text":"\#(text)"}]},"timestamp":"\#(stamp(date))","cwd":"\#(project.path)","sessionId":"s1"}"#
    }

    func bytes(_ path: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: path)) }

    // MARK: opening the library

    @Test func readingTheLibraryLeavesItByteIdentical() throws {
        try index(at: delivered.addingTimeInterval(20))
        let before = try bytes(library)

        let catalog = try Catalog(home: home)
        #expect(try catalog.registry.artifacts().count == 3)
        #expect(try catalog.registry.index().generation == 1)
        // SQLite itself refuses a write through it.
        #expect(throws: (any Error).self) { try catalog.registry.db.execute("CREATE TABLE written (a)") }

        #expect(try bytes(library) == before)
    }

    @Test func aMissingLibraryIsRefusedAndNotMade() throws {
        #expect(throws: Catalog.Failure.noLibrary(library)) { try Catalog(home: home) }
        #expect(!FileManager.default.fileExists(atPath: library))
        #expect(Catalog.Failure.noLibrary(library).exitCode == 3)
    }

    @Test func aLibraryOfAnotherVersionIsRefusedAndLeftAsItWas() throws {
        try index(at: delivered.addingTimeInterval(20))
        try Database(path: library).execute("PRAGMA user_version = \(Registry.extractorVersion - 1)")
        let before = try bytes(library)

        let refusal = Catalog.Failure.wrongVersion(library, found: Registry.extractorVersion - 1)
        #expect(throws: refusal) { try Catalog(home: home) }
        #expect(refusal.exitCode == 3)
        #expect(refusal.description.contains("Open Gleaner"))
        // No reread was scheduled: nothing was written.
        #expect(try bytes(library) == before)
    }

    // MARK: freshness

    @Test func eachCompletedRunIsRecordedUnderOneLibrary() throws {
        let first = delivered.addingTimeInterval(20)
        try index(at: first)
        let once = try Catalog(home: home).registry.index()
        #expect(UUID(uuidString: once.library) != nil)
        #expect(once.generation == 1)
        #expect(once.scannedAt == first)
        #expect(once.sources["claude-code"] == Catalog.Source(state: .read))
        #expect(once.sources["codex"]?.state == .absent)

        // A malformed line: the log is read with problems, and what it named is incomplete.
        try appendLog(["{not json"])
        let second = first.addingTimeInterval(60)
        try index(at: second)
        let twice = try Catalog(home: home).registry.index()
        #expect(twice.library == once.library)
        #expect(twice.generation == 2)
        #expect(twice.scannedAt == second)
        #expect(twice.sources["claude-code"] == Catalog.Source(state: .readWithProblems, partialLogs: 1))
    }

    @Test func aLibraryNeverScannedSaysSo() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        _ = try Registry(path: library)
        let index = try Catalog(home: home).registry.index()
        #expect(UUID(uuidString: index.library) != nil)
        #expect(index.generation == 0)
        #expect(index.scannedAt == nil)
        #expect(index.sources.isEmpty)
    }
}
