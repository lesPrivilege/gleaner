import SwiftUI

/// Block-level Markdown from Foundation's parser: headings, paragraphs, lists, quotes, code
/// blocks and tables. Nothing is fetched: images show as their alt text and links open only when
/// clicked.
struct MarkdownPreview: View {
    let blocks: [Block]

    init(_ source: String) {
        blocks = Self.parse(source)
    }

    enum Block {
        case heading(Int, AttributedString)
        case paragraph(AttributedString)
        case item(depth: Int, marker: String, AttributedString)
        case quote(AttributedString)
        case code(String)
        case table([[AttributedString]])
        case rule
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(block)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder
    func view(_ block: Block) -> some View {
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

    static func parse(_ source: String) -> [Block] {
        guard let document = try? AttributedString(
            markdown: source,
            options: .init(allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible))
        else { return [.paragraph(AttributedString(source))] }

        var blocks: [Block] = []
        // Runs of one block share the identity of their innermost intent.
        var current: (id: Int, intent: PresentationIntent?, text: AttributedString)?
        var table: (id: Int, rows: [Int: [Int: AttributedString]])?

        func flushTable() {
            guard let t = table else { return }
            let rows = t.rows.keys.sorted().map { r in
                let cells = t.rows[r]!
                return (0...(cells.keys.max() ?? 0)).map { cells[$0] ?? AttributedString() }
            }
            blocks.append(.table(rows))
            table = nil
        }

        func flush() {
            guard let c = current else { return }
            current = nil
            let kinds = c.intent?.components.map(\.kind) ?? []
            var text = c.text
            text.presentationIntent = nil
            if kinds.contains(where: { if case .codeBlock = $0 { true } else { false } }) {
                var code = String(text.characters)
                if code.hasSuffix("\n") { code.removeLast() }
                blocks.append(.code(code))
            } else if let level = kinds.lazy.compactMap({ if case .header(let l) = $0 { l } else { nil } }).first {
                blocks.append(.heading(level, text))
            } else if let ordinal = kinds.lazy.compactMap({ if case .listItem(let o) = $0 { o } else { nil } }).first {
                let depth = kinds.filter { if case .listItem = $0 { true } else { false } }.count
                let ordered = kinds.first { k in
                    switch k { case .orderedList, .unorderedList: true; default: false }
                }.map { if case .orderedList = $0 { true } else { false } } ?? false
                blocks.append(.item(depth: depth, marker: ordered ? "\(ordinal)." : "•", text))
            } else if kinds.contains(where: { if case .blockQuote = $0 { true } else { false } }) {
                blocks.append(.quote(text))
            } else if kinds.contains(where: { if case .thematicBreak = $0 { true } else { false } }) {
                blocks.append(.rule)
            } else {
                blocks.append(.paragraph(text))
            }
        }

        for run in document.runs {
            let intent = run.presentationIntent
            let components = intent?.components ?? []
            if let tableComponent = components.first(where: { if case .table = $0.kind { true } else { false } }) {
                flush()
                if table?.id != tableComponent.identity { flushTable(); table = (tableComponent.identity, [:]) }
                var row = 0, column = 0
                for component in components {
                    switch component.kind {
                    case .tableHeaderRow: row = -1
                    case .tableRow(let r): row = r
                    case .tableCell(let c): column = c
                    default: break
                    }
                }
                var piece = AttributedString(document[run.range])
                piece.presentationIntent = nil
                table!.rows[row, default: [:]][column, default: AttributedString()].append(piece)
                continue
            }
            flushTable()
            let id = components.first?.identity ?? -1
            var piece = AttributedString(document[run.range])
            if current?.id == id {
                current!.text.append(piece)
            } else {
                flush()
                piece.presentationIntent = intent
                current = (id, intent, piece)
            }
        }
        flush()
        flushTable()
        return blocks
    }
}
