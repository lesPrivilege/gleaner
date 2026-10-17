import Foundation

/// The project a delivery belongs to: the git repository holding the file, else the repository
/// the agent worked in, else the folder it worked in. Every worktree of a repository resolves to
/// the repository's main folder, wherever the agent keeps it (rulings §2). A project is told
/// apart by that folder's path and shown by its name, so two repositories named `app` stay two.
///
/// Repositories are found by reading `.git` entries, not by running git, so resolving a library
/// costs only file reads. A deleted worktree inside its repository resolves through its nearest
/// existing ancestor; a deleted external one leaves nothing to follow, so the indexer records
/// each delivery's repository while it can still be found.
public enum Projects {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var roots: [String: String?] = [:]

    /// The main folder of the repository holding the file at `path`, else of the one the agent
    /// worked in; nil outside git.
    public static func repository(path: String, cwd: String?) -> String? {
        repository(containing: (path as NSString).deletingLastPathComponent) ?? cwd.flatMap(repository(containing:))
    }

    /// The main folder of the repository containing `directory`, or nil outside git.
    public static func repository(containing directory: String) -> String? {
        lock.lock()
        if let cached = roots[directory] { lock.unlock(); return cached }
        lock.unlock()
        let root = resolve(directory)
        lock.lock()
        roots[directory] = root
        lock.unlock()
        return root
    }

    /// What each project folder is shown as: its name, or its parent folder's name and its own
    /// when another folder has the same name (`client-a/app`, `client-b/app`).
    public static func names(_ folders: some Sequence<String>) -> [String: String] {
        let byName = Dictionary(grouping: Set(folders)) { ($0 as NSString).lastPathComponent }
        var names: [String: String] = [:]
        for (name, group) in byName {
            for folder in group {
                let parent = ((folder as NSString).deletingLastPathComponent as NSString).lastPathComponent
                names[folder] = group.count == 1 ? name : parent + "/" + name
            }
        }
        return names
    }

    /// Forgets every repository found, as a fresh launch would.
    static func forgetRepositories() {
        lock.withLock { roots.removeAll() }
    }

    private static func resolve(_ directory: String) -> String? {
        let fm = FileManager.default
        var current = directory
        while current != "/" && !current.isEmpty {
            let dotGit = current + "/.git"
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dotGit, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return current }
                return mainFolder(gitFile: dotGit, worktree: current)
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// A `.git` file points at the worktree's git directory; its `commondir` leads to the shared
    /// one, whose parent is the main folder. A submodule has no `commondir` and is its own project.
    private static func mainFolder(gitFile: String, worktree: String) -> String {
        guard let text = try? String(contentsOfFile: gitFile, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return worktree }
        var gitDir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !gitDir.hasPrefix("/") { gitDir = (worktree as NSString).appendingPathComponent(gitDir) }
        guard let common = try? String(contentsOfFile: gitDir + "/commondir", encoding: .utf8) else { return worktree }
        var commonDir = common.trimmingCharacters(in: .whitespacesAndNewlines)
        if !commonDir.hasPrefix("/") { commonDir = (gitDir as NSString).appendingPathComponent(commonDir) }
        commonDir = (commonDir as NSString).standardizingPath
        return (commonDir as NSString).lastPathComponent == ".git" ? (commonDir as NSString).deletingLastPathComponent : worktree
    }

    /// Outside git: the folder the agent worked in, or, when the file sits outside it, the first
    /// folder where the two paths part.
    static func folder(path: String, cwd: String?) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        guard let cwd else { return outsideWorktrees(directory) }
        if directory == cwd || directory.hasPrefix(cwd + "/") { return outsideWorktrees(cwd) }
        let a = directory.split(separator: "/"), b = cwd.split(separator: "/")
        let shared = zip(a, b).prefix { $0 == $1 }.count
        return shared < a.count ? "/" + a[...shared].joined(separator: "/") : outsideWorktrees(directory)
    }

    /// An agent's worktree folder stands for the folder that keeps it.
    static func outsideWorktrees(_ directory: String) -> String {
        for marker in ["/.claude/worktrees/", "/.worktrees/", "/.codex/worktrees/"] {
            if let range = directory.range(of: marker) { return String(directory[..<range.lowerBound]) }
        }
        return directory
    }
}
