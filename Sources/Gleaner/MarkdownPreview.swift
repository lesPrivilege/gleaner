import GleanerCore
import SwiftUI

/// Renders `MarkdownBlock`s, with an outline of the document's own headings beside them when it
/// has more than one. Links open only when clicked.
struct MarkdownPreview: View {
    let blocks: [MarkdownBlock]
    let headings: [MarkdownHeading]

    init(_ source: String) {
        blocks = MarkdownBlock.parse(source)
        headings = MarkdownBlock.headings(blocks)
    }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                if headings.count > 1 {
                    outline { block in withAnimation { proxy.scrollTo(Self.anchor(block), anchor: .top) } }
                        .frame(width: 200)
                    Divider()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                            view(block).id(Self.anchor(index))
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
        }
    }

    /// A block's scroll target, apart from the outline rows' own identities.
    static func anchor(_ block: Int) -> String { "block-\(block)" }

    /// The headings as written, indented by level; choosing one scrolls the preview to it.
    func outline(_ scroll: @escaping (Int) -> Void) -> some View {
        let top = headings.map(\.level).min() ?? 1
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("OUTLINE").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                ForEach(headings) { heading in
                    Button { scroll(heading.block) } label: {
                        Text(heading.title)
                            .font(heading.level == top ? .callout.weight(.medium) : .callout)
                            .foregroundStyle(heading.level == top ? .primary : .secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, CGFloat(min(heading.level - top, 3)) * 10)
                    .padding(.vertical, 2)
                    .help(heading.title)
                }
            }
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Outline")
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
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        case .rule:
            Divider()
        }
    }
}
