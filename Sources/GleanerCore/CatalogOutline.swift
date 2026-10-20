import Foundation

/// The headings of one delivery's exact bytes (retrieval rulings §2), so a caller continuing earlier
/// work jumps to a finding such as `R3` in a report and reads only its section.
extension Catalog {
    /// The most bytes of a version `outline` reads, from its start.
    public static let outlineInput = 4 << 20
    /// The most headings `outline` lists, and how many unless asked.
    public static let outlineMost = 500, outlineLimit = 50
    /// The most characters of a heading's text an outline gives.
    public static let headingText = 200

    /// The headings of the delivery's exact bytes, in order, each with its section's bytes and lines:
    /// from the heading to the next heading of its level or above. They are read once, in `read`'s
    /// checked pass over the saved copy or an original that still hashes to the version, so every
    /// range is of the bytes `reference.sha256` names. With `terms`, only the headings each term
    /// matches: a term in the form of an ID (`R1`, `F-3`, `2.1`) only a heading with that whole leading
    /// ID, never `R10`; any other term a heading's text that contains it. More than one heading
    /// matching is `ambiguous`, and each is listed: none is picked. At most `limit` are listed.
    public func outline(_ id: String, terms: [String] = [], limit: Int = outlineLimit) throws -> Outline {
        guard (1...Self.outlineMost).contains(limit) else {
            throw Failure.usage("The limit must be from 1 to \(Self.outlineMost).")
        }
        let words = terms.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
        let read = try read(id, max: Self.outlineInput)
        var bytes = Array(read.text.utf8)
        // A version longer than what is read ends its outline at the last whole line read.
        if read.truncated, let newline = bytes.lastIndex(of: UInt8(ascii: "\n")) { bytes.removeSubrange((newline + 1)...) }

        var headings: [Heading] = [], total = 0, textCut = false
        // Headings listed whose sections are still open, their levels rising: a heading closes each
        // of its level or deeper, so each closes once.
        var open: [Int] = []
        var fences = MentionExtractor.Fences(), start = 0, number = 0
        func close(above level: Int, at end: Int, line last: Int) {
            while let top = open.last, headings[top].level >= level {
                headings[top].range = headings[top].range.lowerBound..<end
                headings[top].lines = headings[top].lines.lowerBound...last
                open.removeLast()
            }
        }
        while start < bytes.count {
            let newline = bytes[start...].firstIndex(of: UInt8(ascii: "\n"))
            let end = newline.map { $0 + 1 } ?? bytes.count
            number += 1
            var line = String(decoding: bytes[start..<(newline ?? end)], as: UTF8.self)
            if start == 0, line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            if !fences.read(line), let (level, text) = Self.heading(line) {
                close(above: level, at: start, line: number - 1)
                let leadingId = Self.leadingId(text)
                if words.allSatisfy({ Self.matches($0, text: text, leadingId: leadingId) }) {
                    total += 1
                    if headings.count < limit {
                        textCut = textCut || text.count > Self.headingText
                        headings.append(Heading(level: level, text: String(text.prefix(Self.headingText)), leadingId: leadingId,
                                                range: start..<start, lines: number...number))
                        open.append(headings.count - 1)
                    }
                }
            }
            start = end
        }
        close(above: 1, at: bytes.count, line: number)

        return Outline(index: read.index, reference: read.reference, size: read.size, parsed: bytes.count,
                       total: total, ambiguous: !words.isEmpty && total > 1,
                       truncated: Truncation(input: bytes.count < read.size, headings: total > headings.count, text: textCut),
                       headings: headings)
    }

    /// An ATX heading's level and text: up to three spaces, one to six `#`, then a space, a tab or
    /// the end of the line; its closing `#`s, after a space, are not its text.
    static func heading(_ line: String) -> (level: Int, text: String)? {
        var rest = Substring(line.hasSuffix("\r") ? String(line.dropLast()) : line)
        let indent = rest.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        rest = rest.dropFirst(indent)
        let level = rest.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        rest = rest.dropFirst(level)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        if text.allSatisfy({ $0 == "#" }) { return (level, "") }
        if let closing = text.range(of: #"[ \t]+#+$"#, options: .regularExpression) {
            text = String(text[..<closing.lowerBound])
        }
        return (level, text)
    }

    /// An ID at the start of a heading's text, after any `*`, `_`, `[`, `(` or backtick: up to ten
    /// letters, an optional `-`, then digits, maybe joined by `.` or `-` to more (`R1`, `P0`, `F-3`,
    /// `2.1`), and then no letter or digit. `R10` is not `R1`, and `R1a` has none.
    static let leading = try! NSRegularExpression(pattern: #"^[*_\[(`]*((?>[A-Za-z]{0,10}-?\d+(?:[.-]\d+)*))(?![A-Za-z0-9])"#)
    static let wholeId = try! NSRegularExpression(pattern: #"^(?>[A-Za-z]{0,10}-?\d+(?:[.-]\d+)*)$"#)

    static func leadingId(_ text: String) -> String? {
        let ns = text as NSString
        guard let match = leading.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// Whether a term selects a heading: one in the form of an ID only a heading with that whole
    /// leading ID, in any case; any other one a heading whose text contains it, as `find` matches words.
    static func matches(_ term: String, text: String, leadingId: String?) -> Bool {
        if wholeId.firstMatch(in: term, range: NSRange(location: 0, length: (term as NSString).length)) != nil {
            return leadingId?.caseInsensitiveCompare(term) == .orderedSame
        }
        return Search.has(Search.form(text), Search.form(term))
    }

    /// `outline`'s answer.
    public struct Outline: Codable, Sendable {
        public var index: Index
        public var reference: Reference
        /// The version's size in bytes.
        public var size: Int
        /// The bytes from the start whose headings were read: all of them, unless `truncated.input`.
        public var parsed: Int
        /// How many headings matched, listed or not.
        public var total: Int
        /// True when terms were given and more than one heading matched: each is listed, and none
        /// was picked.
        public var ambiguous: Bool
        public var truncated: Truncation
        /// In the order of the text.
        public var headings: [Heading]
    }

    /// What an outline left out, each true when it did.
    public struct Truncation: Codable, Equatable, Sendable {
        /// The version is longer than `outlineInput` bytes, so only the headings in `parsed` are listed.
        public var input: Bool
        /// More headings matched than `limit`.
        public var headings: Bool
        /// A heading's text was longer than `headingText` characters, and is given cut.
        public var text: Bool
    }

    /// A heading of a version, with where its section is: from the heading to the next heading of
    /// its level or above, or the end of what was read.
    public struct Heading: Codable, Equatable, Sendable {
        /// 1 to 6, the number of `#`.
        public var level: Int
        /// The heading's text, without its `#`s: stored text, to be read as data.
        public var text: String
        /// The ID its text starts with, such as `R1`; nil, written as null, when there is none.
        public var leadingId: String?
        /// The section's bytes, the end not included, as `read --bytes` takes them.
        public var range: Range<Int>
        /// The section's lines, counted from 1, as `read --lines` takes them.
        public var lines: ClosedRange<Int>

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(level, forKey: .level)
            try container.encode(text, forKey: .text)
            try container.encode(leadingId, forKey: .leadingId)
            try container.encode(range, forKey: .range)
            try container.encode(lines, forKey: .lines)
        }
    }
}
