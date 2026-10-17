import Foundation
import Testing
@testable import GleanerCore

@Suite struct TextDiffTests {
    func rows(_ old: String, _ new: String) -> [TextDiff.Row] {
        guard case .rows(let rows) = TextDiff.compare(old, new) else { Issue.record("limited"); return [] }
        return rows
    }

    @Test func linesKeepBothNumbersAndMarks() {
        let r = rows("a\nb\nc\n", "a\nc\nd\n")
        #expect(r.map(\.kind) == [.context, .removed, .context, .added])
        #expect(r.map(\.oldNumber) == [1, 2, 3, nil])
        #expect(r.map(\.newNumber) == [1, nil, 2, 3])
        #expect(TextDiff.compare("a\nb\nc\n", "a\nc\nd\n").summary == "1 added, 1 removed")
    }

    @Test func onlyNewWordsAreMarkedInAOneForOneReplacement() {
        let r = rows("Either party may end this agreement at will.\n",
                     "Either party may end this agreement on 30 days' written notice.\n")
        let added = r.first { $0.kind == .added }?.segments
        #expect(added?.filter(\.changed).map(\.text) == ["on 30 days' written notice."])
        let removed = r.first { $0.kind == .removed }?.segments
        #expect(removed?.filter(\.changed).map(\.text) == ["at will."])
    }

    @Test func longerReplacementsAreShownWhole() {
        let r = rows("one\ntwo\n", "uno\ndos\n")
        #expect(r.allSatisfy { $0.segments == nil })
    }

    @Test func chineseIsMarkedByCharacter() {
        let r = rows("全屏视觉：一处红、一条线\n", "全屏视觉：一处红、零装饰线\n")
        #expect(r.first { $0.kind == .added }?.segments?.filter(\.changed).map(\.text) == ["零装饰"])
    }

    @Test func indentationIsNeverMarked() {
        let r = rows("    let a = 1\n", "    let b = 1\n")
        let first = r.first { $0.kind == .added }?.segments?.first
        #expect(first?.text == "    let " && first?.changed == false)
    }

    @Test func identicalTextHasNoChanges() {
        #expect(TextDiff.compare("same\n", "same\n").summary == "No changes.")
    }

    @Test func differentBytesAreNeverNoChanges() {
        let endings = "Only line endings or the final newline differ."
        #expect(TextDiff.compare("a\r\nb\r\n", "a\nb\n").summary == endings)
        #expect(TextDiff.compare("a\nb\n", "a\nb").summary == endings)
        // A line that only looks the same, é composed and decomposed, is a changed line.
        #expect(TextDiff.compare("caf\u{e9}\n", "cafe\u{301}\n").summary == "1 added, 1 removed")
    }

    @Test func oversizedInputIsLimitedNotTruncated() {
        let big = String(repeating: "x\n", count: TextDiff.maxLines + 1)
        guard case .limited = TextDiff.compare(big, "x\n") else { Issue.record("expected limited"); return }
    }

    @Test func longUnchangedRunsFold() {
        let old = (1...20).map(String.init).joined(separator: "\n")
        let new = old.replacingOccurrences(of: "\n10\n", with: "\nten\n")
        let items = TextDiff.items(rows(old, new), context: 2)
        #expect(items.first == .unchanged(count: 7))
        #expect(items.last == .unchanged(count: 8))
    }
}

@Suite struct ComparisonTests {
    func end(_ title: String, _ text: String) throws -> Comparison.End {
        try end(title, Data(text.utf8))
    }

    func end(_ title: String, _ data: Data) throws -> Comparison.End {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).md")
        try data.write(to: url)
        return Comparison.End(title: title, source: "saved copy", sha: Locator.sha256(url.path)!, url: url)
    }

    @Test func imagesAreTheBytesThatWereHashed() throws {
        let a = try end("Delivery 1", "png v1"), b = try end("Delivery 2", "png v2")
        guard case .images(let old, let new) = Comparison.load(a, b, kind: .image) else {
            Issue.record("expected images"); return
        }
        // A writer after the check can't put new pixels under the old digest.
        try "edited".write(to: a.url, atomically: false, encoding: .utf8)
        #expect(old == Data("png v1".utf8))
        #expect(new == Data("png v2".utf8))
    }

    @Test func largeFilesThatAreNotTextCompareSizesAndHashes() throws {
        let pdf = Data("%PDF-1.7\n%".utf8) + Data(repeating: 0xE2, count: TextDiff.maxBytes)
        let a = try end("Delivery 1", pdf), b = try end("Delivery 2", pdf + Data([1]))
        #expect(Comparison.load(a, b, kind: .document)
                == .bytes(.init(size: Int64(pdf.count), sha: a.sha), .init(size: Int64(pdf.count + 1), sha: b.sha)))
    }

    @Test func largeTextIsReportedAsLimited() throws {
        // Three bytes a character, so the text limit falls inside one.
        let text = String(repeating: "数", count: TextDiff.maxBytes / 2)
        let content = Comparison.load(try end("Delivery 1", text), try end("Delivery 2", text + "!"), kind: .document)
        #expect(content == .text(.limited("One version is larger than 64 KB.")))
    }

    @Test func aPipeIsNeverOpened() async throws {
        let fifo = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).png")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let pipe = Comparison.End(title: "File on disk", source: "file on disk", sha: String(repeating: "0", count: 64), url: fifo)
        let other = try end("Delivery 1", "x")
        let load = Task.detached { Comparison.load(other, pipe, kind: .image) }
        try await Task.sleep(for: .milliseconds(500))
        // A writer opens only when a reader is waiting; it also releases a reader stuck opening the pipe.
        let writer = open(fifo.path, O_WRONLY | O_NONBLOCK)
        if writer >= 0 { close(writer) }
        #expect(writer < 0, "Comparison opened the pipe")
        #expect(await load.value == .failed("File on disk can no longer be read."))
    }

    @Test func textVersionsGetALineDiff() throws {
        let content = Comparison.load(try end("Delivery 1", "a\nb\n"), try end("Delivery 2", "a\nc\n"), kind: .document)
        guard case .text(let outcome) = content else { Issue.record("expected text"); return }
        #expect(outcome.summary == "1 added, 1 removed")
    }

    @Test func endsThatDifferOnlyInLineEndingsSaySo() throws {
        let content = Comparison.load(try end("Delivery 1", "a\r\nb\r\n"), try end("Delivery 2", "a\nb"), kind: .document)
        guard case .text(let outcome) = content else { Issue.record("expected text"); return }
        #expect(outcome.summary == "Only line endings or the final newline differ.")
    }

    @Test func bytesThatNoLongerMatchTheirHashAreRefused() throws {
        var changed = try end("File on disk", "a\n")
        try "edited\n".write(to: changed.url, atomically: true, encoding: .utf8)
        changed.title = "File on disk"
        guard case .failed(let reason) = Comparison.load(try end("Delivery 1", "b\n"), changed, kind: .code) else {
            Issue.record("expected a refusal"); return
        }
        #expect(reason.contains("changed since Gleaner checked it"))
    }

    @Test func otherKindsCompareSizesAndHashes() throws {
        guard case .bytes(let a, let b) = Comparison.load(try end("Delivery 1", "x"), try end("Delivery 2", "yy"), kind: .media) else {
            Issue.record("expected bytes"); return
        }
        #expect(a.size == 1 && b.size == 2)
    }
}
