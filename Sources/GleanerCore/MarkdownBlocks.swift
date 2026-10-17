import Foundation

/// Block-level Markdown from Foundation's parser: headings, paragraphs, lists, quotes, code
/// blocks and tables, each with its inline styling. Nothing is fetched: an image becomes its alt
/// text with no image URL left on it.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(Int, AttributedString)
    case paragraph(AttributedString)
    case item(depth: Int, marker: String, AttributedString)
    case quote(AttributedString)
    case code(String)
    case table([[AttributedString]])
    case rule

    public static func parse(_ source: String) -> [MarkdownBlock] {
        guard let document = try? AttributedString(
            markdown: source,
            options: .init(allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible))
        else { return [.paragraph(AttributedString(source))] }

        var blocks: [MarkdownBlock] = []
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
            text.imageURL = nil
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
                piece.imageURL = nil
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
