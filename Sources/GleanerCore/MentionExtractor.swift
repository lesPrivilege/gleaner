import Foundation

/// A local path named in a final reply.
public struct Mention: Sendable, Hashable {
    public enum Syntax: String, Sendable {
        case link, image, code, bare
    }

    public var syntax: Syntax
    /// The target exactly as written.
    public var rawTarget: String
    /// Absolute, in Gleaner's one form (`Paths.standard`).
    public var path: String
    /// Line anchor or fragment stripped from the target (`:42`, `#L10`).
    public var anchor: String?
    /// The reply line that contains the mention, redacted and cut to about 400 characters around it.
    public var excerpt: String
}

/// One path named in a reply, with every place the reply names it.
public struct DeliveryCandidate: Sendable {
    public var path: String
    public var evidence: [(part: ReplyPart, mention: Mention)]
}

/// Finds candidate deliveries in a reply. It does not decide which are real deliveries; that is
/// what the labeled spike data is for.
public enum MentionExtractor {
    static let link = try! NSRegularExpression(pattern: #"(!?)\[((?:[^\[\]]|\[[^\]]*\])*)\]\(\s*(<[^>\n]+>|(?:[^()\s]|\([^()\s]*\))+)(?:\s+"[^"\n]*")?\s*\)"#)
    static let codeSpan = try! NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    static let barePath = try! NSRegularExpression(
        pattern: #"(?<![\w./~\-:])~?/(?!/)[^\s`<>"'()\[\]，。；、！？：（）「」]+/[^\s`<>"'()\[\]，。；、！？：（）「」]+"#)
    static let lineAnchor = try! NSRegularExpression(pattern: #":\d+(?::\d+)?(?:-\d+)?$"#)
    static let fileExtension = try! NSRegularExpression(pattern: #"\.[A-Za-z][A-Za-z0-9]{0,7}$"#)
    static let ignoredSchemes = ["mailto:", "sandbox:", "data:", "javascript:", "tel:", "about:"]

    /// Candidates in a whole reply: one per path, in order of first mention, each keeping every
    /// occurrence with the record it came from. That record's working folder, which relative paths
    /// resolve against, takes the paths' form, so the two compare as they are.
    public static func candidates(in turn: Turn) -> [DeliveryCandidate] {
        var order: [String] = []
        var evidence: [String: [(part: ReplyPart, mention: Mention)]] = [:]
        for var part in turn.parts {
            part.cwd = part.cwd.map(Paths.standard)
            for mention in extract(from: part.text, cwd: part.cwd) {
                if evidence[mention.path] == nil { order.append(mention.path) }
                evidence[mention.path, default: []].append((part, mention))
            }
        }
        return order.map { DeliveryCandidate(path: $0, evidence: evidence[$0]!) }
    }

    public static func extract(from text: String, cwd: String?) -> [Mention] {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        var covered: [NSRange] = []
        var found: [(location: Int, mention: Mention)] = []

        func add(_ syntax: Mention.Syntax, raw: String, at range: NSRange) {
            guard let (path, anchor) = normalize(raw, cwd: cwd) else { return }
            found.append((range.location, Mention(
                syntax: syntax, rawTarget: raw, path: path, anchor: anchor,
                excerpt: excerpt(ns, around: range))))
        }

        // Code examples first: a link inside a fence, or written inside inline code, is an example.
        let fences = Self.fences(in: ns)
        let spans = codeSpan.matches(in: text, range: all).map(\.range).filter { !overlaps($0, fences) }
        for match in link.matches(in: text, range: all) where !overlaps(match.range, fences) {
            covered.append(match.range)
            if spans.contains(where: { contains($0, match.range) }) { continue }
            let syntax: Mention.Syntax = match.range(at: 1).length > 0 ? .image : .link
            add(syntax, raw: ns.substring(with: match.range(at: 3)), at: match.range)
        }
        for match in codeSpan.matches(in: text, range: all)
        where !overlaps(match.range, covered) && !overlaps(match.range, fences) {
            covered.append(match.range)
            let raw = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if looksLikePath(raw) { add(.code, raw: raw, at: match.range) }
        }
        for match in barePath.matches(in: text, range: all)
        where !overlaps(match.range, covered) && !overlaps(match.range, fences) {
            let raw = ns.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            add(.bare, raw: raw, at: match.range)
        }

        return found.sorted { $0.location < $1.location }.map(\.mention)
    }

    /// Resolves a written target to an absolute path, or nil when it is not a local path.
    static func normalize(_ raw: String, cwd: String?) -> (path: String, anchor: String?)? {
        var target = raw.trimmingCharacters(in: .whitespaces)
        if target.hasPrefix("<"), target.hasSuffix(">") { target = String(target.dropFirst().dropLast()) }
        if target.lowercased().hasPrefix("file://") {
            target = String(target.dropFirst("file://".count))
            if target.lowercased().hasPrefix("localhost/") { target = String(target.dropFirst("localhost".count)) }
            guard target.hasPrefix("/") else { return nil }
        } else if target.contains("://") || target.hasPrefix("#")
                    || ignoredSchemes.contains(where: { target.lowercased().hasPrefix($0) }) {
            return nil
        }
        // Split the fragment before decoding, so an encoded `%23` stays part of the file name.
        var anchor: String?
        if let hash = target.firstIndex(of: "#") {
            anchor = String(target[hash...])
            target = String(target[..<hash])
        }
        target = target.removingPercentEncoding ?? target
        let ns = target as NSString
        if let match = lineAnchor.firstMatch(in: target, range: NSRange(location: 0, length: ns.length)) {
            anchor = anchor ?? ns.substring(with: match.range)
            target = ns.substring(to: match.range.location)
        }
        guard !target.isEmpty else { return nil }

        if target.hasPrefix("~") {
            target = (target as NSString).expandingTildeInPath
        } else if !target.hasPrefix("/") {
            guard let cwd else { return nil }
            target = (cwd as NSString).appendingPathComponent(target)
        }
        // `~name` for an account this Mac doesn't have stays as written: not a local path.
        guard target.hasPrefix("/") else { return nil }
        return (Paths.standard(target), anchor)
    }

    /// Inline code is mostly identifiers and commands; keep spans that read as paths.
    static func looksLikePath(_ span: String) -> Bool {
        if span.contains("://") && !span.hasPrefix("file://") { return false }
        if span.hasPrefix("./") || span.hasPrefix("../") { return true }
        // `/goal` is a slash command; an absolute path has at least two components.
        if span.hasPrefix("/") || span.hasPrefix("~/") { return span.dropFirst().contains("/") }
        if span.contains(" ") { return false }
        var last = (span as NSString).lastPathComponent as NSString
        if let match = lineAnchor.firstMatch(in: last as String, range: NSRange(location: 0, length: last.length)) {
            last = last.substring(to: match.range.location) as NSString
        }
        return fileExtension.firstMatch(in: last as String, range: NSRange(location: 0, length: last.length)) != nil
    }

    /// Fenced code blocks as CommonMark reads them: a line of three or more backticks or tildes
    /// opens one, and only a line of the same character at least as long, with nothing after it,
    /// closes it. An unclosed fence runs to the end of the reply. Indentation is not limited to
    /// three spaces, because a fence inside a list item is indented from the item, not the margin.
    static func fences(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var open: (start: Int, mark: Character, length: Int)?
        var location = 0
        while location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(line)
            let trimmed = text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let mark = trimmed.first, mark == "`" || mark == "~" else { continue }
            let length = trimmed.prefix { $0 == mark }.count
            guard length >= 3 else { continue }
            let rest = trimmed.dropFirst(length)
            if let fence = open {
                if mark == fence.mark, length >= fence.length, rest.isEmpty {
                    ranges.append(NSRange(location: fence.start, length: location - fence.start))
                    open = nil
                }
            } else if mark == "~" || !rest.contains("`") {
                // Backticks after a backtick run make it inline code, not a fence.
                open = (line.location, mark, length)
            }
        }
        if let fence = open { ranges.append(NSRange(location: fence.start, length: text.length - fence.start)) }
        return ranges
    }

    static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        outer.location <= inner.location && NSMaxRange(outer) >= NSMaxRange(inner)
    }

    static func overlaps(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    /// The reply line around `range`, redacted and then cut to about `limit` characters (SPEC §11).
    /// Redacting the whole line first recognizes a secret by what precedes it ("Bearer",
    /// "token =") even when the cut leaves that out.
    static func excerpt(_ text: NSString, around range: NSRange, limit: Int = 400) -> String {
        let line = text.lineRange(for: range)
        let redacted = Redactor.redact(text.substring(with: line)) as NSString
        var window = NSRange(location: 0, length: redacted.length)
        if redacted.length > limit {
            // Where the mention starts once what precedes it on the line is redacted.
            let before = text.substring(with: NSRange(location: line.location, length: range.location - line.location))
            var start = max(0, (Redactor.redact(before) as NSString).length - limit / 2)
            var end = min(redacted.length, start + limit)
            // Cut only at whitespace, so no word is split.
            let space = CharacterSet.whitespaces
            while start > 0, let c = Unicode.Scalar(redacted.character(at: start - 1)), !space.contains(c) { start -= 1 }
            while end < redacted.length, let c = Unicode.Scalar(redacted.character(at: end)), !space.contains(c) { end += 1 }
            window = NSRange(location: start, length: end - start)
        }
        return redacted.substring(with: window).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
