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
        _ = try catalog.verify(notes)

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

    @Test func aLibraryThatCantBeOpenedToReadSaysToOpenGleaner() throws {
        try index(at: delivered.addingTimeInterval(20))
        // Another SQLite client, closing it last, folded the write-ahead log into the library and
        // removed it; or the library was copied without the files beside it.
        try Database(path: library).execute("PRAGMA wal_checkpoint(TRUNCATE)")
        for sidecar in ["-wal", "-shm"] { try FileManager.default.removeItem(atPath: library + sidecar) }
        let before = try bytes(library)

        #expect { try Catalog(home: home) } throws: { error in
            let failure = error as? Catalog.Failure
            return failure?.exitCode == 3 && failure?.description.contains("Open Gleaner") == true
        }
        #expect(try bytes(library) == before)
        // Opening it as Gleaner does makes the log again, and it reads once more.
        _ = try Registry(path: library)
        #expect(try Catalog(home: home).registry.artifacts().count == 3)
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

    @Test func anUpdatedLibraryGivesNoStatusOfARunByAnotherVersion() throws {
        try index(at: delivered.addingTimeInterval(20))
        // As an earlier Gleaner left it: its version, and its last run's status in that version's shape.
        let earlier = try Database(path: library)
        try earlier.execute("PRAGMA user_version = \(Registry.extractorVersion - 1)")
        try earlier.run("UPDATE meta SET value = ? WHERE key = 'sources'", [#"{"claude-code":{"state":"read"}}"#])

        // Gleaner opens it, and will read every log again; until that run ends, the library is read
        // without that status.
        _ = try Registry(path: library)
        let index = try Catalog(home: home).registry.index()
        #expect(index.sources.isEmpty)
        #expect(index.generation == 1 && index.scannedAt == delivered.addingTimeInterval(20))
        try self.index(at: delivered.addingTimeInterval(40))
        #expect(try Catalog(home: home).registry.index().sources["claude-code"] == Catalog.Source(state: .read))
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

    @Test func readTakesTheSavedCopyOverAnOriginalThatCanChangeWhileItIsRead() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog(), notes = try id("notes.md", in: catalog)
        let delivered = try bytes(project.appendingPathComponent("out/notes.md").path)
        // An agent rewrites the file again and again, each write whole: at any moment it may hold
        // the delivered bytes, and stop holding them while they are read.
        let stop = Date().addingTimeInterval(1)
        let writer = Thread {
            var again = false
            while Date() < stop {
                try? (again ? delivered : Data("# Notes\nrewritten\n".utf8)).write(to: project.appendingPathComponent("out/notes.md"), options: .atomic)
                again.toggle()
            }
        }
        writer.start()
        var reads = 0, failed = 0
        while Date() < stop {
            reads += 1
            do { #expect(try catalog.read(notes).text == "# Notes\nline two\nline three: café\n") }
            catch is Catalog.Failure { failed += 1 }
        }
        #expect(failed == 0, "of \(reads) reads")
    }

    @Test func readGivesALargeVersionsTextAcrossThePiecesItIsReadIn() throws {
        // Larger than the 4 MB pieces a version is read in, and tracked by hash only. In the rows,
        // 16 bytes each, one piece ends just after "before the seam\n".
        let seam = 4 << 20, count = 600_000
        var rows = Data(capacity: count * 16)
        for row in 0..<count {
            rows.append(contentsOf: Array((row == seam / 16 - 1 ? "before the seam\n" : row == seam / 16 ? "after the seam.\n" : "filler row \(row % 1000 + 1000)\n").utf8))
        }
        try write(rows, to: "out/rows.csv", modified: delivered.addingTimeInterval(-30))
        // A character split by the seam; a NUL, and a character left unfinished, past the first piece.
        try write(Data(repeating: 0x61, count: seam - 1) + Data("é\nend\n".utf8), to: "out/split.md", modified: delivered.addingTimeInterval(-30))
        try write(Data(repeating: 0x61, count: seam + 5) + Data([0]) + Data("tail\n".utf8), to: "out/nul.md", modified: delivered.addingTimeInterval(-30))
        try write(Data(repeating: 0x61, count: seam + 5) + Data([0xC3]), to: "out/cut.md", modified: delivered.addingTimeInterval(-30))
        try appendLog([
            user("Export the rows", at: delivered.addingTimeInterval(30)),
            assistant("Rows: [rows](out/rows.csv). Split: [split](out/split.md). NUL: [nul](out/nul.md). Cut: [cut](out/cut.md)", at: delivered.addingTimeInterval(40)),
        ])
        try index(at: delivered.addingTimeInterval(60))
        let catalog = try catalog(), table = try id("rows.csv", in: catalog), split = try id("split.md", in: catalog)

        let across = try catalog.read(table, span: .lines(seam / 16, seam / 16 + 1))
        #expect(across.text == "before the seam\nafter the seam.\n")
        #expect(across.range == seam - 16..<seam + 16 && across.size == count * 16 && !across.truncated)
        #expect(try catalog.read(table, span: .bytes(seam - 4, seam + 6)).text == "eam\nafter ")
        #expect(try catalog.read(table, span: .lines(count, count + 4)).text == "filler row \((count - 1) % 1000 + 1000)\n")
        #expect(try catalog.read(table, span: .lines(count + 1, count + 4)).range == count * 16..<count * 16)
        let first = try catalog.read(table)
        #expect(first.range == 0..<16 << 10 && first.truncated && first.text.hasPrefix("filler row 1000\nfiller row 1001\n"))
        let tail = try catalog.read(table, span: .lines(seam / 16 + 1, count), max: 20)
        #expect(tail.text == "after the seam.\nfill" && tail.range == seam..<seam + 20 && tail.truncated)

        // Each end of a cut falls between characters, whichever piece holds them.
        #expect(try catalog.read(split, span: .bytes(seam, seam + 3)).range == seam + 1..<seam + 3)
        #expect(try catalog.read(split, span: .bytes(seam - 2, seam)).text == "a")
        #expect(try catalog.read(split, span: .lines(1, 1), max: seam).text.hasSuffix("aaa"))
        #expect(try catalog.read(split, span: .bytes(seam - 1, seam + 1)).text == "é")
        for name in ["nul.md", "cut.md"] {
            #expect(throws: Catalog.Failure.notText) { try catalog.read(try id(name, in: catalog)) }
        }
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
        #expect(try catalog.read(notes, span: .bytes(33, 33)).range == 34..<34)
        #expect(try catalog.read(notes, max: .max).range == 0..<35)

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
        let both = try catalog.verify(notes)
        #expect(both.original && both.savedCopy)
        #expect(both.reference.availability == Catalog.Availability(state: .original))

        // A reference kept as JSON, as `resolve` writes it and Copy Reference copies it, or its
        // reference alone, is checked later: where its bytes are is checked again too.
        let resolved = try catalog.resolve(notes)
        let answer = try #require(try JSONSerialization.jsonObject(with: Catalog.encoder.encode(resolved)) as? [String: Any])
        // Kept by another build of Gleaner, whose index says what this one doesn't.
        var later = try #require(answer["index"] as? [String: Any])
        later["sources"] = ["claude-code": ["state": "read", "counted_by_a_later_build": 1]]
        let kept = try [answer, try #require(answer["reference"]), answer.merging(["index": later]) { $1 }].map {
            try Catalog.decoder.decode(Catalog.Kept.self, from: JSONSerialization.data(withJSONObject: $0))
        }
        #expect(kept == Array(repeating: Catalog.Kept(library: resolved.index.library, delivery: notes), count: 3))
        try write(Data("# Notes\nrewritten\n".utf8), to: "out/notes.md", modified: Date())
        let rewritten = try catalog.verify(kept[0])
        #expect(rewritten.reference.delivery == notes && rewritten.reference.sha256 == resolved.reference.sha256)
        #expect(!rewritten.original && rewritten.savedCopy)
        #expect(rewritten.reference.availability == Catalog.Availability(state: .savedCopy))

        try write(Data("rebuilt in place".utf8), to: "out/build.dmg", modified: Date())
        let neither = try catalog.verify(try id("build.dmg", in: catalog))
        #expect(!neither.original && !neither.savedCopy)
        #expect(neither.reference.availability == Catalog.Availability(state: .unavailable, reason: .tooLargeToHaveBeenSaved))
    }

    @Test func verifySaysWhereTheBytesAreAsItsHashesFoundThem() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog()
        let notes = try id("notes.md", in: catalog)
        // The saved copy is there, but no longer holds the version's bytes; nor does the file on disk.
        let copy = catalog.store.objectURL(try #require(try catalog.resolve(notes).reference.sha256)).path
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: copy)
        try Data("damaged".utf8).write(to: URL(fileURLWithPath: copy))
        try write(Data("# Notes\nrewritten\n".utf8), to: "out/notes.md", modified: Date())

        let verified = try catalog.verify(notes)
        #expect(!verified.original && !verified.savedCopy)
        #expect(verified.reference.availability == Catalog.Availability(state: .unavailable, reason: .savedCopyMissing))
    }

    @Test func aReferenceFromAnotherLibraryIsNotVerifiedHere() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog()
        // The same logs read into another library give the same delivery ids, but not the same captures.
        let other = UUID().uuidString.lowercased()
        let refusal = Catalog.Failure.otherLibrary(other)
        #expect(throws: refusal) { try catalog.verify(Catalog.Kept(library: other, delivery: try id("notes.md", in: catalog))) }
        #expect(refusal.exitCode == 1)
    }
}
