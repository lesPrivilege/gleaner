import Foundation
import Testing
@testable import GleanerCore

@Suite struct MarkdownBlockTests {
    /// Each block as plain text, so expectations read like the document.
    func outline(_ source: String) -> [String] {
        MarkdownBlock.parse(source).map { block in
            func s(_ a: AttributedString) -> String { String(a.characters) }
            switch block {
            case .heading(let level, let text): return "h\(level) \(s(text))"
            case .paragraph(let text): return "p \(s(text))"
            case .item(let depth, let marker, let text): return "\(String(repeating: " ", count: depth - 1))\(marker) \(s(text))"
            case .quote(let text): return "> \(s(text))"
            case .code(let text): return "code \(text)"
            case .table(let rows): return "table " + rows.map { $0.map(s).joined(separator: "|") }.joined(separator: " / ")
            case .rule: return "---"
            }
        }
    }

    @Test func headingsParagraphsAndRules() {
        #expect(outline("# Title\n\nSome **bold** text.\n\n---\n\n## Next") == ["h1 Title", "p Some bold text.", "---", "h2 Next"])
    }

    @Test func nestedAndOrderedLists() {
        #expect(outline("- one\n- two\n  - inner\n\n1. first\n2. second") ==
                ["• one", "• two", " • inner", "1. first", "2. second"])
    }

    @Test func tablesKeepRowsAndColumns() {
        #expect(outline("| Area | Result |\n|---|---|\n| Bar | 63 checks |\n| Tab | worked |") ==
                ["table Area|Result / Bar|63 checks / Tab|worked"])
    }

    @Test func codeBlocksAndQuotes() {
        #expect(outline("```\nlet x = 1\n```\n\n> quoted") == ["code let x = 1", "> quoted"])
    }

    @Test func imagesBecomeAltTextWithNothingToFetch() throws {
        let blocks = MarkdownBlock.parse("See ![a diagram](https://example.com/d.png) here.")
        guard case .paragraph(let text) = try #require(blocks.first) else { Issue.record("expected a paragraph"); return }
        #expect(String(text.characters) == "See a diagram here.")
        #expect(text.runs.allSatisfy { $0.imageURL == nil })
    }
}
