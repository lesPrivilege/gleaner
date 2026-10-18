import AppKit
import GleanerCore
import GleanerUI
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
                Button("Done") { model.comparison = nil }
                    .keyboardShortcut(.cancelAction)
                    .help("Close the comparison (Esc)")
            }
            Group {
                switch content {
                case nil:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                case .text(.limited(let reason))?:
                    note(reason, mark: .na)
                case .text(let outcome)?:
                    Text(outcome.summary).font(.caption).foregroundStyle(.secondary)
                    if case .rows(let rows) = outcome, rows.contains(where: { $0.kind != .context }) { DiffRows(items: DiffItem.items(rows)) }
                case .images(let a, let b)?:
                    HStack(spacing: 12) {
                        image(a, end: from)
                        image(b, end: to)
                    }
                case .bytes(let a, let b)?:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(a.sha == b.sha ? "Same content" : "Different bytes").font(.callout.weight(.semibold))
                        bytesLine(from, a)
                        bytesLine(to, b)
                    }
                case .failed(let reason)?:
                    HStack {
                        note(reason, mark: .failed)
                        Button("Check Again") {
                            model.comparison = nil
                            Task { await model.checkAgain(artifact) }
                        }
                        .help("Close the comparison, check the file now, and prepare its copy again.")
                    }
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(.page)
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

    func note(_ text: String, mark: Mark) -> some View {
        StatusLabel(mark: mark, text: text).font(.callout)
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
                note("\(end.title) can’t be shown as an image", mark: .na)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension DiffItem {
    /// The rows as the comparison shows them: each change with the lines around it, and each
    /// longer unchanged run folded (`TextDiff.items`).
    static func items(_ rows: [TextDiff.Row]) -> [DiffItem] {
        var shown = 0
        return TextDiff.items(rows).map { item in
            switch item {
            case .row(let row):
                shown += 1
                return .line(DiffLine(row))
            case .unchanged(let count):
                defer { shown += count }
                return .folded(rows[shown..<min(rows.count, shown + count)].map(DiffLine.init))
            }
        }
    }
}

extension DiffLine {
    init(_ row: TextDiff.Row) {
        let kind: Kind = switch row.kind {
        case .context: .context
        case .added: .added
        case .removed: .removed
        }
        self.init(kind: kind, oldNumber: row.oldNumber, newNumber: row.newNumber, text: row.text,
                  segments: row.segments?.map { Segment(text: $0.text, changed: $0.changed) })
    }
}
