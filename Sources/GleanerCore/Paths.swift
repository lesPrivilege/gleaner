import Foundation

/// The one form Gleaner keeps a path in, whoever wrote it: a reply naming a file, an agent's log
/// recording the folder it worked in, git naming a repository's folder, or an agent asking for a
/// project. Paths in this form compare as they are.
enum Paths {
    /// The folders macOS links into `/private`: `/tmp` is `/private/tmp`.
    static let linkedIntoPrivate: Set<Substring> = ["tmp", "var", "etc"]

    /// The absolute `path` with `.`, `..`, repeated slashes and a slash at the end resolved by its
    /// text alone, and without the `/private` that `/tmp`, `/var` and `/etc` lead to. An agent
    /// records the folder it works in with `/private`, as the system resolves it; Foundation's
    /// folders and the paths agents write go without it. `NSString.standardizingPath` drops it only
    /// while the shorter path exists, so a path would change form once its file is gone: this never
    /// asks the disk.
    static func standard(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": _ = parts.popLast()
            default: parts.append(part)
            }
        }
        if parts.count > 1, parts[0] == "private", linkedIntoPrivate.contains(parts[1]) { parts.removeFirst() }
        return "/" + parts.joined(separator: "/")
    }
}
