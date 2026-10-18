import Foundation

public enum Provider: String, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case codex

    /// The agent's name, as the app and the query core say it.
    public var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

public struct SessionInfo: Sendable {
    public var provider: Provider
    public var id: String
    public var title: String?
    public var cwd: String?
    public var logPath: String
    /// The provider the agent sent its requests to, as its log names it: Codex records one per
    /// session (`openai`, or another configured provider such as a local gateway). Nil when the
    /// log doesn't say.
    public var modelProvider: String? = nil
}

/// One record's worth of reply text. A reply can span several records; each keeps its own
/// position, time, and working directory so a mention is attributed to the record that made it.
public struct ReplyPart: Sendable {
    public var text: String
    /// 1-based line in the log file.
    public var line: Int
    public var at: Date?
    public var cwd: String?
}

/// One user-facing reply and the request it answers.
public struct Turn: Sendable {
    /// The most recent human request in the session when this reply was written.
    public var request: String?
    public var parts: [ReplyPart]
    /// The model that wrote the reply, as the log records it: Claude Code the model the provider
    /// answered with, Codex the model the turn asked for. Nil when the log doesn't say.
    public var model: String? = nil

    public var reply: String { parts.map(\.text).joined(separator: "\n\n") }
    public var deliveredAt: Date? { parts.last?.at }
    public var logLine: Int { parts.last?.line ?? 0 }
    public var cwd: String? { parts.last?.cwd }
}

public struct SessionLog: Sendable {
    public var session: SessionInfo
    /// The turns that ended in a final reply, the log's last turn included.
    public var turns: [Turn]
    /// Records read, of any type.
    public var records: Int
    /// Closed turns the assistant answered in, whether or not the answer ended in a final reply. A
    /// turn is closed once the log holds the next one; the last is still open: the session may be
    /// running, the text it ends on may yet be followed by a tool call, or it ended on one. A turn
    /// the person interrupted was not answered.
    public var answeredTurns: Int
    /// The final replies of closed turns, interrupted ones included. Unlike the open last turn's,
    /// these stay as they are while the log grows.
    public var finalReplies: Int
    /// Record types the adapter does not recognize, with counts. Non-empty means the format moved.
    public var unknownRecordTypes: [String: Int]
    /// Keys the adapter does not know inside the record types it does, as "type.key", with counts.
    /// Non-empty means the format moved.
    public var unknownFields: [String: Int]
    /// Lines that are not JSON records. A log with any was not read completely: what was read
    /// stands, but it cannot show that a delivery is gone.
    public var malformedLines: Int

    public var isComplete: Bool { malformedLines == 0 }
    /// Records of a type the adapter knows.
    public var knownRecords: Int { records - unknownRecordTypes.values.reduce(0, +) }
}

enum JSONLines {
    struct File {
        var records: [(line: Int, object: [String: Any])]
        var malformed: Int
    }

    static func read(_ url: URL) throws -> File {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var records: [(Int, [String: Any])] = []
        var malformed = 0
        var line = 0
        for slice in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            line += 1
            if slice.isEmpty { continue }
            if let object = (try? JSONSerialization.jsonObject(with: Data(slice))) as? [String: Any] {
                records.append((line, object))
            } else {
                malformed += 1
            }
        }
        return File(records: records, malformed: malformed)
    }

    /// Counts the keys of `object` that `known` doesn't list, as "`name`.key".
    static func countUnknownKeys(of object: [String: Any], known: Set<String>, as name: String, into counts: inout [String: Int]) {
        for key in object.keys where !known.contains(key) { counts[name + "." + key, default: 0] += 1 }
    }
}

enum Timestamp {
    static func parse(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string))
            ?? (try? Date.ISO8601FormatStyle().parse(string))
    }
}

enum RequestText {
    static let maxLength = 2000

    /// Strips injected context and markup from a user request, keeping the words a person would search for.
    static func clean(_ text: String) -> String {
        var t = withoutAttachmentHeader(text)
        for tag in ["system-reminder", "local-command-stdout", "local-command-caveat"] {
            t = t.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: "<[^>\\n]+>", with: " ", options: .regularExpression)
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: entity, with: character)
        }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // Redact the whole request before cutting it, so a secret at the edge is still recognized.
        return String(Redactor.redact(t).prefix(maxLength))
    }

    /// Codex prefixes attached files as "# Files mentioned by the user: ## name: path … ## My
    /// request: …". The person's words follow "My request"; with none, the attachments stand in.
    static func withoutAttachmentHeader(_ raw: String) -> String {
        let marker = "## My request:"
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("# Files mentioned by the user:"), let range = text.range(of: marker) else { return text }
        let own = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        let names = text[..<range.lowerBound].split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("## "), let colon = line.range(of: ": /") else { return nil }
            return String(line[line.index(line.startIndex, offsetBy: 3)..<colon.lowerBound])
        }
        return names.isEmpty ? "" : "Attached " + names.joined(separator: ", ")
    }
}
