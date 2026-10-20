import CryptoKit
import Foundation
import Testing
@testable import GleanerCore

/// `outline`: a developer continuing earlier work in a new session found the earlier review report
/// and jumps to its finding `R3` without reading the whole report (retrieval rulings §2, §3).
extension CatalogTests {
    /// Delivers `text` as out/`name` in a later reply, and indexes the home.
    func deliverReport(_ text: String, as name: String = "review.md") throws -> (Catalog, String) {
        try write(Data(text.utf8), to: "out/\(name)", modified: delivered.addingTimeInterval(-30))
        try appendLog([
            user("Review the release", at: delivered.addingTimeInterval(30)),
            assistant("Report: [review](out/\(name))", at: delivered.addingTimeInterval(40)),
        ])
        try index(at: delivered.addingTimeInterval(60))
        let catalog = try catalog()
        return (catalog, try id(name, in: catalog))
    }

    @Test func aLineStartingWithInlineCodeOpensNoFence() throws {
        // The regression: a line starting with inline code once opened a fence that hid every heading after it.
        let (catalog, report) = try deliverReport("# Review\n```inline```\n## R1\nfirst\n## R2\nsecond\n")
        let outline = try catalog.outline(report)
        #expect(outline.headings.map(\.text) == ["Review", "R1", "R2"])
        let r1 = try #require(try catalog.outline(report, terms: ["R1"]).headings.only)
        #expect(r1.leadingId == "R1" && r1.level == 2 && r1.range == 22..<34 && r1.lines == 3...4)
        #expect(try catalog.read(report, span: .bytes(r1.range.lowerBound, r1.range.upperBound)).text == "## R1\nfirst\n")
        #expect(try catalog.read(report, span: .lines(r1.lines.lowerBound, r1.lines.upperBound)).text == "## R1\nfirst\n")
    }

    @Test func outlineFindsAFindingByItsWholeLeadingIdAndPicksNoneOfTwo() throws {
        let report = """
            # Review of 0.2

            ```swift
            ## R9 inside a fence is code
            ```
            ## R1 — Crash on launch
            The window opens before the library.
            ### Steps
            Open it twice.
            ## R10: Slow search ##
            ## [P0] Data loss
            ## Notes on R1
            ## 2.1 Scope
            ## r1 again, later
            #5 is not a heading
                ## nor is code indented four spaces

            """
        let (catalog, id) = try deliverReport(report)
        let all = try catalog.outline(id)
        #expect(all.headings.map(\.text) == ["Review of 0.2", "R1 — Crash on launch", "Steps", "R10: Slow search", "[P0] Data loss",
                                             "Notes on R1", "2.1 Scope", "r1 again, later"])
        #expect(all.headings.map(\.leadingId) == [nil, "R1", nil, "R10", "P0", nil, "2.1", "r1"])
        #expect(all.total == 8 && !all.ambiguous && all.truncated == .init(input: false, headings: false, text: false))
        #expect(all.parsed == all.size && all.size == report.utf8.count)
        // The first heading's section holds the whole report; R1's holds its steps and ends at R10.
        #expect(all.headings[0].range == 0..<report.utf8.count && all.headings[0].lines == 1...16)
        let r1 = all.headings[1]
        #expect(try catalog.read(id, span: .bytes(r1.range.lowerBound, r1.range.upperBound)).text
                == "## R1 — Crash on launch\nThe window opens before the library.\n### Steps\nOpen it twice.\n")

        // R1 is never R10, nor a heading that only mentions it; two headings with that ID are both
        // listed, and the answer says it is ambiguous.
        let r1s = try catalog.outline(id, terms: ["R1"])
        #expect(r1s.headings.map(\.text) == ["R1 — Crash on launch", "r1 again, later"] && r1s.total == 2 && r1s.ambiguous)
        #expect(try catalog.outline(id, terms: ["R10"]).headings.map(\.text) == ["R10: Slow search"])
        let one = try catalog.outline(id, terms: ["r10"])
        #expect(one.headings.count == 1 && !one.ambiguous)
        #expect(try catalog.outline(id, terms: ["p0"]).headings.map(\.leadingId) == ["P0"])
        #expect(try catalog.outline(id, terms: ["R9"]).headings.isEmpty)
        // Other terms are words of the text, every one of them.
        #expect(try catalog.outline(id, terms: ["crash launch"]).headings.map(\.leadingId) == ["R1"])
        #expect(try catalog.outline(id, terms: ["notes", "crash"]).headings.isEmpty)
        #expect(try catalog.outline(id, terms: ["R1", "crash"]).headings.map(\.text) == ["R1 — Crash on launch"])
    }

    @Test func leadingIdsAreWhole() {
        let ids: [String: String?] = [
            "R1": "R1", "R10 x": "R10", "**R3** Leak": "R3", "[P0] x": "P0", "F-3: x": "F-3", "1. Intro": "1", "2.1.4 x": "2.1.4",
            "A8": "A8", "R1a": nil, "R1.x": "R1", "Round 1": nil, "Review": nil, "`R2` x": "R2", "": nil,
        ]
        for (text, id) in ids { #expect(Catalog.leadingId(text) == id, "\(text)") }
        #expect(Catalog.heading("## R1 ##")! == (2, "R1"))
        #expect(Catalog.heading("##")! == (2, ""))
        #expect(Catalog.heading("### C# notes\r")! == (3, "C# notes"))
        for line in ["#R1", "####### seven", "    # code"] { #expect(Catalog.heading(line) == nil, "\(line)") }
    }

    @Test func outlineReadsTheVersionsBytesNeverWhatIsThereInstead() throws {
        let (catalog, report) = try deliverReport("# Report\n## R1\nfound\n")
        try write(Data("# Rewritten\n## R7\n".utf8), to: "out/review.md", modified: Date())
        let outline = try catalog.outline(report)
        #expect(outline.headings.map(\.text) == ["Report", "R1"])
        #expect(outline.reference.availability.state == .savedCopy)
        let delivered = SHA256.hash(data: Data("# Report\n## R1\nfound\n".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(outline.reference.sha256 == delivered && outline.size == 21)
        #expect(throws: Catalog.Failure.notText) { try catalog.outline(try id("frame.png", in: catalog)) }
        // Only the build's hash was kept: once it is rebuilt, there are no bytes to outline.
        try write(Data("rebuilt".utf8), to: "out/build.dmg", modified: Date())
        #expect(throws: Catalog.Failure.unavailable(.tooLargeToHaveBeenSaved)) { try catalog.outline(try id("build.dmg", in: catalog)) }
    }

    @Test func outlineCapsWhatItReadsListsAndGivesAndSaysSo() throws {
        let long = String(repeating: "é", count: Catalog.headingText + 5)
        var report = "# Top\n## \(long)\n"
        for n in 1...60 { report += "## R\(n)\nbody\n" }
        let (catalog, id) = try deliverReport(report)
        let capped = try catalog.outline(id, limit: 10)
        #expect(capped.headings.count == 10 && capped.total == 62)
        #expect(capped.truncated == .init(input: false, headings: true, text: true))
        #expect(capped.headings[1].text == String(repeating: "é", count: Catalog.headingText))
        // A section listed is closed by a heading left out.
        #expect(capped.headings[9].leadingId == "R8" && capped.headings[9].lines == 17...18)
        #expect(try catalog.outline(id).headings.count == Catalog.outlineLimit)
        for wrong in [0, Catalog.outlineMost + 1] {
            #expect(throws: Catalog.Failure.usage("The limit must be from 1 to \(Catalog.outlineMost).")) { try catalog.outline(id, limit: wrong) }
        }

        // Past the most it reads, a version's headings are not listed, and the outline ends at the last whole line read.
        let filler = String(repeating: "filler line\n", count: Catalog.outlineInput / 12)
        let (large, big) = try deliverReport("# Start\n" + filler + "## R1 past the end\n", as: "large.md")
        let start = try large.outline(big)
        #expect(start.headings.map(\.text) == ["Start"] && start.truncated.input)
        #expect(start.parsed == 8 + (Catalog.outlineInput - 8) / 12 * 12 && start.size == 8 + filler.utf8.count + 19)
        #expect(start.headings[0].range == 0..<start.parsed && start.headings[0].lines == 1...(start.parsed / 12 + 1))
    }
}

extension Array {
    /// The one element, or nil when there are none or several.
    fileprivate var only: Element? { count == 1 ? first : nil }
}
