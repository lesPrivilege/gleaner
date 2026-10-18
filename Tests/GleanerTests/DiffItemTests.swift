import GleanerUI
import Testing
@testable import Gleaner
@testable import GleanerCore

@Suite struct DiffItemTests {
    /// Each fold carries the very lines it stands for, so opening it shows them in place.
    @Test func eachFoldCarriesTheLinesItStandsFor() {
        let old = (1...20).map(String.init).joined(separator: "\n")
        let new = old.replacingOccurrences(of: "\n10\n", with: "\nten\n")
        guard case .rows(let rows) = TextDiff.compare(old, new) else { Issue.record("expected rows"); return }
        let items = DiffItem.items(rows)
        var lines: [DiffLine] = []
        for item in items {
            switch item {
            case .line(let line): lines.append(line)
            case .folded(let folded): lines += folded
            }
        }
        #expect(lines == rows.map(DiffLine.init))
        guard case .folded(let first)? = items.first, case .folded(let last)? = items.last else { Issue.record("expected folds"); return }
        #expect(first.map(\.text) == (1...6).map(String.init))
        #expect(last.map(\.text) == (14...20).map(String.init))
    }
}
