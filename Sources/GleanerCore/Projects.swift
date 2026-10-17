import Foundation

/// The project a delivery belongs to: the git repository holding the file, else the repository
/// the agent worked in, else the folder name. Every worktree of a repository resolves to the
/// repository's main folder, wherever the agent keeps it (rulings §2).
///
/// Repositories are found by reading `.git` entries, not by running git, so resolving a library
/// costs only file reads. A deleted worktree resolves through its nearest existing ancestor.
public enum Projects {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var roots: [String: String?] = [:]

    public static func project(path: String, cwd: String?) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        if let root = repository(containing: directory) { return (root as NSString).lastPathComponent }
        if let cwd, let root = repository(containing: cwd) { return (root as NSString).lastPathComponent }
        return fallbackName(path: path, cwd: cwd)
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
    static func fallbackName(path: String, cwd: String?) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        guard let cwd else { return folderName(directory) }
        if directory == cwd || directory.hasPrefix(cwd + "/") { return folderName(cwd) }
        let a = directory.split(separator: "/"), b = cwd.split(separator: "/")
        let shared = zip(a, b).prefix { $0 == $1 }.count
        return shared < a.count ? String(a[shared]) : folderName(directory)
    }

    static func folderName(_ directory: String) -> String {
        for marker in ["/.claude/worktrees/", "/.worktrees/", "/.codex/worktrees/"] {
            if let range = directory.range(of: marker) {
                return (String(directory[..<range.lowerBound]) as NSString).lastPathComponent
            }
        }
        return (directory as NSString).lastPathComponent
    }
}
