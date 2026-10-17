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

    public static func sessionFiles(root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") }
    }

    /// Returns nil for sub-agent threads: their replies go to another agent, not the user.
    public func parse(_ url: URL) throws -> SessionLog? {
        let file = try JSONLines.read(url)
        var unknown: [String: Int] = file.malformed > 0 ? ["<malformed>": file.malformed] : [:]
        var meta: [String: Any]?
        var cwd: String?
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
            case "response_item" where payload["type"] as? String == "message":
                if (record["metadata"] as? [String: Any])?["inherited_user_message"] as? Bool == true { continue }
                let content = payload["content"] as? [[String: Any]] ?? []
                switch payload["role"] as? String {
                case "user":
                    if let text = Self.userText(payload, content: content) { request = RequestText.clean(text) }
                case "assistant" where payload["phase"] as? String == "final_answer":
                    let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    turns.append(Turn(
                        request: request, reply: text, deliveredAt: Timestamp.parse(record["timestamp"]),
                        cwd: cwd, logLine: line))
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
                cwd: meta?["cwd"] as? String, logPath: url.path),
            turns: turns,
            unknownRecordTypes: unknown)
    }

    /// The typed text of a user message. Injected context (AGENTS.md, environment, goals) is
    /// tagged in `content_item_kinds` and excluded; a message without that tagging is not trusted.
    static func userText(_ payload: [String: Any], content: [[String: Any]]) -> String? {
        let metadata = payload["internal_chat_message_metadata_passthrough"] as? [String: Any]
        guard let kinds = metadata?["content_item_kinds"] as? [String], kinds.count == content.count else { return nil }
        let texts = zip(kinds, content).compactMap { kind, item in
            kind == "user.text" ? item["text"] as? String : nil
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }
}
