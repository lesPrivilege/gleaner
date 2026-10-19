import Foundation
import GleanerCore
import Testing

/// `gleaner-index`, built beside these tests, run on the command tests' synthetic home: it makes the
/// library the app would, which `gleaner` then reads (docs/design/headless-indexing.md).
extension CommandTests {
    static let indexTool = command.deletingLastPathComponent().appendingPathComponent("gleaner-index")

    func indexTool(_ arguments: [String]) throws -> (status: Int32, output: Data, error: String) {
        try #require(FileManager.default.isExecutableFile(atPath: Self.indexTool.path), "build gleaner-index first")
        let process = Process()
        process.executableURL = Self.indexTool
        process.arguments = arguments
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, out, String(decoding: err, as: UTF8.self))
    }

    /// What a library delivered, apart from ids, which name the log they came from.
    func deliveries(in home: URL) throws -> Set<String> {
        let library = LibraryFolders(home: home).registry
        return Set(try Registry(readingAt: library).artifacts().flatMap(\.deliveries).map {
            "\($0.path) \($0.sha256 ?? "-") \($0.deliveredAt?.timeIntervalSince1970 ?? 0) \($0.provider.rawValue)"
        })
    }

    @Test func theToolMakesTheLibraryTheAppWouldAndGleanerReadsIt() throws {
        // The same logs, indexed in-process as the app sets up its indexer.
        let twin = home.deletingLastPathComponent().appendingPathComponent(home.lastPathComponent + "-twin")
        try FileManager.default.copyItem(at: home, to: twin)
        defer { try? FileManager.default.removeItem(at: twin) }
        let finished = delivered.addingTimeInterval(20)
        _ = try Indexer(folders: LibraryFolders(home: twin)).run(now: { finished })

        let run = try indexTool(["--home", home.path, "--now", finished.formatted(.iso8601)])
        #expect(run.status == 0, "\(run.error)")
        let json = try #require(try JSONSerialization.jsonObject(with: run.output) as? [String: Any])
        let index = try #require(json["index"] as? [String: Any])
        #expect(index["generation"] as? Int == 1)
        #expect(json["logs_read"] as? Int == 1 && json["new_deliveries"] as? Int == 4)

        #expect(try deliveries(in: home) == deliveries(in: twin))
        let found = try answer(["find", "notes"])
        #expect((found["index"] as? [String: Any])?["library"] as? String == index["library"] as? String)
        let paths = (found["results"] as? [[String: Any]] ?? []).compactMap { ($0["reference"] as? [String: Any])?["path"] as? String }
        #expect(paths.contains(project.appendingPathComponent("out/notes.md").path), "\(paths)")
    }

    @Test func theToolRefusesNoHomeAndYourOwn() throws {
        for arguments in [[], ["--home", NSHomeDirectory()], ["--home", home.path, "--now", "yesterday"]] {
            let run = try indexTool(arguments)
            #expect(run.status == 2, "\(arguments)")
            let json = try #require(try JSONSerialization.jsonObject(with: run.output) as? [String: [String: String]], "\(arguments)")
            #expect(json["error"]?["message"].map(run.error.contains) == true, "\(arguments): \(run.error)")
        }
        #expect(!FileManager.default.fileExists(atPath: library))
    }

    @Test func theToolRefusesALibraryALaterGleanerOpened() throws {
        try index()
        try Database(path: library).execute("PRAGMA user_version = \(Registry.extractorVersion + 1)")
        let before = try Data(contentsOf: URL(fileURLWithPath: library))
        let run = try indexTool(["--home", home.path])
        #expect(run.status == 1)
        #expect(run.error.contains(Registry.Failure.newer(version: Registry.extractorVersion + 1).description))
        #expect(try Data(contentsOf: URL(fileURLWithPath: library)) == before)
    }
}
