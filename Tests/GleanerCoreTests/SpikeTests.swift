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
    @Test func aSheetThatIsNotUTF8IsKept() throws {
        let spike = try Spike(Self.reply)
        var bytes = Data(try spike.run().labeled { _ in "" }.text().utf8)
        bytes.append(0xFF)
        try bytes.write(to: spike.sheet)

        #expect(try spike.run().rows.allSatisfy { $0["label"] == "" })
        #expect(try Data(contentsOf: spike.out.appendingPathComponent("replaced/candidates-\(hex12(bytes)).tsv")) == bytes)
        #expect(try spike.read("summary.txt").contains("labels: 0 carried; the previous candidates.tsv couldn't be read as a sheet; the sheet it replaced is kept"))
    }

    /// A sheet that is there but can't be opened may hold labels: the run stops before it replaces
    /// anything, and says so without its text.
    @Test func aSheetThatCannotBeOpenedStopsTheRun() throws {
        let spike = try Spike(Self.reply)
        try spike.run().labeled { _ in "PRIVATE-7f3a" }.text().write(to: spike.sheet, atomically: true, encoding: .utf8)
        let outputs = try spike.outputs()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: spike.sheet.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: spike.sheet.path) }
        let denied = try #require(throws: CocoaError.self) { try Data(contentsOf: spike.sheet) }
        try #require(denied.code == .fileReadNoPermission)

        let run = try spike.launch()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: spike.sheet.path)
        #expect(run.status != 0)
        #expect(run.stderr.contains("can't open"))
        #expect(!run.stderr.contains("PRIVATE-7f3a"))
        #expect(try spike.outputs() == outputs)
    }

    /// A copy already in `replaced/` stands for the sheet only if it holds the sheet's bytes, since an
    /// earlier run may have stopped while writing it. A short one stops the run before it replaces
    /// anything; the exact one lets the labels be set aside as usual.
    @Test(arguments: [false, true]) func aCopyInReplacedMustHoldTheSheet(exact: Bool) throws {
        let spike = try Spike(Self.reply)
        let text = try spike.run().labeled { _ in "PRIVATE-7f3a" }.text()
        try text.write(to: spike.sheet, atomically: true, encoding: .utf8)
        let name = "replaced/candidates-\(hex12(Data(text.utf8))).tsv", copy = Data((exact ? text : String(text.prefix(text.count / 2))).utf8)
        try FileManager.default.createDirectory(at: spike.out.appendingPathComponent("replaced"), withIntermediateDirectories: true)
        try copy.write(to: spike.out.appendingPathComponent(name))
        // Neither label can be carried now, so the sheet has to be kept before it is replaced.
        try spike.write("The [report](out/report.md) is out of date.")
        let outputs = try spike.outputs()

        let run = try spike.launch()
        #expect(!run.stderr.contains("PRIVATE-7f3a"))
        #expect(try Data(contentsOf: spike.out.appendingPathComponent(name)) == copy)
        if exact {
            #expect(run.status == 0)
            #expect(try Sheet(spike.read("labels-not-carried.tsv")).rows.map { $0["why"] } == ["changed", "gone"])
        } else {
            #expect(run.status != 0)
            #expect(run.stderr.contains("doesn't hold the sheet's bytes"))
            #expect(try spike.outputs() == outputs)
        }
    }

    // MARK: The recall sample

    /// The first run draws the recall sample into recall/replies.tsv, a row per reply with the id
    /// candidates.tsv gives its candidates, and starts an empty recall/misses.tsv. Moving `recall/`
    /// aside draws a new sample, of the size asked for.
    @Test func theFirstRunDrawsTheRecallSample() throws {
        let spike = try Spike(Self.reply)
        try spike.write("Saved the [chart](out/chart.png).", to: "s2")
        try spike.write("Nothing to hand over.", to: "s3")
        let sheet = try spike.run()
        let sample = try Sheet(spike.read("recall/replies.tsv"))
        #expect(sample.header == ["reply", "reviewed", "note", "provider", "project", "session_title", "delivered_at", "session_id", "fingerprint"])
        #expect(sample.rows.count == 3)
        #expect(sample.rows.allSatisfy { $0["reviewed"] == "" && $0["note"] == "" && $0["fingerprint"]?.count == 12 })
        let replies = Set(sheet.rows.compactMap { $0["reply"] })
        #expect(replies.count == 2 && replies.isSubset(of: sample.rows.compactMap { $0["reply"] }))
        #expect(try spike.read("recall/misses.tsv") == "reply\tpath\tnote\n")
        #expect(try spike.read("summary.txt").contains("recall sample (recall/): replies: 3  drawn now, seed 42  reviewed: 0"))
        #expect(!FileManager.default.fileExists(atPath: spike.out.appendingPathComponent("recall-sample.md").path))

        try FileManager.default.moveItem(at: spike.out.appendingPathComponent("recall"), to: spike.out.appendingPathComponent("recall-1"))
        try spike.run(["--sample", "1"])
        #expect(try Sheet(spike.read("recall/replies.tsv")).rows.count == 1)
    }

    /// No run writes the sample or the misses again: a person's review survives reruns, a new reply
    /// stays out of the sample, and the page shows the review.
    @Test func aRerunLeavesTheSampleAndTheReviewAlone() throws {
        let spike = try Spike(Self.reply)
        try spike.run()
        var sample = try Sheet(spike.read("recall/replies.tsv"))
        sample.rows[0]["reviewed"] = "yes"
        sample.rows[0]["note"] = "checked"
        let id = sample.rows[0]["reply"]!
        try sample.text().write(to: spike.out.appendingPathComponent("recall/replies.tsv"), atomically: true, encoding: .utf8)
        try "reply\tpath\tnote\n\(id)\tout/chart.png\tnamed in prose\n"
            .write(to: spike.out.appendingPathComponent("recall/misses.tsv"), atomically: true, encoding: .utf8)
        let review = try [spike.read("recall/replies.tsv"), spike.read("recall/misses.tsv")]
        try spike.write("Saved the [chart](out/chart.png).", to: "s2")

        try spike.run()
        #expect(try [spike.read("recall/replies.tsv"), spike.read("recall/misses.tsv")] == review)
        let view = try spike.read("recall/replies.md")
        #expect(view.contains("- reply `\(id)` · reviewed: yes · as sampled"))
        #expect(view.contains("- `out/chart.png` · named in prose"))
        #expect(view.components(separatedBy: "\n## ").count == 2)
        #expect(try spike.read("summary.txt").contains("replies: 1  reviewed: 1  changed since sampled: 0  gone since sampled: 0  misses: 1\n"))
    }

    /// The page says which sampled replies changed or went since they were drawn; the sample stays as drawn.
    @Test func theSampleSaysWhichRepliesChangedOrWent() throws {
        let spike = try Spike(Self.reply)
        try spike.write("Saved the [chart](out/chart.png).", to: "s2")
        try spike.run()
        let sample = try spike.read("recall/replies.tsv")
        try spike.write("The [report](out/report.md) is out of date.")
        try FileManager.default.removeItem(at: spike.root.appendingPathComponent("claude/-p/s2.jsonl"))

        try spike.run()
        #expect(try spike.read("recall/replies.tsv") == sample)
        let view = try spike.read("recall/replies.md")
        #expect(view.contains("changed since it was sampled, so its review no longer counts"))
        #expect(view.contains("gone from the logs"))
        #expect(try spike.read("summary.txt").contains("changed since sampled: 1  gone since sampled: 1"))
    }

    /// A person's recall file that can't be opened, or read as a sheet with its columns, stops the run
    /// before it writes anything, and it says so without the file's text.
    @Test(arguments: ["replies.tsv can't be opened", "replies.tsv has no fingerprint", "misses.tsv has no path"])
    func aReviewThatCannotBeReadStopsTheRun(_ damage: String) throws {
        let spike = try Spike(Self.reply)
        try spike.run()
        let replies = spike.out.appendingPathComponent("recall/replies.tsv")
        var sample = try Sheet(spike.read("recall/replies.tsv"))
        sample.rows[0]["note"] = "PRIVATE-7f3a"
        let columns = damage == "replies.tsv has no fingerprint" ? sample.header.filter { $0 != "fingerprint" } : sample.header
        try sample.text(order: columns).write(to: replies, atomically: true, encoding: .utf8)
        if damage == "misses.tsv has no path" {
            try "reply\tnote\n\(sample.rows[0]["reply"]!)\tPRIVATE-7f3a\n"
                .write(to: spike.out.appendingPathComponent("recall/misses.tsv"), atomically: true, encoding: .utf8)
        }
        let outputs = try spike.outputs()
        if damage == "replies.tsv can't be opened" {
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: replies.path)
            let denied = try #require(throws: CocoaError.self) { try Data(contentsOf: replies) }
            try #require(denied.code == .fileReadNoPermission)
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: replies.path) }

        let run = try spike.launch()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: replies.path)
        #expect(run.status != 0)
        #expect(run.stderr.contains(String(damage.prefix { $0 != " " })))
        #expect(!run.stderr.contains("PRIVATE-7f3a"))
        #expect(try spike.outputs() == outputs)
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
    @discardableResult func run(_ options: [String] = []) throws -> Sheet {
        #expect(try launch(options).status == 0)
        return Sheet(try read("candidates.tsv"))
    }

    /// Runs `gleaner-spike` on the home: how it exited, and what it said on stderr.
    func launch(_ options: [String] = []) throws -> (status: Int32, stderr: String) {
        let spike = Bundle.module.bundleURL.deletingLastPathComponent().appendingPathComponent("gleaner-spike")
        try #require(FileManager.default.isExecutableFile(atPath: spike.path), "build gleaner-spike first")
        let process = Process(), errors = Pipe()
        process.executableURL = spike
        process.arguments = ["--claude-root", root.appendingPathComponent("claude").path,
                             "--codex-home", root.appendingPathComponent("codex").path, "--out", out.path] + options
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let said = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: said, as: UTF8.self))
    }

    /// A file `gleaner-spike` wrote under `out/`.
    func read(_ name: String) throws -> String { try String(contentsOf: out.appendingPathComponent(name), encoding: .utf8) }

    /// Every file under `out/`, by its path there, with its bytes.
    func outputs() throws -> [String: Data] {
        var files: [String: Data] = [:]
        for name in FileManager.default.subpaths(atPath: out.path) ?? [] {
            let url = out.appendingPathComponent(name)
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files[name] = try Data(contentsOf: url) }
        }
        return files
    }
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
