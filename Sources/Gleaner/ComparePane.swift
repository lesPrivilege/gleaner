import AppKit
import GleanerCore
import SwiftUI

/// Two exact versions, in place of the preview. Read-only: nothing here chooses a winner.
struct ComparePane: View {
    @Environment(LibraryModel.self) private var model
    var artifact: Artifact
    var from: Comparison.End
    var to: Comparison.End
    @State private var loaded: (request: Request, content: Comparison.Content)?

    /// What a comparison is of: both ends, each naming its delivery, source and hash.
    struct Request: Equatable {
        var from: Comparison.End
        var to: Comparison.End
        var kind: Artifact.Kind
    }

    var body: some View {
        let request = Request(from: from, to: to, kind: artifact.kind)
        let content = Self.content(loaded, for: request)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(from.title) → \(to.title)").font(.headline)
                Text("\(label(from)) → \(label(to))")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Close Comparison") { model.comparison = nil }
                    .keyboardShortcut(.cancelAction)
            }
            Group {
                switch content {
                case nil:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                case .text(.limited(let reason))?:
                    note(reason + " Read either exact version on its own.")
                case .text(let outcome)?:
                    Text(outcome.summary).font(.caption).foregroundStyle(.secondary)
                    if case .rows(let rows) = outcome, rows.contains(where: { $0.kind != .context }) { DiffRows(rows: rows) }
                case .images(let a, let b)?:
                    HStack(spacing: 12) {
                        image(a, end: from)
                        image(b, end: to)
                    }
                case .bytes(let a, let b)?:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(a.sha == b.sha ? "Same content" : "These bytes differ").font(.callout.weight(.semibold))
                        bytesLine(from, a)
                        bytesLine(to, b)
                        Text("Gleaner compares text line by line and images side by side; for these files it compares size and hash.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .failed(let reason)?:
                    HStack {
                        note(reason)
                        Button("Check Again") {
                            model.comparison = nil
                            Task { await model.checkAgain(artifact) }
                        }
                        .help("Close the comparison, check the file now, and prepare its copy again.")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        .task(id: request) {
            let result = await Task.detached(priority: .userInitiated) {
                Comparison.load(request.from, request.to, kind: request.kind)
            }.value
            // Another comparison was asked for while this one loaded.
            guard !Task.isCancelled else { return }
            loaded = (request, result)
        }
    }

    /// Only a result loaded for this very pair is shown; until then it is loading.
    static func content(_ loaded: (request: Request, content: Comparison.Content)?, for request: Request) -> Comparison.Content? {
        loaded?.request == request ? loaded?.content : nil
    }

    func label(_ end: Comparison.End) -> String { "\(end.source) · \(end.sha.prefix(8))" }

    func note(_ text: String) -> some View {
        StatusLabel(mark: .hollow, text: text).font(.callout).foregroundStyle(.secondary)
    }

    func bytesLine(_ end: Comparison.End, _ bytes: Comparison.Bytes) -> some View {
        Text("\(end.title): \(ByteCountFormatter.string(fromByteCount: bytes.size, countStyle: .file)) · \(bytes.sha.prefix(12))…")
            .font(.system(.callout, design: .monospaced))
    }

    func image(_ data: Data, end: Comparison.End) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 280)
                Text("\(end.title) · \(Int(image.size.width))×\(Int(image.size.height))").font(.caption).foregroundStyle(.secondary)
            } else {
                note("\(end.title) can’t be shown as an image.")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Courtwork's change language: grey for what was there, the change colour for new lines, and a
/// solid block only on the words that are new. Marks and both line numbers stay, so colour is
/// never the only carrier.
struct DiffRows: View {
    var rows: [TextDiff.Row]
    @State private var expanded: Set<Int> = []

    var body: some View {
        let items = TextDiff.items(rows)
        // A two-axis scroll view centres content narrower than itself; pin rows to the leading edge.
        GeometryReader { geometry in
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    switch item {
                    case .row(let row):
                        line(row)
                    case .unchanged(let count):
                        if expanded.contains(index) {
                            ForEach(Array(unchangedRows(before: index, items: items, count: count).enumerated()), id: \.offset) { _, row in
                                line(row)
                            }
                        } else {
                            Button("⋯ \(count) unchanged line\(count == 1 ? "" : "s")") { expanded.insert(index) }
                                .buttonStyle(.plain)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 3)
                                .padding(.leading, 10 * 7)
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .padding(.vertical, 6)
            .frame(minWidth: geometry.size.width, alignment: .leading)
        }
        }
        .frame(height: min(420, CGFloat(items.count) * 23 + 14))
    }

    /// The context rows a fold stands for, recovered from the row list by position.
    func unchangedRows(before index: Int, items: [TextDiff.Item], count: Int) -> [TextDiff.Row] {
        let shown = items[..<index].reduce(0) { total, item in
            switch item {
            case .row: total + 1
            case .unchanged(let n): total + n
            }
        }
        return Array(rows[shown..<min(rows.count, shown + count)])
    }

    func line(_ row: TextDiff.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(row.oldNumber.map(String.init) ?? "").frame(width: 38, alignment: .trailing).foregroundStyle(.tertiary)
            Text(row.newNumber.map(String.init) ?? "").frame(width: 38, alignment: .trailing).foregroundStyle(.tertiary)
            Text(row.kind == .added ? "+" : row.kind == .removed ? "−" : " ")
                .fontWeight(.semibold).frame(width: 22)
                .foregroundStyle(row.kind == .added ? Palette.change : .secondary)
            Text(text(row)).fixedSize()
        }
        .font(.system(.callout, design: .monospaced))
        .lineSpacing(4)
        .padding(.trailing, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(row))
    }

    func text(_ row: TextDiff.Row) -> AttributedString {
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

    func spoken(_ row: TextDiff.Row) -> String {
        switch row.kind {
        case .added:
            let new = row.segments?.filter(\.changed).map(\.text).joined(separator: " ")
            return "Added line \(row.newNumber ?? 0): \(row.text)" + (new.map { ". New words: \($0)" } ?? "")
        case .removed: return "Removed line \(row.oldNumber ?? 0): \(row.text)"
        case .context: return "Line \(row.newNumber ?? 0): \(row.text)"
        }
    }
}
