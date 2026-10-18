import GleanerCore
import GleanerUI
import SwiftUI

/// Renders `MarkdownBlock`s at their full height; whoever shows them decides whether they scroll.
/// Links open only when clicked.
struct MarkdownPreview: View {
    let blocks: [MarkdownBlock]

    init(_ source: String) {
        blocks = MarkdownBlock.parse(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func view(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text).font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Text(text).fixedSize(horizontal: false, vertical: true)
        case .item(let depth, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary).frame(minWidth: 14, alignment: .trailing)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth - 1) * 18)
        case .quote(let text):
            Text(text).foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
        case .code(let text):
            ScrollView(.horizontal) {
                Text(text).font(.system(.callout, design: .monospaced)).padding(10)
            }
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.tag))
        case .table(let rows):
            // Cells wrap to the pane's width; a horizontal scroll view would give them unbounded
            // width and mis-measure wrapped rows.
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell).fontWeight(index == 0 ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if index < rows.count - 1 { Divider() }
                }
            }
            .font(.callout)
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: Radius.tag).strokeBorder(Color(nsColor: .separatorColor)))
        case .rule:
            Divider()
        }
    }
}
