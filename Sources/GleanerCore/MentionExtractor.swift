import Foundation

/// A local path named in a final reply.
public struct Mention: Sendable, Hashable {
    public enum Syntax: String, Sendable {
        case link, image, code, bare
    }

    public var syntax: Syntax
    /// The target exactly as written.
    public var rawTarget: String
    /// Absolute, standardized path.
    public var path: String
    /// Line anchor or fragment stripped from the target (`:42`, `#L10`).
    public var anchor: String?
    /// The reply line that contains the mention.
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
    static let fence = try! NSRegularExpression(pattern: #"(?m)^\s*(```|~~~)[\s\S]*?^\s*\1"#)
    static let barePath = try! NSRegularExpression(
        pattern: #"(?<![\w./~\-:])~?/(?!/)[^\s`<>"'()\[\]，。；、！？：（）「」]+/[^\s`<>"'()\[\]，。；、！？：（）「」]+"#)
    static let lineAnchor = try! NSRegularExpression(pattern: #":\d+(?::\d+)?(?:-\d+)?$"#)
    static let fileExtension = try! NSRegularExpression(pattern: #"\.[A-Za-z][A-Za-z0-9]{0,7}$"#)
    static let ignoredSchemes = ["mailto:", "sandbox:", "data:", "javascript:", "tel:", "about:"]

    /// Candidates in a whole reply: one per path, in order of first mention, each keeping every
    /// occurrence with the record it came from.
    public static func candidates(in turn: Turn) -> [DeliveryCandidate] {
        var order: [String] = []
        var evidence: [String: [(part: ReplyPart, mention: Mention)]] = [:]
        for part in turn.parts {
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
        let fences = fence.matches(in: text, range: all).map(\.range)
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
        return ((target as NSString).standardizingPath, anchor)
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

    static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        outer.location <= inner.location && NSMaxRange(outer) >= NSMaxRange(inner)
    }

    static func overlaps(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    static func excerpt(_ text: NSString, around range: NSRange, limit: Int = 400) -> String {
        let line = text.lineRange(for: range)
        var window = line
        if line.length > limit {
            let start = max(line.location, range.location - limit / 2)
            let end = min(NSMaxRange(line), start + limit)
            window = NSRange(location: start, length: end - start)
        }
        return text.substring(with: window).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
