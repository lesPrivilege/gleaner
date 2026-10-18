import Foundation

/// A folder git checks files out into, and the repository it belongs to.
public struct Checkout: Sendable, Equatable {
    /// The repository's main folder, or a worktree's own folder.
    public var folder: String
    /// The repository's main folder (see `Projects`).
    public var repository: String

    public init(folder: String, repository: String) {
        self.folder = folder
        self.repository = repository
    }
}

/// The project a delivery belongs to: the git repository holding the file, else the repository
/// the agent worked in, else the folder it worked in. Every worktree of a repository resolves to
/// the repository's main folder, wherever the agent keeps it (rulings §2); a bare repository
/// (`app.git`) is its own main folder. A project is told apart by that folder's path and shown by
/// its name, so two repositories named `app` stay two.
///
/// Repositories are found by reading `.git` entries, not by running git, so resolving a library
/// costs only file reads. A deleted worktree inside its repository resolves through its nearest
/// existing ancestor, which is the main folder, not the worktree; a deleted external one leaves
/// nothing to follow. So the indexer records each delivery's checkout and repository while they
/// can still be found.
public enum Projects {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var checkouts: [String: Checkout?] = [:]

    /// The main folder of the repository holding the file at `path`, else of the one the agent
    /// worked in; nil outside git.
    public static func repository(path: String, cwd: String?) -> String? {
        (checkout(path: path) ?? cwd.map(standardPath).flatMap(checkout(containing:)))?.repository
    }

    /// The checkout holding the file at `path`, or nil outside git. Found once per folder, like the
    /// repository, so a worktree removed later is still the one found.
    public static func checkout(path: String) -> Checkout? {
        checkout(containing: (path as NSString).deletingLastPathComponent)
    }

    private static func checkout(containing directory: String) -> Checkout? {
        lock.lock()
        if let cached = checkouts[directory] { lock.unlock(); return cached }
        lock.unlock()
        let checkout = resolve(directory)
        lock.lock()
        checkouts[directory] = checkout
        lock.unlock()
        return checkout
    }

    /// A project folder's name: a bare repository's without its `.git`.
    public static func name(_ folder: String) -> String {
        let name = (folder as NSString).lastPathComponent
        return name.hasSuffix(".git") && name.count > 4 ? String(name.dropLast(4)) : name
    }

    /// What each project folder is shown as: its name, or its parent folder's name and its own
    /// when another folder has the same name (`client-a/app`, `client-b/app`).
    public static func names(_ folders: some Sequence<String>) -> [String: String] {
        let byName = Dictionary(grouping: Set(folders), by: name)
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
        lock.withLock { checkouts.removeAll() }
    }

    /// The checkout containing `directory` as the disk has it now: the nearest folder holding
    /// `.git`, a main folder when that is a directory, a linked worktree (or a submodule) when a file.
    static func resolve(_ directory: String) -> Checkout? {
        let fm = FileManager.default
        var current = directory
        while current != "/" && !current.isEmpty {
            let dotGit = current + "/.git"
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dotGit, isDirectory: &isDirectory) {
                let repository = isDirectory.boolValue ? current : mainFolder(gitFile: dotGit, worktree: current)
                return Checkout(folder: current, repository: repository)
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// A `.git` file points at the worktree's git directory; its `commondir` leads to the shared
    /// one. Kept in a folder under a hidden name (`.git`, or `.bare` beside a `.git` file naming
    /// it), it belongs to that folder; a bare repository (`app.git`) is its own main folder. A
    /// submodule has no `commondir` and is its own project.
    private static func mainFolder(gitFile: String, worktree: String) -> String {
        guard let text = try? String(contentsOfFile: gitFile, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return worktree }
        var gitDir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !gitDir.hasPrefix("/") { gitDir = (worktree as NSString).appendingPathComponent(gitDir) }
        guard let common = try? String(contentsOfFile: gitDir + "/commondir", encoding: .utf8) else { return worktree }
        var commonDir = common.trimmingCharacters(in: .whitespacesAndNewlines)
        if !commonDir.hasPrefix("/") { commonDir = (gitDir as NSString).appendingPathComponent(commonDir) }
        commonDir = (commonDir as NSString).standardizingPath
        return (commonDir as NSString).lastPathComponent.hasPrefix(".") ? (commonDir as NSString).deletingLastPathComponent : commonDir
    }

    /// Outside git: the folder the agent worked in, or, when the file sits outside it, the first
    /// folder where the two paths part.
    /// The cwd is spelled as a delivered path is (`standardPath`), so a folder under `/private/tmp`
    /// or `/private/var` is the same folder as the paths in it.
    static func folder(path: String, cwd: String?) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        guard let cwd = cwd.map(standardPath) else { return outsideWorktrees(directory) }
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
