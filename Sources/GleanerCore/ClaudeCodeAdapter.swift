import Foundation

/// Reads Claude Code session logs (`~/.claude/projects/<project>/<session>.jsonl`).
///
/// Records hold one content block each. A turn starts at a user record that is neither a tool
/// result nor injected context; its final reply is the assistant text after the last tool call.
public enum ClaudeCodeAdapter {
    static let knownTypes: Set<String> = [
        "user", "assistant", "system", "attachment", "summary",
        "ai-title", "custom-title", "agent-name", "last-prompt", "queue-operation",
        "mode", "permission-mode", "bridge-session", "atis-latch", "frame-link",
        "file-history-snapshot", "file-history-delta", "relocated", "worktree-state",
        "cost-state", "artifact-autoreact-ledger", "artifact-comment-monitor",
    ]

    /// Session logs under `root`, excluding sub-agent transcripts. Throws when a folder cannot be
    /// listed, so an unreadable folder is never taken for an empty one.
    public static func sessionFiles(root: URL) throws -> [URL] {
        let fm = FileManager.default
        return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { Locator.stat($0.path).kind == .directory }
            .flatMap { project in
                try fm.contentsOfDirectory(at: project, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
            }
    }

    public static func parse(_ url: URL) throws -> SessionLog {
        let file = try JSONLines.read(url)
        var unknown: [String: Int] = file.malformed > 0 ? ["<malformed>": file.malformed] : [:]
        var sessionID = url.deletingPathExtension().lastPathComponent
        var customTitle: String?
        var aiTitle: String?
        var sessionCwd: String?
        var turns: [Turn] = []

        var request: String?
        var turnCwd: String?
        var reply: [ReplyPart] = []

        func closeTurn() {
            if !reply.isEmpty { turns.append(Turn(request: request, parts: reply)) }
            reply = []
        }

        for (line, record) in file.records {
            let type = record["type"] as? String ?? "<none>"
            guard knownTypes.contains(type) else {
                unknown[type, default: 0] += 1
                continue
            }
            if let id = record["sessionId"] as? String { sessionID = id }
            switch type {
            case "custom-title":
                customTitle = record["customTitle"] as? String ?? customTitle
            case "ai-title":
                aiTitle = record["aiTitle"] as? String ?? aiTitle
            case "user":
                guard record["isSidechain"] as? Bool != true,
                      let message = record["message"] as? [String: Any] else { continue }
                if let blocks = message["content"] as? [[String: Any]],
                   blocks.contains(where: { $0["type"] as? String == "tool_result" }) { continue }
                if record["isMeta"] as? Bool == true || record["isCompactSummary"] as? Bool == true { continue }

                closeTurn()
                if let cwd = record["cwd"] as? String {
                    sessionCwd = sessionCwd ?? cwd
                    turnCwd = cwd
                }
                let text = userText(message["content"])
                if isHumanRequest(record, text: text) { request = RequestText.clean(text) }
            case "assistant":
                guard record["isSidechain"] as? Bool != true,
                      let message = record["message"] as? [String: Any],
                      message["model"] as? String != "<synthetic>",
                      let blocks = message["content"] as? [[String: Any]] else { continue }
                // The agent may have moved into a worktree since the request; relative paths in
                // the reply are relative to where it is now.
                if let cwd = record["cwd"] as? String { turnCwd = cwd }
                for block in blocks {
                    switch block["type"] as? String {
                    case "tool_use":
                        reply = []
                    case "text":
                        if let text = block["text"] as? String,
                           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            reply.append(ReplyPart(
                                text: text, line: line, at: Timestamp.parse(record["timestamp"]),
                                cwd: turnCwd ?? sessionCwd))
                        }
                    default:
                        break
                    }
                }
            default:
                break
            }
        }
        closeTurn()

        return SessionLog(
            session: SessionInfo(
                provider: .claudeCode, id: sessionID, title: customTitle ?? aiTitle,
                cwd: sessionCwd, logPath: url.path),
            turns: turns,
            unknownRecordTypes: unknown)
    }

    static func userText(_ content: Any?) -> String {
        if let string = content as? String { return string }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
    }

    /// A turn can also be started by a task notification or an interruption; those answer the
    /// user but are not what the user asked for, so the previous request stays as context.
    static func isHumanRequest(_ record: [String: Any], text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("[Request interrupted") { return false }
        if let kind = (record["origin"] as? [String: Any])?["kind"] as? String {
            return kind == "human"
        }
        return !trimmed.hasPrefix("<task-notification") && !trimmed.hasPrefix("<local-command")
    }
}
