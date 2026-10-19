#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
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
        /// device). It is never opened: reading a FIFO blocks forever. `unreadable` is a path
        /// Gleaner can't open, read, or reach for want of permission: not shown to be gone, but
        /// its bytes are unknown.
        case file, directory, special, unreadable, missing
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
        let info = stat(path)
        guard info.kind != .missing else {
            guard let checkout = recorded ?? Projects.checkout(path: path) else { return LocatorState(kind: .missing, git: .notInRepo) }
            let rel = relative(path, to: checkout.folder)
            // A removed worktree takes its HEAD with it; its branch and commits stay in the repository.
            let removed = !FileManager.default.fileExists(atPath: checkout.folder + "/.git")
            guard let commit = commit(containing: rel, root: removed ? checkout.repository : checkout.folder, head: !removed) else {
                return LocatorState(kind: .missing, repositoryRoot: checkout.folder, git: .lost)
            }
            return LocatorState(
                kind: .missing, repositoryRoot: checkout.folder,
                git: commit.isHead ? .recoverableFromHead : .recoverableFromHistory,
                restoreCommand: removed
                    // `-f` takes back the folder of a worktree deleted without git, which git keeps
                    // registered; it still refuses a folder that holds anything.
                    ? "git -C \(quoted(checkout.repository)) worktree add -f --detach \(quoted(checkout.folder)) \(quoted(commit.sha))"
                    : "git --literal-pathspecs -C \(quoted(checkout.folder)) restore --source=\(quoted(commit.sha)) -- \(quoted(rel))")
        }

        let root = Projects.resolve((path as NSString).deletingLastPathComponent)?.folder
        let sha = info.kind == .file ? sha256(path) : nil
        return LocatorState(
            // A file that can't be opened or read whole is there, but its bytes are unknown.
            kind: info.kind == .file && sha == nil ? .unreadable : info.kind,
            size: info.size,
            modifiedAt: info.modifiedAt,
            sha256: sha,
            repositoryRoot: root,
            git: root.map { gitState(path, root: $0) } ?? .notInRepo)
    }

    /// Kind, size, and modification time of what `path` leads to, without reading contents or
    /// asking git. Missing only when nothing is there (a link to nothing included); any other
    /// failure, such as a folder on the way that can't be searched, is unreadable.
    public static func stat(_ path: String) -> (kind: LocatorState.Kind, size: Int64?, modifiedAt: Date?) {
        var info = SystemStat()
        // stat(2), by another name because this function's hides it. It follows links.
        guard fstatat(AT_FDCWD, path, &info, 0) == 0 else {
            return (errno == ENOENT || errno == ENOTDIR ? .missing : .unreadable, nil, nil)
        }
        let kind: LocatorState.Kind = switch info.st_mode & S_IFMT {
        case S_IFREG: .file
        case S_IFDIR: .directory
        default: .special
        }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9)
        return (kind, kind == .file ? Int64(info.st_size) : nil, modified)
    }

    /// Nil when the file can't be opened or a read fails, which makes it unreadable: the digest of a
    /// prefix is not its hash.
    public static func sha256(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            try read(handle) { hasher.update(data: $0) }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Hands `body` the rest of `handle`'s file a piece at a time, each let go once `body` returns.
    /// Foundation hands a piece over autoreleased: without a pool of its own, a file read whole
    /// would be held until the thread's pool drains.
    static func read(_ handle: FileHandle, each body: (Data) -> Void) throws {
        while try autoreleasepool(invoking: {
            guard let piece = try handle.read(upToCount: 4 << 20), !piece.isEmpty else { return false }
            body(piece)
            return true
        }) {}
    }

    /// What Git says of the file at `path` now, in the checkout holding it: committed, modified,
    /// untracked or ignored; not in a repository outside one. Reads no bytes of the file.
    public static func gitState(of path: String) -> GitState {
        guard let root = Projects.resolve((path as NSString).deletingLastPathComponent)?.folder else { return .notInRepo }
        return gitState(path, root: root)
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
    /// ref that does. Each candidate is checked, because the commit that last touched a path may be
    /// the one that deleted it, by finding the path in its tree: the file's contents are never read,
    /// so a partial clone has nothing to fetch. `head` is false when `root` is not the checkout the
    /// path was in, whose HEAD is not the one that held it.
    static func commit(containing rel: String, root: String, head useHead: Bool) -> (sha: String, isHead: Bool)? {
        let head = useHead
            ? run(["-C", root, "rev-parse", "--verify", "--quiet", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let touched = run(["-C", root, "log", "--all", "--full-history", "--format=%H", "--", rel]).output
            .split(separator: "\n").map(String.init)
        let sha = ([head] + touched).first { commit in
            !commit.isEmpty && run(["-C", root, "rev-parse", "--verify", "--quiet", "\(commit):\(rel)"]).status == 0
        }
        return sha.map { ($0, $0 == head) }
    }

    /// One word for any POSIX shell, whatever `value` holds.
    public static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // Without the first, `git status` refreshes and rewrites the index: not read-only. The second
        // keeps a file name like `notes [1].md` from matching other files as a pattern. The rest keep
        // git from running a command the repository configures (SPEC §7): a hook or daemon to read the
        // index, a signature checker for `git log`, and, in a partial clone, a fetch of what it lacks.
        process.arguments = ["--no-optional-locks", "--literal-pathspecs", "-c", "core.fsmonitor=false",
                             "-c", "log.showSignature=false"] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["GIT_NO_LAZY_FETCH": "1"]) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
