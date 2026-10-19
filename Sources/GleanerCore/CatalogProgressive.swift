import Foundation

/// Progressive queries over the same organization and verified version bytes as the app. Sections
/// are derived views of a selected document, never new deliveries or assertions about its findings.
extension Catalog {
    public static let pageLimit = 1_000
    public static let outlineByteLimit = 4 << 20
    public static let sectionByteLimit = 1 << 20

    static func validatePage(limit: Int, offset: Int) throws {
        guard (1...pageLimit).contains(limit), offset >= 0 else {
            throw Failure.usage("The limit must be between 1 and \(pageLimit), and the offset at least 0.")
        }
    }

    static func requireGeneration(_ expected: Int?, in index: Index) throws {
        if let expected, expected != index.generation {
            throw Failure.staleIndex(expected: expected, found: index.generation)
        }
    }

    /// Projects exactly as the app organizes them, including user-created empty projects. Keys
    /// identify projects in this library; names, folders and checkouts are separately described.
    /// `generation` detects a completed reindex between calls, not a frozen database snapshot.
    public func projects(limit: Int = 20, offset: Int = 0, generation: Int? = nil) throws -> ProjectList {
        try Self.validatePage(limit: limit, offset: offset)
        let index = try registry.index()
        try Self.requireGeneration(generation, in: index)
        let organization = try organize(try shown().artifacts)
        let results = organization.projects.dropFirst(offset).prefix(limit).map { project in
            let files = project.works.flatMap(\.files)
            let origin: ProjectSummary.Origin = switch project.origin {
            case .repository: .repository
            case .folder: .folder
            case .yours: .yours
            }
            return ProjectSummary(key: project.key, name: project.name, folder: project.folder,
                                  origin: origin, works: project.works.count, files: files.count,
                                  deliveries: files.reduce(0) { $0 + $1.deliveries.count },
                                  checkouts: Array(Set(files.compactMap { $0.checkout?.folder })).sorted())
        }
        let total = organization.projects.count
        return ProjectList(index: index, total: total, offset: offset,
                           nextOffset: offset < total && results.count < total - offset ? offset + results.count : nil,
                           results: Array(results))
    }

    /// Markdown-style headings of one exact captured text version, in document order. Terms
    /// filter heading titles, not other documents or inferred findings. The entire document must
    /// fit the parsing bound: an incomplete parse never masquerades as an empty/full outline.
    public func outline(_ id: String, terms: [String] = [], limit: Int = 20, offset: Int = 0) throws -> Outline {
        try Self.validatePage(limit: limit, offset: offset)
        let (document, sections) = try documentSections(id)
        let tokens = Search.tokens(terms.joined(separator: " "))
        let matched = sections.filter { section in
            let title = Search.form(section.title)
            return tokens.allSatisfy { title.contains(Search.form($0)) }
        }
        let page = Array(matched.dropFirst(offset).prefix(limit))
        return Outline(index: document.index, reference: document.reference, format: "markdown_headings",
                       size: document.size, total: matched.count, offset: offset,
                       nextOffset: offset < matched.count && page.count < matched.count - offset ? offset + page.count : nil,
                       sections: page)
    }

    /// Read a section identified by `outline`, including its heading and nested subsections.
    /// Its anchor is bound to the library, delivery, hash and exact source byte range. A matching
    /// title such as R1 in another report, or another revision, cannot substitute its bytes.
    public func readSection(_ id: String, section: String, max: Int = 16 << 10) throws -> SectionText {
        guard (1...Self.sectionByteLimit).contains(max) else {
            throw Failure.usage("The most to read must be between 1 and \(Self.sectionByteLimit) bytes.")
        }
        let (document, sections) = try documentSections(id)
        guard let selected = sections.first(where: { $0.id == section }) else { throw Failure.sectionNotFound(section) }
        let bytes = Array(document.text.utf8)
        let start = selected.range.lowerBound
        var end = start + Swift.min(max, selected.range.count)
        while end > start, end < bytes.count, bytes[end] & 0xC0 == 0x80 { end -= 1 }
        return SectionText(index: document.index, reference: document.reference, section: selected,
                           text: String(decoding: bytes[start..<end], as: UTF8.self), range: start..<end,
                           size: document.size, truncated: end < selected.range.upperBound)
    }

    private func documentSections(_ id: String) throws -> (Text, [Section]) {
        let document = try read(id, max: Self.outlineByteLimit + 1)
        guard !document.truncated, document.size <= Self.outlineByteLimit else {
            throw Failure.usage("Outline supports text documents up to \(Self.outlineByteLimit) bytes. Use read with explicit ranges for this version.")
        }
        let headings = DocumentHeadings.parse(document.text)
        let sections = try headings.map { heading in
            // A typed, length-preserving encoding, not concatenated unescaped fields. This is an
            // opaque ID, never interpreted as a path, a command, a link or an instruction.
            let anchor = SectionAnchor(library: document.reference.library, delivery: id,
                                       sha256: document.reference.sha256, range: heading.range)
            let token = "section:v1:" + (try Self.encoder.encode(anchor)).base64EncodedString()
            return Section(id: token, title: heading.title, level: heading.level, range: heading.range)
        }
        return (document, sections)
    }

    private struct SectionAnchor: Encodable {
        var library: String
        var delivery: String
        var sha256: String?
        var range: Range<Int>
    }

    public struct ProjectSummary: Codable, Sendable {
        public enum Origin: String, Codable, Sendable { case repository, folder, yours }
        public var key: String
        public var name: String
        public var folder: String?
        public var origin: Origin
        public var works: Int
        public var files: Int
        public var deliveries: Int
        public var checkouts: [String]
    }

    public struct ProjectList: Codable, Sendable {
        public var index: Index
        public var total: Int
        public var offset: Int
        public var nextOffset: Int?
        public var results: [ProjectSummary]
    }

    public struct Section: Codable, Equatable, Sendable {
        public var id: String
        /// Source heading text, with the structural heading markers removed. Never a verdict.
        public var title: String
        public var level: Int
        /// UTF-8 source bytes, end excluded; includes descendants up to the next peer/ancestor.
        public var range: Range<Int>
    }

    public struct Outline: Codable, Sendable {
        public var index: Index
        public var reference: Reference
        public var format: String
        public var size: Int
        public var total: Int
        public var offset: Int
        public var nextOffset: Int?
        public var sections: [Section]
    }

    public struct SectionText: Codable, Sendable {
        public var index: Index
        public var reference: Reference
        public var section: Section
        public var text: String
        public var range: Range<Int>
        public var size: Int
        public var truncated: Bool
    }
}

/// A bounded source outline, intentionally smaller than a Markdown renderer. ATX and single-line
/// setext headings outside fenced/indented code are recognized. No HTML execution, frontmatter
/// interpretation, semantic rulings or cross-document links are inferred. Byte offsets preserve
/// CRLF and non-ASCII source text exactly.
enum DocumentHeadings {
    struct Heading {
        var title: String
        var level: Int
        var range: Range<Int>
    }

    static func parse(_ text: String) -> [Heading] {
        let bytes = Array(text.utf8)
        var headings: [Heading] = []
        var fence: (mark: UInt8, count: Int)?
        var previous: (text: String, start: Int)?
        var start = 0
        while start < bytes.count {
            let newline = bytes[start...].firstIndex(of: 10)
            let end = newline.map { $0 + 1 } ?? bytes.count
            var line = Array(bytes[start..<(newline ?? end)])
            if line.last == 13 { line.removeLast() }
            if start == 0, line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) }
            let spaces = line.prefix(while: { $0 == 32 }).count
            let content = Array(line.dropFirst(spaces))
            let mark = content.first
            let count = mark.map { m in content.prefix(while: { $0 == m }).count } ?? 0
            if let active = fence {
                if spaces <= 3, mark == active.mark, count >= active.count,
                   content.dropFirst(count).allSatisfy({ $0 == 32 || $0 == 9 }) { fence = nil }
                previous = nil
            } else if spaces <= 3, (mark == 96 || mark == 126), count >= 3 {
                fence = (mark!, count)
                previous = nil
            } else if spaces <= 3, mark == 35, count <= 6,
                      content.count == count || content[count] == 32 || content[count] == 9 {
                var title = String(decoding: content.dropFirst(count), as: UTF8.self).trimmingCharacters(in: .whitespaces)
                // An optional closing sequence needs whitespace before it. Literal hashes in a
                // title such as C# are retained.
                if let suffix = title.range(of: #"[ \t]+#+$"#, options: .regularExpression) {
                    title.removeSubrange(suffix)
                    title = title.trimmingCharacters(in: .whitespaces)
                }
                headings.append(Heading(title: title, level: count, range: start..<bytes.count))
                previous = nil
            } else if spaces <= 3, (mark == 61 || mark == 45), count >= 1,
                      content.dropFirst(count).allSatisfy({ $0 == 32 || $0 == 9 }), let prior = previous {
                headings.append(Heading(title: prior.text, level: mark == 61 ? 1 : 2, range: prior.start..<bytes.count))
                previous = nil
            } else {
                let title = String(decoding: content, as: UTF8.self).trimmingCharacters(in: .whitespaces)
                previous = spaces <= 3 && !title.isEmpty && mark != 9 && mark != 62 ? (title, start) : nil
            }
            start = end
        }
        // The stack closes each heading once, in linear time even for a very long report.
        var open: [Int] = []
        for i in headings.indices {
            while let last = open.last, headings[last].level >= headings[i].level {
                headings[last].range = headings[last].range.lowerBound..<headings[i].range.lowerBound
                open.removeLast()
            }
            open.append(i)
        }
        return headings
    }
}
