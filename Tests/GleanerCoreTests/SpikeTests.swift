import CryptoKit
import Foundation
import Testing
@testable import GleanerCore

/// Spike A's labeling sheet (SPEC §13), from the `gleaner-spike` built next to these tests.
@Suite struct SpikeTests {
    static let reply = "Here is the [report](out/report.md). I changed `App.tsx`."

    @Test func theSheetSaysWhichCandidatesAreAdmitted() throws {
        let sheet = try Spike(Self.reply).run()
        #expect(Dictionary(uniqueKeysWithValues: sheet.rows.map { ($0["path"], $0["admitted"]) })
            == ["/p/out/report.md": "yes", "/p/App.tsx": "no"])
    }

    /// `scripts/score-candidates.py` reads the sheet as `gleaner-spike` writes it, once a person labels it.
    @Test func theScorerCountsTheLabeledSheet() throws {
        let spike = try Spike(Self.reply)
        // Both are deliveries: the rule admits the report and rejects App.tsx.
        let sheet = try spike.run().labeled { _ in "" }
        try sheet.text().write(to: spike.sheet, atomically: true, encoding: .utf8)

        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/score-candidates.py")
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", script.path, spike.sheet.path]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let report = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(report["counts"] as? [String: Int] == ["rows": 2, "tp": 1, "fp": 0, "tn": 0, "fn": 1, "uncertain": 0, "unlabeled": 0])
        #expect(report["rejected_deliveries"] as? [String] == sheet.rows.filter { $0["path"] == "/p/App.tsx" }.compactMap { $0["id"] })
    }

    /// A rerun finds the labels by column name, however a person saved the sheet, and gives each back
    /// to the candidate it was given for. A sheet with its columns moved is kept before it is replaced.
    @Test(arguments: ["as written", "CR LF", "CR", "a byte order mark", "admitted moved next to id"])
    func aRerunFindsTheLabelsHoweverTheSheetIsSaved(_ save: String) throws {
        let spike = try Spike(Self.reply)
        let sheet = try spike.run().labeled { "delivery: " + $0["path"]! }
        var text = sheet.text()
        switch save {
        case "CR LF": text = sheet.text(newline: "\r\n")
        case "CR": text = sheet.text(newline: "\r")
        case "a byte order mark": text = "\u{FEFF}" + text
        case "admitted moved next to id":
            var order = sheet.header.filter { $0 != "admitted" }
            order.insert("admitted", at: 1)
            text = sheet.text(order: order)
        default: break
        }
        try text.write(to: spike.sheet, atomically: true, encoding: .utf8)

        let rerun = try spike.run()
        #expect(rerun.rows.map { [$0["id"], $0["label"], $0["note"]] } == sheet.rows.map { [$0["id"], $0["label"], $0["note"]] })
        #expect(try Sheet(spike.read("labels-not-carried.tsv")).rows.isEmpty)
        let moved = save == "admitted moved next to id", name = "candidates-\(hex12(Data(text.utf8))).tsv"
        #expect((try? FileManager.default.contentsOfDirectory(atPath: spike.out.appendingPathComponent("replaced").path))
            == (moved ? [name] : nil))
        #expect(try spike.read("summary.txt").contains("labels: 2 carried" + (moved ? "; the sheet it replaced is kept as replaced/\(name)\n" : "\n")))
    }

    /// A label goes only to the reply and path it was given for. A rerun sets aside, with why, a label
    /// whose reply changed, whose candidate is gone, or whose row can't be read, and keeps the sheet
    /// they were on byte for byte before replacing it.
    @Test func aRerunSetsAsideTheLabelsItCannotCarry() throws {
        let spike = try Spike(Self.reply)
        try spike.write("Saved the [chart](out/chart.png) and the [notes](notes.md).", to: "s2")
        let sheet = try spike.run().labeled { "delivery: " + $0["path"]! }
        // A tab typed into the notes' note gives that row a cell more.
        let text = sheet.text().replacingOccurrences(of: "delivery: /p/notes.md", with: "delivery: /p/notes.md\tsee the plan")
        try text.write(to: spike.sheet, atomically: true, encoding: .utf8)
        try spike.write("The [report](out/report.md) is out of date.")

        let rerun = try spike.run()
        #expect(Dictionary(uniqueKeysWithValues: rerun.rows.map { ($0["path"]!, $0["label"]!) })
            == ["/p/out/report.md": "", "/p/out/chart.png": "delivery", "/p/notes.md": ""])
        let id = Dictionary(uniqueKeysWithValues: sheet.rows.map { ($0["path"]!, $0["id"]) })
        let setAside = try Sheet(spike.read("labels-not-carried.tsv")).rows.map { [$0["why"], $0["id"], $0["note"]] }
        #expect(setAside == [["changed", id["/p/out/report.md"]!, "delivery: /p/out/report.md"],
                             ["gone", id["/p/App.tsx"]!, "delivery: /p/App.tsx"],
                             ["unreadable", id["/p/notes.md"]!, "delivery: /p/notes.md"]])
        let kept = "replaced/candidates-\(hex12(Data(text.utf8))).tsv"
        #expect(try spike.read(kept) == text)
        #expect(try spike.read("summary.txt").contains(
            "labels: 1 carried, 3 set aside in labels-not-carried.tsv (1 changed, 1 gone, 1 unreadable); the sheet it replaced is kept as \(kept)\n"))
    }

    /// A label from a sheet without fingerprints can't be shown to judge the same reply, so it is set aside.
    @Test func aLabelWithoutAFingerprintIsSetAside() throws {
        let spike = try Spike(Self.reply)
        let sheet = try spike.run().labeled { _ in "" }
        try sheet.text(order: sheet.header.filter { $0 != "fingerprint" }).write(to: spike.sheet, atomically: true, encoding: .utf8)

        #expect(try spike.run().rows.allSatisfy { $0["label"] == "" })
        #expect(try Sheet(spike.read("labels-not-carried.tsv")).rows.map { $0["why"] } == ["changed", "changed"])
        #expect(try spike.read("summary.txt").contains("2 set aside"))
    }

    /// A sheet that isn't UTF-8 is kept as it was, and none of its labels is guessed at.
    @Test func aSheetThatCannotBeReadIsKept() throws {
        let spike = try Spike(Self.reply)
        var bytes = Data(try spike.run().labeled { _ in "" }.text().utf8)
        bytes.append(0xFF)
        try bytes.write(to: spike.sheet)

        #expect(try spike.run().rows.allSatisfy { $0["label"] == "" })
        #expect(try Data(contentsOf: spike.out.appendingPathComponent("replaced/candidates-\(hex12(bytes)).tsv")) == bytes)
        #expect(try spike.read("summary.txt").contains("labels: 0 carried; the previous candidates.tsv couldn't be read; the sheet it replaced is kept"))
    }
}

/// A synthetic home with Claude Code logs of one reply each, for `gleaner-spike` to read.
struct Spike {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-spike-\(UUID().uuidString)")
    var out: URL { root.appendingPathComponent("out") }
    var sheet: URL { out.appendingPathComponent("candidates.tsv") }

    init(_ reply: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("claude/-p"), withIntermediateDirectories: true)
        try write(reply)
    }

    /// Writes the log `session`, whose one record is `reply`, at line 1.
    func write(_ reply: String, to session: String = "s1") throws {
        let record: [String: Any] = [
            "type": "assistant", "timestamp": "2026-10-17T00:00:00.000Z", "cwd": "/p", "sessionId": session,
            "message": ["model": "m", "role": "assistant", "content": [["type": "text", "text": reply]]] as [String: Any],
        ]
        var line = try JSONSerialization.data(withJSONObject: record, options: [.withoutEscapingSlashes])
        line.append(0x0A)
        try line.write(to: root.appendingPathComponent("claude/-p/\(session).jsonl"))
    }

    /// Runs `gleaner-spike` on the home; the sheet it writes.
    @discardableResult func run() throws -> Sheet {
        let spike = Bundle.module.bundleURL.deletingLastPathComponent().appendingPathComponent("gleaner-spike")
        try #require(FileManager.default.isExecutableFile(atPath: spike.path), "build gleaner-spike first")
        let process = Process()
        process.executableURL = spike
        process.arguments = ["--claude-root", root.appendingPathComponent("claude").path,
                             "--codex-home", root.appendingPathComponent("codex").path, "--out", out.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return Sheet(try read("candidates.tsv"))
    }

    /// A file `gleaner-spike` wrote under `out/`.
    func read(_ name: String) throws -> String { try String(contentsOf: out.appendingPathComponent(name), encoding: .utf8) }
}

/// A sheet in gleaner-spike's format: its header, and each row by column name.
struct Sheet {
    var header: [String]
    var rows: [[String: String]]

    init(_ text: String) {
        let lines = text.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        let header = lines.first ?? []
        self.header = header
        rows = lines.dropFirst().map { Dictionary(zip(header, $0), uniquingKeysWith: { first, _ in first }) }
    }

    /// The sheet with each row labeled `delivery` and noted as `note` says.
    func labeled(_ note: ([String: String]) -> String) -> Sheet {
        var sheet = self
        sheet.rows = rows.map { row in row.merging(["label": "delivery", "note": note(row)]) { $1 } }
        return sheet
    }

    /// The sheet as a person might save it: its columns in `order`, its lines ending in `newline`.
    func text(order: [String]? = nil, newline: String = "\n") -> String {
        let columns = order ?? header
        return ([columns] + rows.map { row in columns.map { row[$0] ?? "" } }).map { $0.joined(separator: "\t") + newline }.joined()
    }
}

/// The first 12 hex digits of the SHA-256 of `data`, as gleaner-spike names what it keeps.
func hex12(_ data: Data) -> String {
    SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
}
