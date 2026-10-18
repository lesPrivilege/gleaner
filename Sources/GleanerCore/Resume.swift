import Foundation

/// How a person can go back to the conversation that delivered a file. Gleaner can't open a
/// conversation itself: each agent documents a command that resumes one by its id, run from the
/// folder the conversation started in (`claude --resume`, `codex resume`). Gleaner offers that
/// command to copy, only while the conversation's log and folder are there, and says why not
/// otherwise. A log file is not the conversation: showing it is never offered as opening it.
public enum Resume: Equatable, Sendable {
    case command(String)
    /// The agent pruned the conversation's log, so there is nothing to resume.
    case logGone
    /// The folder the conversation started in is gone.
    case folderGone(String)
    /// The log never said which folder the conversation started in.
    case folderUnknown
}

extension Delivery {
    /// `exists` says whether a path is there now: the log as a file, the folder as a folder.
    public func resume(exists: (String, LocatorState.Kind) -> Bool) -> Resume {
        guard exists(logPath, .file) else { return .logGone }
        guard let folder = sessionCwd else { return .folderUnknown }
        guard exists(folder, .directory) else { return .folderGone(folder) }
        let resume = switch provider {
        case .claudeCode: "claude --resume " + Locator.quoted(sessionID)
        case .codex: "codex resume " + Locator.quoted(sessionID)
        }
        return .command("cd " + Locator.quoted(folder) + " && " + resume)
    }
}
