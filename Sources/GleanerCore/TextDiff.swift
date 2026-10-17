import Foundation

/// A line comparison of two exact versions, in Courtwork's change language (docs/design/
/// diff-and-references.md): rows keep their −/+ mark and both line numbers, and word-level
/// segments appear only where exactly one removed line is followed by exactly one added line.
/// Inputs over the caps give `.limited`, never a partial diff.
public enum TextDiff {
    public static let maxBytes = 64 << 10
    public static let maxLines = 2000

    public enum Kind: Sendable, Equatable { case context, added, removed }

    public struct Segment: Sendable, Equatable {
        public var text: String
        public var changed: Bool
    }

    public struct Row: Sendable, Equatable {
        public var kind: Kind
        public var oldNumber: Int?
        public var newNumber: Int?
        public var text: String
        /// Set for a one-for-one replaced line: which words changed.
        public var segments: [Segment]?
    }

    public enum Outcome: Sendable, Equatable {
        case rows([Row])
        case limited(String)
    }

    /// What a reader sees: changed rows with a little context, and folds for long unchanged runs.
    public enum Item: Sendable, Equatable {
        case row(Row)
        case unchanged(count: Int)
    }

    public static func compare(_ old: String, _ new: String) -> Outcome {
        if old.utf8.count > maxBytes || new.utf8.count > maxBytes {
            return .limited("One version is larger than \(maxBytes >> 10) KB.")
        }
        let a = lines(old), b = lines(new)
        if a.count > maxLines || b.count > maxLines {
            return .limited("One version has more than \(maxLines) lines.")
        }
        let difference = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var rows: [Row] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                rows.append(Row(kind: .removed, oldNumber: i + 1, newNumber: nil, text: a[i]))
                i += 1
            } else if j < b.count, inserted.contains(j) {
                rows.append(Row(kind: .added, oldNumber: nil, newNumber: j + 1, text: b[j]))
                j += 1
            } else {
                rows.append(Row(kind: .context, oldNumber: i + 1, newNumber: j + 1, text: b[j]))
                i += 1
                j += 1
            }
        }
        // Word segments for every single removed line followed by a single added line.
        var index = 0
        while index < rows.count {
            guard rows[index].kind == .removed else { index += 1; continue }
            var end = index
            while end < rows.count, rows[end].kind == .removed { end += 1 }
            var addEnd = end
            while addEnd < rows.count, rows[addEnd].kind == .added { addEnd += 1 }
            if end - index == 1, addEnd - end == 1 {
                let words = self.words(rows[index].text, rows[end].text)
                rows[index].segments = words.old
                rows[end].segments = words.new
            }
            index = max(addEnd, index + 1)
        }
        return .rows(rows)
    }

    /// Changed rows with `context` unchanged lines around each change; longer unchanged runs fold.
    public static func items(_ rows: [Row], context: Int = 3) -> [Item] {
        let changed = rows.indices.filter { rows[$0].kind != .context }
        guard !changed.isEmpty else { return rows.isEmpty ? [] : [.unchanged(count: rows.count)] }
        var keep = Set<Int>()
        for index in changed {
            for k in max(0, index - context)...min(rows.count - 1, index + context) { keep.insert(k) }
        }
        var items: [Item] = []
        var run = 0
        for (index, row) in rows.enumerated() {
            if keep.contains(index) {
                if run > 0 { items.append(.unchanged(count: run)); run = 0 }
                items.append(.row(row))
            } else {
                run += 1
            }
        }
        if run > 0 { items.append(.unchanged(count: run)) }
        return items
    }

    static func lines(_ text: String) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.hasSuffix("\r") ? String(line.dropLast()) : String(line)
        }
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Whitespace runs, single CJK characters, or runs of anything else: a changed Chinese word
    /// is marked by its characters, not its whole sentence.
    static let token = try! NSRegularExpression(
        pattern: #"\s+|[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]|[^\s\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]+"#)

    static func tokens(_ text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return token.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    static func words(_ old: String, _ new: String) -> (old: [Segment], new: [Segment]) {
        let a = tokens(old), b = tokens(new)
        if a.count > 2048 || b.count > 2048 || a.count * b.count > 65536 {
            return ([Segment(text: old, changed: true)], [Segment(text: new, changed: true)])
        }
        let difference = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        let oldSegments = a.indices.map { Segment(text: a[$0], changed: removed.contains($0)) }
        let newSegments = b.indices.map { Segment(text: b[$0], changed: inserted.contains($0)) }
        return (absorbWhitespace(oldSegments), absorbWhitespace(newSegments))
    }

    /// Whitespace between two changed words joins them into one block, and leading indentation is
    /// never marked, so a block starts and ends on visible text.
    static func absorbWhitespace(_ segments: [Segment]) -> [Segment] {
        var merged: [Segment] = []
        for segment in segments {
            if let last = merged.last, last.changed == segment.changed {
                merged[merged.count - 1].text += segment.text
            } else {
                merged.append(segment)
            }
        }
        var out: [Segment] = []
        for (index, segment) in merged.enumerated() {
            let blank = segment.text.trimmingCharacters(in: .whitespaces).isEmpty
            let bridges = !segment.changed && blank && out.last?.changed == true
                && index + 1 < merged.count && merged[index + 1].changed
            var next = segment
            if bridges { next.changed = true }
            if next.changed && blank && out.isEmpty { next.changed = false }
            if let last = out.last, last.changed == next.changed {
                out[out.count - 1].text += next.text
            } else {
                out.append(next)
            }
        }
        return out.filter { !$0.text.isEmpty }
    }
}

extension TextDiff.Outcome {
    public var summary: String {
        switch self {
        case .limited(let reason): return reason
        case .rows(let rows):
            let added = rows.filter { $0.kind == .added }.count
            let removed = rows.filter { $0.kind == .removed }.count
            if added == 0 && removed == 0 { return rows.isEmpty ? "No lines." : "No changes." }
            return "\(added) added, \(removed) removed"
        }
    }
}
