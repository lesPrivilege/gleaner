import Foundation
import Testing
@testable import GleanerCore

/// Spike A's labeling sheet (SPEC §13), from the `gleaner-spike` built next to these tests.
@Suite struct SpikeTests {
    @Test func theSheetSaysWhichCandidatesAreAdmitted() throws {
        let spike = Bundle.module.bundleURL.deletingLastPathComponent().appendingPathComponent("gleaner-spike")
        try #require(FileManager.default.isExecutableFile(atPath: spike.path), "build gleaner-spike first")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-spike-\(UUID().uuidString)")
        let logs = root.appendingPathComponent("claude/-p")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let reply = #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"text","text":"Here is the [report](out/report.md). I changed `App.tsx`."}]},"timestamp":"2026-10-17T00:00:00.000Z","cwd":"/p","sessionId":"s1"}"#
        try (reply + "\n").write(to: logs.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = spike
        process.arguments = ["--claude-root", root.appendingPathComponent("claude").path,
                             "--codex-home", root.appendingPathComponent("codex").path,
                             "--out", root.appendingPathComponent("out").path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let sheet = try String(contentsOf: root.appendingPathComponent("out/candidates.tsv"), encoding: .utf8)
        let rows = sheet.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        let header = try #require(rows.first)
        let admitted = try #require(header.firstIndex(of: "admitted")), path = try #require(header.firstIndex(of: "path"))
        let byPath = Dictionary(uniqueKeysWithValues: rows.dropFirst().map { ($0[path], $0[admitted]) })
        #expect(byPath == ["/p/out/report.md": "yes", "/p/App.tsx": "no"])
    }
}
