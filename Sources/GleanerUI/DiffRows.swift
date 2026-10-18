import AppKit
import SwiftUI

/// One line of a comparison: its kind, its number on each side, and, for a line that replaces one
/// other line, its words with the changed ones marked.
public struct DiffLine: Equatable, Sendable {
    public enum Kind: Sendable { case context, added, removed }

    public struct Segment: Equatable, Sendable {
        public var text: String
        public var changed: Bool

        public init(text: String, changed: Bool) {
            self.text = text
            self.changed = changed
        }
    }

    public var kind: Kind
    public var oldNumber: Int?
    public var newNumber: Int?
    public var text: String
    public var segments: [Segment]?

    public init(kind: Kind, oldNumber: Int?, newNumber: Int?, text: String, segments: [Segment]? = nil) {
        self.kind = kind
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        self.text = text
        self.segments = segments
    }
}

/// What a comparison shows in order: a line, or a run of unchanged lines folded into one row.
public enum DiffItem: Equatable, Sendable {
    case line(DiffLine)
    case folded([DiffLine])
}

/// Courtwork's change language: grey for what was there, the change color for new lines, and a
/// solid block only on the words that are new. Marks and both line numbers stay, so color is
/// never the only carrier. A folded run opens in place when clicked. The rows are as tall as they
/// are, up to `tallest`, past which they scroll.
public struct DiffRows: View {
    public var items: [DiffItem]
    @State private var expanded: Set<Int> = []
    @State private var height: CGFloat?

    public static let tallest: CGFloat = 420
    /// The two line-number columns and the mark's: the text starts after them.
    static let numberWidth: CGFloat = 38, markWidth: CGFloat = 22

    public init(items: [DiffItem]) {
        self.items = items
    }

    public var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    switch item {
                    case .line(let row):
                        line(row)
                    case .folded(let rows):
                        if expanded.contains(index) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                line(row)
                            }
                        } else {
                            Button("⋯ \(rows.count) unchanged line\(rows.count == 1 ? "" : "s")") { expanded.insert(index) }
                                .buttonStyle(.plain)
                                .fixedSize()
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 3)
                                .padding(.leading, 2 * Self.numberWidth + Self.markWidth)
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .padding(.vertical, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        // A two-axis scroll view centres content smaller than itself; hold the rows at the top left.
        .defaultScrollAnchor(.topLeading, for: .alignment)
        // Until the rows are measured, a guess from their count.
        .frame(height: min(height ?? CGFloat(items.count) * 20 + 12, Self.tallest))
    }

    func line(_ row: DiffLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(row.oldNumber.map(String.init) ?? "").frame(width: Self.numberWidth, alignment: .trailing).foregroundStyle(.tertiary)
            Text(row.newNumber.map(String.init) ?? "").frame(width: Self.numberWidth, alignment: .trailing).foregroundStyle(.tertiary)
            Text(row.kind == .added ? "+" : row.kind == .removed ? "−" : " ")
                .fontWeight(.semibold).frame(width: Self.markWidth)
                .foregroundStyle(row.kind == .added ? Palette.change : .secondary)
            Text(text(row)).fixedSize()
        }
        .font(.system(.callout, design: .monospaced))
        .lineSpacing(4)
        .padding(.trailing, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(row))
    }

    func text(_ row: DiffLine) -> AttributedString {
        let base: Color = row.kind == .added ? Palette.change : .secondary
        guard let segments = row.segments else {
            var text = AttributedString(row.text)
            text.foregroundColor = base
            return text
        }
        var out = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            part.foregroundColor = base
            if segment.changed {
                if row.kind == .added {
                    part.backgroundColor = Palette.changeBlock
                    part.foregroundColor = Palette.changeInk
                } else {
                    part.backgroundColor = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                    part.foregroundColor = .primary
                }
            }
            out.append(part)
        }
        return out
    }

    func spoken(_ row: DiffLine) -> String {
        switch row.kind {
        case .added:
            let new = row.segments?.filter(\.changed).map(\.text).joined(separator: " ")
            return "Added line \(row.newNumber ?? 0): \(row.text)" + (new.map { ". New words: \($0)" } ?? "")
        case .removed: return "Removed line \(row.oldNumber ?? 0): \(row.text)"
        case .context: return "Line \(row.newNumber ?? 0): \(row.text)"
        }
    }
}
