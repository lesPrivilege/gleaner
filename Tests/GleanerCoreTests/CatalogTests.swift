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

    /// Every file in the project, by path, with its bytes.
    func projectFiles() throws -> [String: Data] {
        let files = (FileManager.default.subpaths(atPath: project.path) ?? [])
            .filter { Locator.stat(project.appendingPathComponent($0).path).kind == .file }
        return try Dictionary(uniqueKeysWithValues: files.map { ($0, try bytes(project.appendingPathComponent($0).path)) })
    }

    /// The library read as the `gleaner` command reads it, with the save limit the test indexed with.
    func catalog() throws -> Catalog {
        var catalog = try Catalog(home: home)
        catalog.saveLimit = 64
        return catalog
    }

    func id(_ name: String, in catalog: Catalog) throws -> String {
        try #require(try catalog.registry.artifacts().first { $0.name == name }?.latest.id)
    }

    // MARK: opening the library

    @Test func readingTheLibraryLeavesItByteIdentical() throws {
        try index(at: delivered.addingTimeInterval(20))
        let before = try bytes(library), files = try projectFiles()

        let catalog = try catalog()
        #expect(try catalog.registry.artifacts().count == 3)
        // SQLite itself refuses a write through it.
        #expect(throws: (any Error).self) { try catalog.registry.db.execute("CREATE TABLE written (a)") }
        let notes = try id("notes.md", in: catalog)
        _ = try catalog.find(["notes"])
        _ = try catalog.show(notes)
        _ = try catalog.read(notes)
        _ = try catalog.resolve(notes)
        _ = try catalog.handoff(notes)
        _ = try catalog.verify(delivery: notes)

        #expect(try bytes(library) == before)
        #expect(try projectFiles() == files)
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

    @Test func eachProblemAnAdapterFindsIsCounted() throws {
        // A field Gleaner doesn't know, and a log whose agent only called a tool.
        try appendLog([#"{"type":"mode","mode":"plan","sessionId":"s1","brandNewField":true}"#])
        let toolCall = #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]},"timestamp":"\#(stamp(delivered))","cwd":"\#(project.path)","sessionId":"s2"}"#
        try ([user("Build it", at: delivered.addingTimeInterval(-60)), toolCall].joined(separator: "\n") + "\n")
            .write(toFile: home.appendingPathComponent(".claude/projects/-Praxis/s2.jsonl").path, atomically: true, encoding: .utf8)
        try index(at: delivered.addingTimeInterval(20))

        #expect(try Catalog(home: home).registry.index().sources["claude-code"] == Catalog.Source(
            state: .readWithProblems, unknownFields: ["mode.brandNewField": 1], logsWithoutFinalReply: 1))
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

    // MARK: identity

    @Test func identityFieldsArePresentAndApart() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog()
        let path = project.appendingPathComponent("out/notes.md").path
        let resolved = try catalog.resolve(try id("notes.md", in: catalog))
        let reference = resolved.reference
        #expect(reference.library == resolved.index.library)
        #expect(reference.delivery == (try id("notes.md", in: catalog)))
        #expect(reference.name == "notes.md")
        #expect(reference.sha256 == Locator.sha256(path))
        #expect(reference.path == path)
        // The log as the adapter found it, through the temporary folder's link.
        let logPath = try #require(try catalog.registry.artifacts().first { $0.name == "notes.md" }?.latest.logPath)
        #expect(logPath.hasSuffix(".claude/projects/-Praxis/s1.jsonl"))
        #expect(reference.evidence == Catalog.LogLine(log: logPath, line: 2))
        #expect(reference.provenance == Catalog.Seen(state: .atDelivery, observedAt: delivered.addingTimeInterval(20)))
        #expect(reference.availability == Catalog.Availability(state: .original))

        // As JSON, each is a field of its own, beside the index it came from.
        let json = try #require(try JSONSerialization.jsonObject(with: Catalog.encoder.encode(resolved)) as? [String: Any])
        let fields = try #require(json["reference"] as? [String: Any])
        #expect(Set(fields.keys) == ["library", "delivery", "name", "sha256", "path", "evidence", "provenance", "availability"])
        #expect((fields["evidence"] as? [String: Any])?["line"] as? Int == 2)
        #expect((fields["provenance"] as? [String: Any])?["state"] as? String == "at_delivery")
        #expect((fields["availability"] as? [String: Any])?["state"] as? String == "original")
        #expect(Set((json["index"] as? [String: Any] ?? [:]).keys) == ["library", "generation", "scanned_at", "sources"])
    }

    @Test func aDeliveryGleanerNeverReadHasANullHash() throws {
        try appendLog([
            user("And the summary", at: delivered.addingTimeInterval(60)),
            assistant("Summary: [summary](out/summary.md)", at: delivered.addingTimeInterval(70)),
        ])
        try index(at: delivered.addingTimeInterval(80))
        let catalog = try catalog()
        let resolved = try catalog.resolve(try id("summary.md", in: catalog))
        #expect(resolved.reference.sha256 == nil)
        #expect(resolved.reference.provenance.state == .neverObserved)
        #expect(resolved.reference.availability == Catalog.Availability(state: .unavailable, reason: .neverSeen))
        let json = try JSONSerialization.jsonObject(with: Catalog.encoder.encode(resolved)) as? [String: Any]
        #expect((json?["reference"] as? [String: Any])?["sha256"] is NSNull)
    }

    @Test func anUnknownDeliveryIsNotFound() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog()
        #expect(throws: Catalog.Failure.notFound("0123456789")) { try catalog.show("0123456789") }
        #expect(throws: Catalog.Failure.notFound("0123456789")) { try catalog.read("0123456789") }
        #expect(Catalog.Failure.notFound("0123456789").exitCode == 1)
    }

    // MARK: find and show

    @Test func findMatchesOneDeliverysWordsAndCountsWhatItLeftOut() throws {
        let later = delivered.addingTimeInterval(3600)
        try write(Data("<svg/>".utf8), to: "out/poster.svg", modified: later.addingTimeInterval(-30))
        try appendLog([
            user("Draft the launch poster " + String(repeating: "with a few more words ", count: 20), at: later.addingTimeInterval(-300)),
            assistant("Poster: [poster](out/poster.svg)", at: later),
        ])
        try index(at: later.addingTimeInterval(20))
        let catalog = try catalog()

        let poster = try catalog.find(["Launch", "praxis"])
        #expect(poster.results.map(\.reference.name) == ["poster.svg"])
        #expect(poster.total == 1 && !poster.truncated)
        #expect(poster.index.generation == 1)
        let hit = try #require(poster.results.first)
        #expect(hit.project == Catalog.Project(name: "Praxis", folder: project.path))
        #expect(hit.kind == .image)
        #expect(hit.deliveredAt == later)
        #expect(hit.request?.hasPrefix("Draft the launch poster with a few more words") == true)
        #expect(hit.request?.hasSuffix("…") == true && (hit.request?.count ?? 0) <= 201)

        // Newest first (files of one reply by path), cut at the limit, with the total.
        let all = try catalog.find([], limit: 2)
        #expect(all.results.map(\.reference.name) == ["poster.svg", "build.dmg"])
        #expect(all.total == 4 && all.truncated)
        #expect(try catalog.find([], kind: .image).results.map(\.reference.name) == ["poster.svg", "frame.png"])
        #expect(try catalog.find([], project: "praxis").total == 4)
        #expect(try catalog.find([], project: project.path).total == 4)
        #expect(try catalog.find([], project: "Courtwork").total == 0)
        #expect(throws: Catalog.Failure.self) { try catalog.find([], limit: 0) }
    }

    @Test func showGivesEveryDeliveryThePlanAndTheEvidence() throws {
        try index(at: delivered.addingTimeInterval(20))
        let second = delivered.addingTimeInterval(3600)
        try write(Data("# Notes\nline two, revised\n".utf8), to: "out/notes.md", modified: second.addingTimeInterval(-30))
        try appendLog([
            user("Revise the notes", at: second.addingTimeInterval(-300)),
            assistant("Revised: [notes](out/notes.md)", at: second),
        ])
        try index(at: second.addingTimeInterval(20))
        let catalog = try catalog()
        let artifact = try #require(try catalog.registry.artifacts().first { $0.name == "notes.md" })

        let shown = try catalog.show(artifact.deliveries[1].id)
        #expect(shown.reference.delivery == artifact.deliveries[1].id)
        #expect(shown.number == 1)
        #expect(shown.deliveredAt == delivered)
        #expect(shown.request == "Write the release notes and render the frame")
        #expect(shown.reply?.contains("[notes](out/notes.md)") == true)
        #expect(shown.project == Catalog.Project(name: "Praxis", folder: project.path))
        #expect(shown.kind == .document)
        #expect(shown.deliveries.map(\.number) == [2, 1])
        #expect(shown.deliveries.map(\.reference.delivery) == artifact.deliveries.map(\.id))
        #expect(shown.deliveries.map(\.deliveredAt) == [second, delivered])
        // The file on disk is delivery 2, so delivery 1 comes from Gleaner's saved copy.
        #expect(shown.onDisk.kind == .file && shown.onDisk.sha256 == artifact.latest.sha256)
        #expect(shown.handoff == Catalog.Plan(action: .ready))
        #expect(shown.reference.availability == Catalog.Availability(state: .savedCopy))
        #expect(shown.deliveries.map(\.reference.availability.state) == [.original, .savedCopy])

        // A version Gleaner kept only the hash of is unavailable once the file changes.
        try write(Data("rebuilt in place".utf8), to: "out/build.dmg", modified: Date())
        let build = try catalog.show(try id("build.dmg", in: catalog))
        #expect(build.handoff == Catalog.Plan(action: .unavailable, currentSha256: build.onDisk.sha256))
        #expect(build.reference.availability == Catalog.Availability(state: .unavailable, reason: .tooLargeToHaveBeenSaved))
    }

    // MARK: read

    @Test func readGivesTheVersionsBytesNeverWhatIsThereInstead() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog()
        let notes = try id("notes.md", in: catalog), build = try id("build.dmg", in: catalog)
        // While the build still holds its bytes, they are read from it.
        let original = try catalog.read(build)
        #expect(original.text == "a build larger than the save limit, so Gleaner keeps only its hash")
        #expect(original.reference.availability.state == .original)

        // An agent rewrites both files.
        try write(Data("# Notes\nrewritten\n".utf8), to: "out/notes.md", modified: Date())
        try write(Data("rebuilt in place".utf8), to: "out/build.dmg", modified: Date())
        let saved = try catalog.read(notes)
        #expect(saved.text == "# Notes\nline two\nline three: café\n")
        #expect(saved.reference.availability.state == .savedCopy)
        #expect(saved.range == 0..<35 && saved.size == 35 && !saved.truncated)

        // Only the build's hash was kept: its bytes are gone, and the new ones are not offered instead.
        let refusal = Catalog.Failure.unavailable(.tooLargeToHaveBeenSaved)
        #expect(throws: refusal) { try catalog.read(build) }
        #expect(refusal.exitCode == 1)
    }

    @Test func readRefusesWhatIsNotText() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog()
        #expect(throws: Catalog.Failure.notText) { try catalog.read(try id("frame.png", in: catalog)) }
        #expect(Catalog.Failure.notText.exitCode == 1)
    }

    @Test func readSelectsLinesOrBytesAndStopsAtTheMost() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog(), notes = try id("notes.md", in: catalog)
        // "# Notes\n" is bytes 0..<8, "line two\n" 8..<17, "line three: café\n" 17..<35 (é is 32 and 33).
        let lines = try catalog.read(notes, span: .lines(2, 3))
        #expect(lines.text == "line two\nline three: café\n")
        #expect(lines.range == 8..<35 && !lines.truncated)
        #expect(try catalog.read(notes, span: .lines(3, 9)).text == "line three: café\n")
        #expect(try catalog.read(notes, span: .lines(4, 9)).range == 35..<35)
        #expect(try catalog.read(notes, span: .bytes(2, 7)).text == "Notes")

        // A cut never splits a character.
        let cut = try catalog.read(notes, span: .lines(3, 3), max: 16)
        #expect(cut.text == "line three: caf")
        #expect(cut.range == 17..<32 && cut.truncated)
        #expect(try catalog.read(notes, span: .bytes(33, 35)).range == 34..<35)

        for wrong in [Catalog.Span.lines(0, 2), .lines(3, 2), .bytes(-1, 2), .bytes(5, 2)] {
            #expect(throws: Catalog.Failure.self) { try catalog.read(notes, span: wrong) }
        }
        #expect(throws: Catalog.Failure.self) { try catalog.read(notes, max: 0) }
        do {
            _ = try catalog.read(notes, span: .lines(0, 2))
        } catch let failure as Catalog.Failure {
            #expect(failure.exitCode == 2)
        }
    }

    // MARK: handoff and verify

    @Test func handoffStagesAVerifiedReadOnlyCopy() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog()
        try write(Data("# Notes\nrewritten\n".utf8), to: "out/notes.md", modified: Date())

        let handed = try catalog.handoff(try id("notes.md", in: catalog))
        #expect(handed.copy.hasPrefix(home.appendingPathComponent("Library/Caches/Gleaner/handoff").path + "/"))
        #expect(Locator.sha256(handed.copy) == handed.reference.sha256)
        #expect(try String(contentsOfFile: handed.copy, encoding: .utf8) == "# Notes\nline two\nline three: café\n")
        #expect((try FileManager.default.attributesOfItem(atPath: handed.copy)[.posixPermissions] as? NSNumber)?.intValue == 0o444)
        // The project's file is as the agent left it.
        #expect(try String(contentsOf: project.appendingPathComponent("out/notes.md"), encoding: .utf8) == "# Notes\nrewritten\n")

        try write(Data("rebuilt in place".utf8), to: "out/build.dmg", modified: Date())
        #expect(throws: Catalog.Failure.unavailable(.tooLargeToHaveBeenSaved)) {
            try catalog.handoff(try id("build.dmg", in: catalog))
        }
    }

    @Test func verifySaysWhichBytesStillHoldTheReference() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog()
        let notes = try id("notes.md", in: catalog)
        let both = try catalog.verify(delivery: notes)
        #expect(both.original && both.savedCopy)

        // A reference kept as JSON, as `resolve` writes it and Copy Reference copies it, is checked later.
        let kept = try Catalog.encoder.encode(try catalog.resolve(notes))
        try write(Data("# Notes\nrewritten\n".utf8), to: "out/notes.md", modified: Date())
        let reference = try Catalog.decoder.decode(Catalog.Resolved.self, from: kept).reference
        let later = try catalog.verify(reference)
        #expect(later.reference == reference)
        #expect(!later.original && later.savedCopy)

        try write(Data("rebuilt in place".utf8), to: "out/build.dmg", modified: Date())
        let neither = try catalog.verify(delivery: try id("build.dmg", in: catalog))
        #expect(!neither.original && !neither.savedCopy)
    }
}
