import Foundation

/// Reads Codex rollout logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).
///
/// Final replies are assistant messages with `phase == "final_answer"`. Forked threads replay
/// their parent's messages marked `inherited_user_message`; those are skipped.
public struct CodexAdapter: Sendable {
    static let knownTypes: Set<String> = [
        "session_meta", "event_msg", "response_item", "turn_context", "world_state",
        "token_usage_record", "inter_agent_communication_metadata", "compacted",
    ]

    /// Thread titles by thread id, from `session_index.jsonl`.
    public var titles: [String: String]

    public init(titles: [String: String]) {
        self.titles = titles
    }

    public static func loadTitles(index: URL) -> [String: String] {
        guard let file = try? JSONLines.read(index) else { return [:] }
        var titles: [String: String] = [:]
        for (_, record) in file.records {
            if let id = record["id"] as? String, let name = record["thread_name"] as? String {
                titles[id] = name
            }
        }
        return titles
    }

    /// Rollout logs under `root`, and the folders under it that could not be listed, with the
    /// reason. Throws when `root` itself cannot be listed, so an unreadable folder is never taken
    /// for an empty one; a folder under it that can't be listed leaves the others read.
    public static func sessionFiles(root: URL) throws -> (logs: [URL], unlisted: [String]) {
        let fm = FileManager.default
        _ = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var unlisted: [String] = []
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: {
            unlisted.append("\($0.path): \($1.localizedDescription)")
            return true
        }) else { throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: root]) }
        let logs = walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") }
        return (logs, unlisted)
    }

    /// Returns nil for sub-agent threads: their replies go to another agent, not the user.
    public func parse(_ url: URL) throws -> SessionLog? {
        let file = try JSONLines.read(url)
        var unknown: [String: Int] = [:]
        var meta: [String: Any]?
        var cwd: String?
        var model: String?
        var request: String?
        var turns: [Turn] = []

        for (line, record) in file.records {
            let type = record["type"] as? String ?? "<none>"
            guard Self.knownTypes.contains(type) else {
                unknown[type, default: 0] += 1
                continue
            }
            let payload = record["payload"] as? [String: Any] ?? [:]
            switch type {
            case "session_meta" where meta == nil:
                if payload["thread_source"] as? String == "subagent" { return nil }
                meta = payload
                cwd = payload["cwd"] as? String
            case "turn_context":
                cwd = payload["cwd"] as? String ?? cwd
                // The model the turn asked for; through a gateway, as the gateway's catalog names it.
                model = payload["model"] as? String ?? model
            case "response_item" where payload["type"] as? String == "message":
                if (record["metadata"] as? [String: Any])?["inherited_user_message"] as? Bool == true { continue }
                let content = payload["content"] as? [[String: Any]] ?? []
                switch payload["role"] as? String {
                case "user":
                    if let text = Self.userText(payload, content: content) { request = RequestText.clean(text) }
                case "assistant" where payload["phase"] as? String == "final_answer":
                    let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    turns.append(Turn(request: request, parts: [ReplyPart(
                        text: text, line: line, at: Timestamp.parse(record["timestamp"]), cwd: cwd)], model: model))
                default:
                    break
                }
            default:
                break
            }
        }

        let id = meta?["id"] as? String ?? url.deletingPathExtension().lastPathComponent
        return SessionLog(
            session: SessionInfo(
                provider: .codex, id: id, title: titles[id],
                cwd: meta?["cwd"] as? String, logPath: url.path, modelProvider: meta?["model_provider"] as? String),
            turns: turns,
            unknownRecordTypes: unknown,
            malformedLines: file.malformed)
    }

    /// The typed text of a user message. Injected context (AGENTS.md, environment, goals) is
    /// tagged in `content_item_kinds` and excluded; a message without that tagging is not trusted.
    static func userText(_ payload: [String: Any], content: [[String: Any]]) -> String? {
        let metadata = payload["internal_chat_message_metadata_passthrough"] as? [String: Any]
        guard let kinds = metadata?["content_item_kinds"] as? [String], kinds.count == content.count else { return nil }
        let texts = zip(kinds, content).compactMap { kind, item in
            kind == "user.text" ? item["text"] as? String : nil
        }.filter { !isStructuredAnswer($0) }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    /// Answers to an agent's question prompt arrive as JSON in a user message. They reply to the
    /// agent rather than state what the user asked for, so the previous request stays as context.
    static func isStructuredAnswer(_ text: String) -> Bool {
        // The desktop app wraps the answer in a tag such as <send_user_message_question_reply>.
        let trimmed = text
            .replacingOccurrences(of: #"^\s*<[A-Za-z_]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"</[A-Za-z_]+>\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") || trimmed.hasPrefix("{") else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }
}
