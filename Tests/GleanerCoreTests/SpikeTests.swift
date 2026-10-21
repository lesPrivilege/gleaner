import Foundation
import Testing
@testable import GleanerCore

/// Spike A's labeling sheet (SPEC §13), from the `gleaner-spike` built next to these tests.
@Suite struct SpikeTests {
    @Test func theSheetSaysWhichCandidatesAreAdmitted() throws {
        let (_, rows) = try sheet()
        let header = try #require(rows.first)
        let admitted = try #require(header.firstIndex(of: "admitted")), path = try #require(header.firstIndex(of: "path"))
        let byPath = Dictionary(uniqueKeysWithValues: rows.dropFirst().map { ($0[path], $0[admitted]) })
        #expect(byPath == ["/p/out/report.md": "yes", "/p/App.tsx": "no"])
    }

    /// `scripts/score-candidates.py` reads the sheet as `gleaner-spike` writes it, once a person labels it.
    @Test func theScorerCountsTheLabeledSheet() throws {
        let (url, rows) = try sheet()
        let header = try #require(rows.first)
        let id = try #require(header.firstIndex(of: "id")), label = try #require(header.firstIndex(of: "label"))
        let path = try #require(header.firstIndex(of: "path"))
        // Both are deliveries: the rule admits the report and rejects App.tsx.
        let labeled = [header] + rows.dropFirst().map { row in var row = row; row[label] = "delivery"; return row }
        try (labeled.map { $0.joined(separator: "\t") }.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)

        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/score-candidates.py")
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", script.path, url.path]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let report = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(report["counts"] as? [String: Int] == ["rows": 2, "tp": 1, "fp": 0, "tn": 0, "fn": 1, "uncertain": 0, "unlabeled": 0])
        #expect(report["rejected_deliveries"] as? [String] == rows.filter { $0[path] == "/p/App.tsx" }.map { $0[id] })
    }

    /// Runs `gleaner-spike` on one Claude Code reply that names a report and a source file: the
    /// sheet it writes, and that sheet's rows split into cells.
    func sheet() throws -> (URL, [[String]]) {
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

        let url = root.appendingPathComponent("out/candidates.tsv")
        let sheet = try String(contentsOf: url, encoding: .utf8)
        return (url, sheet.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) })
    }
}
