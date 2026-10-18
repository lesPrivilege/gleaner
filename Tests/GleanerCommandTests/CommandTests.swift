import Foundation
import GleanerCore
import Testing

/// The `gleaner` command built next to these tests, run as an agent's shell runs it, on a library
/// the indexer wrote in a synthetic home (docs/design/query-core.md "Commands"): one JSON object on
/// stdout, and its exit codes. No command writes the library or the project.
@Suite struct CommandTests {
    let home: URL
    let project: URL
    let delivered = Date(timeIntervalSince1970: 1_790_000_000)

    /// Notes (text), a frame (not text) and a long draft, all saved when indexed, and a summary
    /// named in the same reply but never written.
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-command-\(UUID().uuidString)")
        project = home.appendingPathComponent("Projects/Praxis")
        let fm = FileManager.default
        try fm.createDirectory(at: project.appendingPathComponent("out"), withIntermediateDirectories: true)
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)

        let before = delivered.addingTimeInterval(-30)
        try write(Data("# Notes\nline two\nline three: café\n".utf8), to: "out/notes.md", modified: before)
        try write(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D]), to: "out/frame.png", modified: before)
        try write(Data(String(repeating: "draft\n", count: 3000).utf8), to: "out/draft.md", modified: before)
        let lines = [
            user("Write the release notes and render the frame", at: delivered.addingTimeInterval(-600)),
            assistant("Notes: [notes](out/notes.md). Frame: [frame](out/frame.png). Draft: [draft](out/draft.md). Summary: [summary](out/summary.md)", at: delivered),
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: logs.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)
    }

    // MARK: helpers

    /// The `gleaner` built beside this test bundle.
    static let command = Bundle(for: Marker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("gleaner")
    private final class Marker {}

    var support: URL { home.appendingPathComponent("Library/Application Support/Gleaner") }
    var library: String { support.appendingPathComponent("registry.sqlite").path }
    var logs: URL { home.appendingPathComponent(".claude/projects/-Praxis") }

    /// Indexes the home as the app does, then closes the library, as quitting the app would.
    func index() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let indexer = Indexer(
            registry: try Registry(path: library),
            store: ContentStore(objects: support.appendingPathComponent("objects"),
                                staging: home.appendingPathComponent("Library/Caches/Gleaner/handoff")),
            sources: LogSources(claudeProjects: home.appendingPathComponent(".claude/projects"),
                                codexHome: home.appendingPathComponent(".codex")))
        let finished = delivered.addingTimeInterval(20)
        _ = try indexer.run(now: { finished })
    }

    /// Runs `gleaner` on the home, as a shell would: its exit status, what it wrote to stdout, and
    /// what it wrote to stderr.
    func gleaner(_ arguments: [String]) throws -> (status: Int32, output: Data, error: String) {
        try #require(FileManager.default.isExecutableFile(atPath: Self.command.path), "build gleaner first")
        let process = Process()
        process.executableURL = Self.command
        process.arguments = arguments + ["--home", home.path]
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        // A command that hangs is stopped, and fails its test, rather than holding up the suite.
        let deadline = DispatchWorkItem { process.terminate() }
        defer { deadline.cancel() }
        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: deadline)
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, out, String(decoding: err, as: UTF8.self))
    }

    /// The one JSON object a command wrote, after it exited 0.
    func answer(_ arguments: [String]) throws -> [String: Any] {
        let run = try gleaner(arguments)
        #expect(run.status == 0, "\(arguments): \(run.error)")
        return try #require(try JSONSerialization.jsonObject(with: run.output) as? [String: Any])
    }

    /// The one JSON object a command wrote when it failed with `status`: its `error` has a kind and
    /// a message, and the message is on stderr too.
    func refusal(_ arguments: [String], status: Int32) throws -> [String: Any] {
        let run = try gleaner(arguments)
        #expect(run.status == status, "\(arguments): \(run.error)")
        let json = try #require(try JSONSerialization.jsonObject(with: run.output) as? [String: Any], "\(arguments)")
        let error = try #require(json["error"] as? [String: Any], "\(arguments)")
        let message = try #require(error["message"] as? String, "\(arguments)")
        #expect(error["kind"] is String, "\(arguments)")
        #expect(!message.isEmpty && run.error.contains(message), "\(arguments): \(run.error)")
        return json
    }

    func id(_ name: String) throws -> String {
        try #require(try Catalog(home: home).registry.artifacts().first { $0.name == name }?.latest.id)
    }

    func write(_ data: Data, to relative: String, modified: Date) throws {
        let url = project.appendingPathComponent(relative)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
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

    // MARK: answers (exit 0)

    @Test func theAnswerIsTheCatalogsAsOneJSONObject() throws {
        try index()
        let notes = try id("notes.md")
        let resolved = try gleaner(["resolve", notes])
        #expect(resolved.status == 0)
        // Keys sorted and snake_case, dates in ISO 8601, then a newline.
        #expect(resolved.output == (try Catalog.encoder.encode(try Catalog(home: home).resolve(notes))) + Data("\n".utf8))
        #expect(resolved.error.isEmpty)
    }

    @Test func findListsMatchesWithTheirTotal() throws {
        try index()
        let found = try answer(["find", "release", "notes", "--limit", "2"])
        #expect(Set(found.keys) == ["index", "total", "truncated", "results"])
        #expect(found["total"] as? Int == 4 && found["truncated"] as? Bool == true)
        let results = try #require(found["results"] as? [[String: Any]])
        // Files of one reply by path.
        #expect(results.map { ($0["reference"] as? [String: Any])?["name"] as? String } == ["draft.md", "frame.png"])
        let hit = try #require(results.first)
        #expect((hit["reference"] as? [String: Any])?["delivery"] as? String == (try id("draft.md")))
        #expect(hit["project"] as? [String: String] == ["name": "Praxis", "folder": project.path])
        #expect(hit["kind"] as? String == "document")
        #expect(hit["delivered_at"] as? String == ISO8601DateFormatter().string(from: delivered))
        #expect(hit["request"] as? String == "Write the release notes and render the frame")

        let images = try answer(["find", "release", "--kind", "image", "--project", "praxis"])
        #expect((images["results"] as? [[String: Any]])?.map { ($0["reference"] as? [String: Any])?["name"] as? String } == ["frame.png"])
        // No match is an answer too, evidence only within its index.
        let none = try answer(["find", "invoice"])
        #expect(none["total"] as? Int == 0 && (none["results"] as? [Any])?.isEmpty == true)
        #expect((none["index"] as? [String: Any])?["generation"] as? Int == 1)
    }

    @Test func showGivesTheDeliveriesThePlanAndTheEvidence() throws {
        try index()
        let notes = try id("notes.md")
        let shown = try answer(["show", notes])
        #expect((shown["reference"] as? [String: Any])?["delivery"] as? String == notes)
        #expect(shown["number"] as? Int == 1)
        #expect(shown["request"] as? String == "Write the release notes and render the frame")
        #expect((shown["reply"] as? String)?.contains("[notes](out/notes.md)") == true)
        #expect((shown["deliveries"] as? [Any])?.count == 1)
        #expect((shown["handoff"] as? [String: Any])?["action"] as? String == "ready")
        #expect((shown["on_disk"] as? [String: Any])?["kind"] as? String == "file")
    }

    @Test func readGivesTheVersionsTextWithinItsBounds() throws {
        try index()
        let notes = try id("notes.md")
        let lines = try answer(["read", notes, "--lines", "2:3"])
        #expect(lines["text"] as? String == "line two\nline three: café\n")
        #expect(lines["range"] as? [Int] == [8, 35])
        #expect(lines["size"] as? Int == 35 && lines["truncated"] as? Bool == false)
        #expect(try answer(["read", notes, "--bytes", "2:7"])["text"] as? String == "Notes")
        let cut = try answer(["read", notes, "--max", "7"])
        #expect(cut["text"] as? String == "# Notes" && cut["truncated"] as? Bool == true)
        // At most 16 KB unless asked.
        let draft = try answer(["read", try id("draft.md")])
        #expect(draft["range"] as? [Int] == [0, 16 << 10] && draft["size"] as? Int == 18000 && draft["truncated"] as? Bool == true)
    }

    @Test func handoffStagesAVerifiedCopy() throws {
        try index()
        let handed = try answer(["handoff", try id("notes.md")])
        let copy = try #require(handed["copy"] as? String)
        #expect(copy.hasPrefix(home.appendingPathComponent("Library/Caches/Gleaner/handoff").path + "/"))
        #expect(Locator.sha256(copy) == Locator.sha256(project.appendingPathComponent("out/notes.md").path))
        #expect(Locator.sha256(copy) == (handed["reference"] as? [String: Any])?["sha256"] as? String)
    }

    @Test func verifyChecksADeliveryOrAKeptReference() throws {
        try index()
        let notes = try id("notes.md")
        let both = try answer(["verify", notes])
        #expect(both["original"] as? Bool == true && both["saved_copy"] as? Bool == true)

        // A reference kept as `resolve` wrote it, or its reference alone, checked after an agent
        // rewrote the file: where its bytes are is checked again too.
        let resolved = try #require(try JSONSerialization.jsonObject(with: try gleaner(["resolve", notes]).output) as? [String: Any])
        let kept = home.appendingPathComponent("notes-reference.json"), bare = home.appendingPathComponent("notes-bare.json")
        try JSONSerialization.data(withJSONObject: resolved).write(to: kept)
        try JSONSerialization.data(withJSONObject: try #require(resolved["reference"])).write(to: bare)
        try write(Data("# Notes\nrewritten\n".utf8), to: "out/notes.md", modified: Date())
        for file in [kept, bare] {
            let later = try answer(["verify", file.path])
            let reference = later["reference"] as? [String: Any]
            #expect(reference?["delivery"] as? String == notes)
            #expect((reference?["availability"] as? [String: Any])?["state"] as? String == "saved_copy")
            #expect(later["original"] as? Bool == false && later["saved_copy"] as? Bool == true)
        }
    }

    @Test func aKeptReferenceNamesNoFileToRead() throws {
        try index()
        let notes = try id("notes.md")
        // A reference whose hash leads out of Gleaner's store, to a pipe that would block a read for ever.
        let pipe = home.appendingPathComponent("pipe").path
        #expect(mkfifo(pipe, 0o600) == 0)
        var resolved = try #require(try JSONSerialization.jsonObject(with: try gleaner(["resolve", notes]).output) as? [String: Any])
        var reference = try #require(resolved["reference"] as? [String: Any])
        reference["sha256"] = String(repeating: "../", count: 40) + pipe
        resolved["reference"] = reference
        let kept = home.appendingPathComponent("forged-reference.json")
        try JSONSerialization.data(withJSONObject: resolved).write(to: kept)

        // The delivery's own bytes, as the library recorded them, are what is checked.
        let verified = try answer(["verify", kept.path])
        #expect(verified["original"] as? Bool == true && verified["saved_copy"] as? Bool == true)
        #expect((verified["reference"] as? [String: Any])?["sha256"] as? String == Locator.sha256(project.appendingPathComponent("out/notes.md").path))
    }

    // MARK: exit codes

    @Test func noDeliveryOrNoBytesExitsOne() throws {
        try index()
        let summary = try id("summary.md")
        let index = try Catalog(home: home).registry.index()
        let refusals: [([String], Catalog.Failure, kind: String)] = [
            (["show", "0123456789"], .notFound("0123456789"), "not_found"),
            (["read", summary], .unavailable(.neverSeen), "unavailable"),
            (["handoff", summary], .unavailable(.neverSeen), "unavailable"),
            (["read", try id("frame.png")], .notText, "not_text"),
        ]
        for (arguments, failure, kind) in refusals {
            // Still one JSON object: why, beside the index the refusal is evidence of. An id from
            // another library, or one this index hasn't read yet, is not found in it.
            let json = try refusal(arguments, status: 1)
            #expect(Set(json.keys) == ["index", "error"], "\(arguments)")
            let given = json["index"] as? [String: Any]
            #expect(given?["library"] as? String == index.library && given?["generation"] as? Int == 1, "\(arguments)")
            #expect(Set(given?.keys ?? [:].keys) == ["library", "generation", "scanned_at", "sources"], "\(arguments)")
            let error = json["error"] as? [String: Any]
            #expect(error?["kind"] as? String == kind && error?["message"] as? String == failure.description, "\(arguments)")
            #expect(error?["reason"] as? String == (kind == "unavailable" ? "never_seen" : nil), "\(arguments)")
        }

        // verify answers in full, and when neither the original nor a saved copy holds the bytes,
        // says why and exits 1.
        let neither = try refusal(["verify", summary], status: 1)
        #expect(neither["original"] as? Bool == false && neither["saved_copy"] as? Bool == false)
        #expect((neither["index"] as? [String: Any])?["library"] as? String == index.library)
        #expect(neither["error"] as? [String: String] == [
            "kind": "unavailable", "reason": "never_seen", "message": Catalog.Failure.unavailable(.neverSeen).description,
        ])
        // While either does, there is no error.
        #expect(try answer(["verify", try id("notes.md")])["error"] == nil)
    }

    @Test func aFailureOutsideTheCatalogsWordsExitsOneAsFailed() throws {
        try index()
        // Gleaner's caches folder is a file, so no hand-off copy can be written.
        let caches = home.appendingPathComponent("Library/Caches/Gleaner")
        try FileManager.default.createDirectory(at: caches.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: caches)
        let json = try refusal(["handoff", try id("notes.md")], status: 1)
        #expect(Set(json.keys) == ["index", "error"])
        #expect((json["error"] as? [String: Any])?["kind"] as? String == "failed")
    }

    @Test func aWrongUsageExitsTwo() throws {
        try index()
        let notes = try id("notes.md")
        // Refused before the library is open, or once it is, then with its index.
        let wrong: [([String], opened: Bool)] = [
            (["frobnicate"], false),
            (["find"], false),
            (["find", "notes", "--limit", "0"], true),
            (["find", "notes", "--kind", "poem"], false),
            (["read", notes, "--lines", "two"], false),
            (["read", notes, "--lines", "0:2"], true),
            (["read", notes, "--lines", "1:2", "--bytes", "0:3"], false),
            (["read", notes, "--max", "0"], true),
            // A file, but not a reference.
            (["verify", project.appendingPathComponent("out/notes.md").path], false),
        ]
        for (arguments, opened) in wrong {
            let json = try refusal(arguments, status: 2)
            #expect(Set(json.keys) == (opened ? ["index", "error"] : ["error"]), "\(arguments)")
            #expect((json["error"] as? [String: Any])?["kind"] as? String == "usage", "\(arguments)")
        }
    }

    @Test func noLibraryOrAnotherVersionExitsThree() throws {
        // No library was open, so there is no index to give.
        let missing = try refusal(["find", "notes"], status: 3)
        #expect(missing as? [String: [String: String]] == [
            "error": ["kind": "no_library", "message": Catalog.Failure.noLibrary(library).description],
        ])
        #expect(!FileManager.default.fileExists(atPath: library))

        try index()
        try Database(path: library).execute("PRAGMA user_version = \(Registry.extractorVersion - 1)")
        let before = try bytes(library)
        let other = try refusal(["show", "0123456789"], status: 3)
        #expect(other as? [String: [String: String]] == [
            "error": ["kind": "wrong_version", "message": Catalog.Failure.wrongVersion(library, found: Registry.extractorVersion - 1).description],
        ])
        #expect(try bytes(library) == before)
    }

    // MARK: read only

    @Test func noCommandWritesTheLibraryOrTheProject() throws {
        try index()
        let before = try bytes(library), files = try projectFiles()
        let notes = try id("notes.md"), summary = try id("summary.md")
        let kept = home.appendingPathComponent("notes-reference.json")
        try gleaner(["resolve", notes]).output.write(to: kept)
        let commands = [
            ["find", "notes"], ["show", notes], ["read", notes], ["resolve", notes], ["handoff", notes],
            ["verify", notes], ["verify", kept.path],
            ["show", "0123456789"], ["read", summary], ["handoff", summary], ["verify", summary],
            ["read", notes, "--lines", "0:2"], ["frobnicate"],
        ]
        for arguments in commands {
            _ = try gleaner(arguments)
            #expect(try bytes(library) == before, "\(arguments)")
            #expect(try projectFiles() == files, "\(arguments)")
        }
    }
}
