import Foundation

/// Reads Codex rollout logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).
///
/// Final replies are assistant messages with `phase == "final_answer"`. Forked threads replay
/// their parent's messages marked `inherited_user_message`; those are skipped. Each turn starts
/// with a `turn_context`; one the person interrupted holds a `turn_aborted` event.
public struct CodexAdapter: Sendable {
    /// The keys of every record. Its content is in its payload.
    static let recordKeys: Set<String> = ["timestamp", "type", "ordinal", "payload", "metadata"]

    /// The record types Codex writes, each with the keys it writes in their payloads, whatever the
    /// payload's own type. A key outside these sets is an unknown field: the format moved.
    static let payloadKeys: [String: Set<String>] = [
        "session_meta": [
            "id", "session_id", "timestamp", "cwd", "originator", "cli_version", "source", "thread_source",
            "model_provider", "base_instructions", "context_window", "creator_account_id", "creator_user_id",
            "git", "history_mode", "runtime_workspace_roots", "forked_from_id", "parent_thread_id",
            "agent_nickname", "agent_path", "agent_role", "multi_agent_version", "subagent_history_start_ordinal",
        ],
        "turn_context": [
            "turn_id", "root_turn_id", "cwd", "workspace_roots", "model", "effort", "summary", "personality",
            "approval_policy", "approvals_reviewer", "sandbox_policy", "permission_profile",
            "active_permission_profile", "collaboration_mode", "comp_hash", "current_date", "timezone",
            "cyber_access_program", "disabled_plugin_ids", "multi_agent_version", "realtime_active",
        ],
        "response_item": [
            "type", "id", "role", "phase", "content", "status", "internal_chat_message_metadata_passthrough",
            "author", "recipient", "name", "namespace", "call_id", "arguments", "input", "output",
            "summary", "encrypted_content",
        ],
        "event_msg": [
            "type", "turn_id", "root_turn_id", "thread_id", "threadId", "started_at", "started_at_ms",
            "completed_at", "completed_at_ms", "duration_ms", "time_to_first_token_ms", "item",
            "last_agent_message", "error", "reason", "collaboration_mode_kind", "model_context_window",
            "turn_attribution", "goal", "thread_settings", "info", "rate_limits",
        ],
        "world_state": ["state", "full"],
        "token_usage_record": [
            "session_id", "thread_id", "turn_id", "root_turn_id", "response_id", "usage", "turn_token_usage",
            "thread_token_usage",
        ],
        "inter_agent_communication_metadata": ["trigger_turn"],
        "compacted": [
            "message", "replacement_history", "replacement_history_metadata", "retained_context",
            "resume_metadata", "latest_token_usage_record", "compaction_response_id", "window_id",
            "window_number", "first_window_id", "previous_window_id",
        ],
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
        var unknownFields: [String: Int] = [:]
        var meta: [String: Any]?
        var cwd: String?
        var model: String?
        var request: String?
        var turns: [Turn] = []
        var answeredTurns = 0
        var finalReplies = 0
        var answered = false
        var aborted = false
        var replies = 0

        /// Counts the turn the next turn's context closes: answered, unless it was aborted (the
        /// person interrupted it), and its final answers. The log's last turn is still open and
        /// isn't counted: the thread may be running, or it ended on a tool call.
        func closeTurn() {
            if answered, !aborted { answeredTurns += 1 }
            finalReplies += replies
            answered = false
            aborted = false
            replies = 0
        }

        for (line, record) in file.records {
            let type = record["type"] as? String ?? "<none>"
            guard let known = Self.payloadKeys[type] else {
                unknown[type, default: 0] += 1
                continue
            }
            let payload = record["payload"] as? [String: Any] ?? [:]
            JSONLines.countUnknownKeys(of: record, known: Self.recordKeys, as: type, into: &unknownFields)
            JSONLines.countUnknownKeys(of: payload, known: known, as: type + ".payload", into: &unknownFields)
            switch type {
            case "session_meta" where meta == nil:
                if payload["thread_source"] as? String == "subagent" { return nil }
                meta = payload
                cwd = payload["cwd"] as? String
            case "turn_context":
                // Codex starts each turn with one.
                cwd = payload["cwd"] as? String ?? cwd
                // The model the turn asked for; through a gateway, as the gateway's catalog names it.
                model = payload["model"] as? String ?? model
                closeTurn()
            case "response_item" where payload["type"] as? String == "message":
                if (record["metadata"] as? [String: Any])?["inherited_user_message"] as? Bool == true { continue }
                let content = payload["content"] as? [[String: Any]] ?? []
                switch payload["role"] as? String {
                case "user":
                    if let text = Self.userText(payload, content: content) { request = RequestText.clean(text) }
                case "assistant":
                    answered = true
                    guard payload["phase"] as? String == "final_answer" else { continue }
                    let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    turns.append(Turn(request: request, parts: [ReplyPart(
                        text: text, line: line, at: Timestamp.parse(record["timestamp"]), cwd: cwd)], model: model))
                    replies += 1
                default:
                    break
                }
            case "event_msg" where payload["type"] as? String == "turn_aborted":
                // The person interrupted the turn: what the assistant wrote in it is not an answer.
                aborted = true
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
            records: file.records.count, answeredTurns: answeredTurns, finalReplies: finalReplies,
            unknownRecordTypes: unknown, unknownFields: unknownFields,
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
