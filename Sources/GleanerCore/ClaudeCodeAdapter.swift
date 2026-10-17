import Foundation

/// Reads Claude Code session logs (`~/.claude/projects/<project>/<session>.jsonl`).
///
/// Records hold one content block each. A turn starts at a user record that is neither a tool
/// result nor injected context; its final reply is the assistant text after the last tool call.
public enum ClaudeCodeAdapter {
    /// The record types Claude Code writes, each with the keys it writes in them. A key outside
    /// its type's set is an unknown field: the format moved.
    static let knownKeys: [String: Set<String>] = {
        // Keys of every transcript entry.
        let entry: Set<String> = [
            "type", "uuid", "parentUuid", "sessionId", "session_id", "sessionKind", "timestamp", "cwd",
            "entrypoint", "gitBranch", "isSidechain", "userType", "version", "slug",
        ]
        return [
            "user": entry.union([
                "message", "origin", "isMeta", "isCompactSummary", "isVisibleInTranscriptOnly", "toolUseResult",
                "sourceToolAssistantUUID", "sourceToolUseID", "promptId", "promptSource", "permissionMode",
                "permissionDecision", "imagePasteIds", "interruptedByShutdown", "mcpMeta", "classifierBoundary",
                "classifierMetaLines", "queueSkipAttachments", "queueSkipSlashCommands", "queueTranscriptOnly",
                "serverClassifierContext", "summarizedTurnPromptUuids", "toolDenialKind", "turnCompanion",
                "turnOrigin", "turnPosition", "usageLimitNote",
            ]),
            "assistant": entry.union([
                "message", "requestId", "advisorModel", "apiBlockIndex", "apiError", "apiErrorParams",
                "apiErrorStatus", "attributionMcpServer", "attributionMcpTool", "attributionPlugin",
                "attributionSkill", "effort", "error", "errorDetails", "isApiErrorMessage", "perTurnEffort",
                "quotaLimits", "requestedModel", "serverClassifierRequest", "supersedesUuids", "thinkingDisplay",
                "thinkingDurationMs", "truncatedAfterOutput", "wireIngestContext", "wireToolInputs",
            ]),
            "system": entry.union([
                "subtype", "level", "content", "isMeta", "error", "apiRefusalCategory", "apiRefusalExplanation",
                "commandRun", "compactMetadata", "direction", "durationMs", "fallbackModel", "hasOutput",
                "hookAdditionalContext", "hookCount", "hookErrors", "hookInfos", "logicalParentUuid", "maxRetries",
                "messageCount", "neutralizedByFork", "originalModel", "preventedContinuation",
                "refusedUserMessageUuid", "requestId", "retractedMessageUuids", "retryAttempt", "retryInMs",
                "source", "stopReason", "toolUseID", "trigger",
            ]),
            "attachment": entry.union([
                "attachment", "rendered", "renderedBesideToolResult", "renderedInHumanTurn", "renderedRole",
            ]),
            "summary": ["type", "summary", "leafUuid"],
            "ai-title": ["type", "sessionId", "aiTitle"],
            "custom-title": ["type", "sessionId", "customTitle"],
            "agent-name": ["type", "sessionId", "agentName"],
            "last-prompt": ["type", "sessionId", "lastPrompt", "leafUuid"],
            "queue-operation": ["type", "sessionId", "timestamp", "operation", "content", "commandUuid", "deliveryId", "reason"],
            "mode": ["type", "sessionId", "mode"],
            "permission-mode": ["type", "sessionId", "permissionMode"],
            "bridge-session": ["type", "sessionId", "bridgeSessionId", "lastSequenceNum", "ownerAccountUuid", "ownerOrganizationUuid"],
            "atis-latch": ["type", "sessionId", "atis"],
            "frame-link": ["type", "sessionId", "timestamp", "artifactCount", "frameUrl", "path", "title"],
            "file-history-snapshot": ["type", "messageId", "snapshot", "isSnapshotUpdate"],
            "file-history-delta": ["type", "messageId", "snapshotMessageId", "timestamp", "trackingPath", "backup"],
            "relocated": ["type", "sessionId", "relocatedCwd"],
            "worktree-state": ["type", "sessionId", "worktreeSession"],
            "cost-state": [
                "type", "sessionId", "startTime", "modelUsage", "hasUnknownModelCost", "totalCostUSD", "totalDuration",
                "totalAPIDuration", "totalAPIDurationWithoutRetries", "totalToolDuration", "totalLinesAdded",
                "totalLinesRemoved",
            ],
            "artifact-autoreact-ledger": ["type", "sessionId", "v", "accountUuid", "artifacts"],
            "artifact-comment-monitor": ["type", "sessionId", "v", "artifacts"],
        ]
    }()

    /// Session logs under `root`, excluding sub-agent transcripts, and the project folders that
    /// could not be listed, with the reason. Throws when `root` itself cannot be listed, so an
    /// unreadable folder is never taken for an empty one; one project folder that can't be listed
    /// leaves the others read.
    public static func sessionFiles(root: URL) throws -> (logs: [URL], unlisted: [String]) {
        let fm = FileManager.default
        var logs: [URL] = [], unlisted: [String] = []
        for project in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        where Locator.stat(project.path).kind == .directory {
            do {
                logs += try fm.contentsOfDirectory(at: project, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
            } catch {
                unlisted.append("\(project.path): \(error.localizedDescription)")
            }
        }
        return (logs, unlisted)
    }

    public static func parse(_ url: URL) throws -> SessionLog {
        let file = try JSONLines.read(url)
        var unknown: [String: Int] = [:]
        var unknownFields: [String: Int] = [:]
        var sessionID = url.deletingPathExtension().lastPathComponent
        var customTitle: String?
        var aiTitle: String?
        var sessionCwd: String?
        var turns: [Turn] = []
        var answeredTurns = 0

        var request: String?
        var turnCwd: String?
        var reply: [ReplyPart] = []
        var answered = false

        func closeTurn() {
            if !reply.isEmpty { turns.append(Turn(request: request, parts: reply)) }
            reply = []
            answered = false
        }

        for (line, record) in file.records {
            let type = record["type"] as? String ?? "<none>"
            guard let known = knownKeys[type] else {
                unknown[type, default: 0] += 1
                continue
            }
            JSONLines.countUnknownKeys(of: record, known: known, as: type, into: &unknownFields)
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
                if !answered {
                    answeredTurns += 1
                    answered = true
                }
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
            records: file.records.count, answeredTurns: answeredTurns,
            unknownRecordTypes: unknown, unknownFields: unknownFields,
            malformedLines: file.malformed)
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
