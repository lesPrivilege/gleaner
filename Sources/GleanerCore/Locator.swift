import CryptoKit
import Foundation

public enum GitState: String, Sendable {
    case committed
    case modified
    case untracked
    case ignored
    case notInRepo = "not_in_repo"
    /// The file is gone from disk but HEAD still has it.
    case recoverableFromHead = "recoverable_from_head"
    /// The file is gone and not in HEAD, but some commit on some ref has it.
    case recoverableFromHistory = "recoverable_from_history"
    /// The file is gone and no commit has it.
    case lost
}

public struct LocatorState: Sendable {
    public enum Kind: String, Sendable {
        /// `special` is anything that is neither a regular file nor a directory (FIFO, socket,
        /// device). It is never opened: reading a FIFO blocks forever.
        case file, directory, special, missing
    }

    public var kind: Kind
    public var size: Int64?
    public var modifiedAt: Date?
    public var sha256: String?
    public var repositoryRoot: String?
    public var git: GitState
    /// For a missing file git still has: a command the person can run to restore it from a commit
    /// checked to hold it, quoted for any POSIX shell. A removed worktree is added back at that
    /// commit, where it was. Gleaner never runs it (SPEC §6).
    public var restoreCommand: String?
}

/// Observes a path in place. Read-only: it never writes to the file or its repository.
public enum Locator {
    /// A file on disk is checked in the checkout holding it now. A missing one is looked for in
    /// `checkout`, the one it was found in at delivery, which outlives a removed worktree; without
    /// it, in the checkout its path was last found in.
    public static func observe(_ path: String, checkout recorded: Checkout? = nil) -> LocatorState {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else {
            guard let checkout = recorded ?? Projects.checkout(path: path) else { return LocatorState(kind: .missing, git: .notInRepo) }
            let rel = relative(path, to: checkout.folder)
            // A removed worktree takes its HEAD with it; its branch and commits stay in the repository.
            let removed = !fm.fileExists(atPath: checkout.folder + "/.git")
            guard let commit = commit(containing: rel, root: removed ? checkout.repository : checkout.folder, head: !removed) else {
                return LocatorState(kind: .missing, repositoryRoot: checkout.folder, git: .lost)
            }
            return LocatorState(
                kind: .missing, repositoryRoot: checkout.folder,
                git: commit.isHead ? .recoverableFromHead : .recoverableFromHistory,
                restoreCommand: removed
                    ? "git -C \(quoted(checkout.repository)) worktree add --detach \(quoted(checkout.folder)) \(quoted(commit.sha))"
                    : "git --literal-pathspecs -C \(quoted(checkout.folder)) restore --source=\(quoted(commit.sha)) -- \(quoted(rel))")
        }

        let info = stat(path)
        let root = Projects.resolve((path as NSString).deletingLastPathComponent)?.folder
        return LocatorState(
            kind: info.kind,
            size: info.size,
            modifiedAt: info.modifiedAt,
            sha256: info.kind == .file ? sha256(path) : nil,
            repositoryRoot: root,
            git: root.map { gitState(path, root: $0) } ?? .notInRepo)
    }

    /// Kind, size, and modification time without reading contents or asking git.
    public static func stat(_ path: String) -> (kind: LocatorState.Kind, size: Int64?, modifiedAt: Date?) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: (path as NSString).resolvingSymlinksInPath)
        else { return (.missing, nil, nil) }
        let kind: LocatorState.Kind = switch attributes[.type] as? FileAttributeType {
        case .typeRegular: .file
        case .typeDirectory: .directory
        default: .special
        }
        return (kind, kind == .file ? (attributes[.size] as? NSNumber)?.int64Value : nil, attributes[.modificationDate] as? Date)
    }

    /// Nil when the file can't be opened or a read fails: the digest of a prefix is not its hash.
    public static func sha256(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func gitState(_ path: String, root: String) -> GitState {
        let result = run(["-C", root, "status", "--porcelain=v1", "--ignored", "--", relative(path, to: root)])
        guard result.status == 0 else { return .notInRepo }
        let lines = result.output.split(separator: "\n")
        if lines.isEmpty { return .committed }
        if lines.allSatisfy({ $0.hasPrefix("!!") }) { return .ignored }
        if lines.allSatisfy({ $0.hasPrefix("??") }) { return .untracked }
        return .modified
    }

    static func relative(_ path: String, to root: String) -> String {
        path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }

    /// The commit to restore `rel` from: HEAD when it has the path, else the newest commit on any
    /// ref that does. Each candidate is checked with `git cat-file`, because the commit that last
    /// touched a path may be the one that deleted it. `head` is false when `root` is not the
    /// checkout the path was in, whose HEAD is not the one that held it.
    static func commit(containing rel: String, root: String, head useHead: Bool) -> (sha: String, isHead: Bool)? {
        let head = useHead
            ? run(["-C", root, "rev-parse", "--verify", "--quiet", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let touched = run(["-C", root, "log", "--all", "--full-history", "--format=%H", "--", rel]).output
            .split(separator: "\n").map(String.init)
        let sha = ([head] + touched).first { commit in
            !commit.isEmpty && run(["-C", root, "cat-file", "-e", "\(commit):\(rel)"]).status == 0
        }
        return sha.map { ($0, $0 == head) }
    }

    /// One word for any POSIX shell, whatever `value` holds.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // Without the first, `git status` refreshes and rewrites the index: not read-only. The second
        // keeps a file name like `notes [1].md` from matching other files as a pattern. The third keeps
        // reading the index from running a hook or daemon the repository configures (SPEC §7).
        process.arguments = ["--no-optional-locks", "--literal-pathspecs", "-c", "core.fsmonitor=false"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
