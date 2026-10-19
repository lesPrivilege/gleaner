import Foundation
import Synchronization
import UniformTypeIdentifiers

/// A file found on the disk whose dates fall in a session's span, in the session's workspace
/// (docs/design/capture.md). It shows that the file appeared or changed while the session was
/// working, not that the session made it: parallel sessions, background jobs and a copy made while
/// it worked fall inside spans too. It is a candidate, never a delivery. Gleaner records it the first time it sees it and never
/// rewrites it; a later session's observation of the file is recorded beside it. Only metadata is
/// read: names, sizes, dates and file identity, never the bytes.
public struct Observed: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        /// Its creation date falls in a stretch of the span.
        case appeared
        /// Its modification date falls in one, and its creation date doesn't.
        case changed
    }

    public var path: String
    public var kind: Kind
    /// The log of the session it was observed during, which keys the session here as it keys a
    /// delivery's, and the session's own id.
    public var logPath: String
    public var sessionID: String
    public var provider: Provider
    public var sessionTitle: String?
    /// The stretch of the session's span its date falls in, as last derived from the log: from a
    /// request to the last reply answering it. Nil once the log no longer gives one.
    public var stretch: DateInterval?
    /// The folder walked: the Git checkout the session worked in, or the folder itself.
    public var workspace: String
    /// The file as Gleaner first saw it.
    public var size: Int64
    public var createdAt: Date?
    public var modifiedAt: Date
    /// Its identity on its volume, which a rename keeps and a replacement doesn't.
    public var device: Int64
    public var inode: Int64
    /// The repository's main folder and the checkout it was found in, recorded at first sight as a
    /// capture records them: a worktree removed later leaves nothing that leads back.
    public var repository: String?
    public var checkout: String?
    /// When Gleaner first saw it.
    public var observedAt: Date

    public var id: String { logPath + "\n" + path }

    /// The date that placed it in the span.
    public var date: Date { kind == .appeared ? createdAt ?? modifiedAt : modifiedAt }
}

/// A file observed during sessions and handed over in none: a candidate the person may look at,
/// detach from a session, or relate to a work. Never a delivery, a version or a work.
public struct Candidate: Sendable, Identifiable {
    public var path: String
    /// Each session's observation of it, its latest write first, without those the person detached.
    public var observations: [Observed]
    /// What a project keys on, as for an artifact: the main folder of the repository it was found
    /// in, else the folder its session worked in (see `Projects`).
    public var projectFolder: String
    public var inRepository: Bool
    /// The checkout it was found in; nil outside git.
    public var checkout: Checkout?
    /// The key of the project it is shown in.
    public var project: String

    /// `observations` run newest first; the earliest that found a repository gives its project, as
    /// an artifact's earliest capture does.
    init(path: String, observations: [Observed]) {
        self.path = path
        self.observations = observations
        let found = observations.reversed().first { $0.repository != nil }
        projectFolder = found?.repository ?? Projects.folder(path: path, cwd: observations[observations.count - 1].workspace)
        inRepository = found != nil
        checkout = found.flatMap { o in o.checkout.map { Checkout(folder: $0, repository: o.repository ?? $0) } }
        project = projectFolder
    }

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var latest: Observed { observations[0] }
    /// Its latest write, as the sessions that observed it saw it.
    public var date: Date { latest.modifiedAt }
    public var kind: Artifact.Kind { Artifact.kind(ofExtension: (path as NSString).pathExtension) }

    /// Each file observed, with every session's observation of it, newest first: what
    /// `Organization` takes, made once each time the observations load.
    public static func files(_ observations: [Observed]) -> [Candidate] {
        Dictionary(grouping: observations, by: \.path).map { path, list in
            Candidate(path: path, observations: list.sorted {
                $0.modifiedAt != $1.modifiedAt ? $0.modifiedAt > $1.modifiedAt : $0.logPath < $1.logPath
            })
        }.sorted(by: newestFirst)
    }

    static func newestFirst(_ a: Candidate, _ b: Candidate) -> Bool {
        a.date != b.date ? a.date > b.date : a.path < b.path
    }

    /// The file with only the observations `kept`; nil when none is kept.
    public func keeping(_ kept: (Observed) -> Bool) -> Candidate? {
        let list = observations.filter(kept)
        guard list.count < observations.count else { return self }
        return list.isEmpty ? nil : Candidate(path: path, observations: list)
    }
}

/// When a session worked (docs/design/capture.md): one stretch per request, from the request to
/// the last reply answering it, widened for the clocks of the log's writer and the disk's, and
/// joined where they meet. The time between a reply and the next request is left out: a
/// conversation resumed days later wasn't working in between.
public struct Span: Sendable, Equatable {
    /// Earliest first; none overlaps another. Never empty.
    public var stretches: [DateInterval]

    public func stretch(containing date: Date) -> DateInterval? {
        stretches.first { $0.contains(date) }
    }

    public var end: Date { stretches[stretches.count - 1].end }

    /// As the registry keeps it: `[[start, end], …]` in seconds since 1970.
    var json: String {
        String(decoding: (try? JSONEncoder().encode(stretches.map { [$0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970] })) ?? Data(),
               as: UTF8.self)
    }

    init(stretches: [DateInterval]) {
        self.stretches = stretches
    }

    init?(json: String) {
        guard let pairs = try? JSONDecoder().decode([[Double]].self, from: Data(json.utf8)),
              !pairs.isEmpty, pairs.allSatisfy({ $0.count == 2 && $0[0] <= $0[1] }) else { return nil }
        stretches = pairs.map { DateInterval(start: Date(timeIntervalSince1970: $0[0]), end: Date(timeIntervalSince1970: $0[1])) }
    }
}

extension SessionLog {
    /// When the session worked: each reply's stretch runs from the request it answers (the
    /// adapter's `requestAt`; its own first record without one) to its last record, widened by
    /// `grace` both ways, and stretches that meet are joined. A reply to a task notification
    /// answers the request before it, so a background job between the two is inside. A session
    /// without a reply time has no span: an interrupted turn, and a title appended later, give none.
    public func span(grace: TimeInterval) -> Span? {
        let stretches = turns.compactMap { turn -> DateInterval? in
            let times = turn.parts.compactMap(\.at)
            guard let first = times.min(), let last = times.max() else { return nil }
            return DateInterval(start: min(turn.requestAt ?? first, first).addingTimeInterval(-grace), end: last.addingTimeInterval(grace))
        }.sorted { $0.start < $1.start }
        var joined: [DateInterval] = []
        for stretch in stretches {
            if let last = joined.last, stretch.start <= last.end {
                joined[joined.count - 1] = DateInterval(start: last.start, end: max(last.end, stretch.end))
            } else {
                joined.append(stretch)
            }
        }
        return joined.isEmpty ? nil : Span(stretches: joined)
    }

    /// The folders the session worked in, as its records name them, in one spelling, first first.
    public var workingFolders: [String] {
        var seen = Set<String>()
        return ([session.cwd] + turns.flatMap(\.parts).map(\.cwd)).compactMap { $0.map(standardPath) }
            .filter { seen.insert($0).inserted }
    }
}

/// Where a session's files are looked for (docs/design/capture.md): the Git checkout of a folder
/// it worked in, else the folder. A workspace is walked by metadata only, once per run whatever
/// the number of sessions in it.
public enum Workspace {
    /// Entries one walk looks at before it stops; a walk cut short is reported.
    public static let limit = 100_000

    /// Folders a walk never enters by name: the dependency caches tools leave. Nor does it enter a
    /// hidden folder (`.git`, `.build` and `.venv` among them), a folder its tool marked as a cache
    /// with a `CACHEDIR.TAG` file (Cargo's `target`, for one), or a folder on another volume, nor
    /// list a hidden file (`.env`, `.DS_Store`). These skips are structural. No file type is
    /// skipped, since a script may itself be what was made, and no output folder is: `dist` or
    /// `build` may hold what was asked for.
    static let caches: Set<String> = ["node_modules", "__pycache__", "DerivedData"]

    /// A regular file as a walk found it, without opening it; or a package, which Finder shows as
    /// one file (`isPackage`), by its own metadata.
    struct File: Sendable, Equatable {
        var path: String
        var size: Int64
        var createdAt: Date?
        var modifiedAt: Date
        /// When its inode last changed (`st_ctime`): a write, a rename, new permissions, or its
        /// dates being set. No tool can set it back, so a copy that kept older dates shows when it
        /// was made.
        var changedAt: Date
        var device: Int64
        var inode: Int64
        /// A folder the system declares a package (`isPackage`): one entry, never entered.
        var isPackage = false
    }

    /// What one walk found, and why it may not be everything: it stopped at its bound, or a folder
    /// in it couldn't be listed.
    struct Walk: Sendable {
        var files: [File] = []
        var problems: [String] = []
        /// The folders below the root a walk that doesn't enter repositories left out, each one
        /// (`isRepository`), in walk order.
        var repositories: [String] = []
        /// Whether the root itself could be listed: when it couldn't, the walk saw nothing of it.
        var listedRoot = false
    }

    /// The workspace of a folder a session worked in: the Git checkout holding it (a worktree's own
    /// folder, or the main one), else the folder. Nil when the folder isn't there.
    public static func root(of folder: String) -> String? {
        guard Locator.stat(folder).kind == .directory else { return nil }
        return Projects.resolve(folder)?.folder ?? folder
    }

    /// Why a workspace isn't walked, or nil when it is (docs/design/capture.md): it is the home
    /// folder or holds it, it is in the home's Library outside iCloud Drive and cloud storage, it
    /// is a system folder or a hidden one, or it is, holds or is inside one of Gleaner's `own`
    /// folders (the agents' logs and Gleaner's library). Compared as the disk has them, with links
    /// followed and case as on disk, so another spelling of a folder is skipped as it is; the real
    /// home is skipped whatever `home` is.
    public static func skipped(_ workspace: String, home: String, own: [String]) -> String? {
        let path = resolved(workspace)
        func within(_ path: String, _ folder: String) -> Bool {
            path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/")
        }
        let homes = Set([home, NSHomeDirectory()].map(resolved))
        if homes.contains(where: { within($0, path) }) { return "the home folder or a folder holding it" }
        for home in homes where within(path, home + "/Library")
            && !["Mobile Documents", "CloudStorage"].contains(where: { path.hasPrefix(home + "/Library/" + $0 + "/") }) {
            return "the home’s Library"
        }
        if ["/Applications", "/Volumes", "/private", "/private/var", "/private/tmp", "/var", "/tmp", "/opt", "/cores", "/Network"]
            .contains(path)
            || ["/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/private/etc", "/dev"].contains(where: { within(path, $0) }) {
            return "a system folder"
        }
        if (path as NSString).lastPathComponent.hasPrefix(".") { return "a hidden folder" }
        if own.map(resolved).contains(where: { within(path, $0) || within($0, path) }) { return "the agents’ logs or Gleaner’s library" }
        return nil
    }

    /// The path as the disk has it, links followed and case as on disk; for a path that isn't
    /// there, its nearest folder that is, with the rest as given.
    static func resolved(_ path: String) -> String {
        if let real = realpath(path, nil) {
            defer { free(real) }
            return String(cString: real)
        }
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != path else { return path }
        return (resolved(parent) as NSString).appendingPathComponent((path as NSString).lastPathComponent)
    }

    /// Whether a folder holding `names` is a Git repository's own folder, as git looks for one: a
    /// checkout's, holding `.git`, or a bare repository, holding `HEAD`, `objects` and `refs`.
    static func isRepository(_ names: Set<String>) -> Bool {
        names.contains(".git") || ["HEAD", "objects", "refs"].allSatisfy(names.contains)
    }

    /// Whether a folder named `name` is a package, which Finder shows as one file (an app, an Xcode
    /// project, an RTFD document, a bundle): its extension's type, as the system declares it for a
    /// folder, conforms to `UTType.package`. That is structure the system gives, not a type Gleaner
    /// picks. Each extension is looked up once.
    static func isPackage(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if let known = packages.withLock({ $0[ext] }) { return known }
        let package = UTType(filenameExtension: ext, conformingTo: .directory)?.conforms(to: .package) == true
        packages.withLock { $0[ext] = package }
        return package
    }

    private static let packages = Mutex<[String: Bool]>([:])

    /// Lists every regular file under `root`, by name, size, dates and identity; never opens one.
    /// A package (`isPackage`) is listed as one entry by its own metadata, never entered. Doesn't
    /// list hidden files, enter hidden folders, caches, or folders on another volume, or follow
    /// links: what a walk finds is never `.env`, whether a session is observed or a delivered
    /// folder listed (SPEC §5.3, §5.4).
    /// Folders are read in name order, so a walk cut at `limit` entries stops at the same place
    /// each time. Without `entersRepositories`, a folder below the root that is a Git repository's
    /// own (`isRepository`), another project, is left out whole and named in `repositories`.
    static func walk(_ root: String, limit: Int = limit, entersRepositories: Bool = true) -> Walk {
        var walk = Walk(), seen = 0
        var info = Darwin.stat()
        // stat(2), following a linked root, by the name `Locator.stat` uses: the struct's name hides the function's.
        guard fstatat(AT_FDCWD, root, &info, 0) == 0 else {
            walk.problems.append("\(root): \(String(cString: strerror(errno)))")
            return walk
        }
        let volume = info.st_dev
        var folders = [root]
        while let folder = folders.popLast() {
            let names: [String]
            do {
                names = try FileManager.default.contentsOfDirectory(atPath: folder).sorted()
            } catch {
                walk.problems.append("\(folder): \(error.localizedDescription)")
                continue
            }
            if folder == root { walk.listedRoot = true }
            if !entersRepositories, folder != root, isRepository(Set(names)) {
                walk.repositories.append(folder)
                continue
            }
            if names.contains("CACHEDIR.TAG") { continue }
            var inner: [String] = []
            for name in names {
                seen += 1
                guard seen <= limit else {
                    walk.problems.append("\(root): stopped after \(limit) entries")
                    return walk
                }
                let path = folder + "/" + name
                guard lstat(path, &info) == 0 else { continue }
                switch info.st_mode & S_IFMT {
                case S_IFDIR where !name.hasPrefix(".") && info.st_dev == volume && isPackage(name):
                    var package = file(path, info)
                    package.isPackage = true
                    walk.files.append(package)
                case S_IFDIR where !name.hasPrefix(".") && !caches.contains(name) && info.st_dev == volume:
                    inner.append(path)
                case S_IFREG where !name.hasPrefix("."):
                    walk.files.append(file(path, info))
                default:
                    break
                }
            }
            folders += inner.reversed()
        }
        return walk
    }

    /// The regular file at `path` itself (not what a link leads to), by its metadata; nil for
    /// anything else, or nothing.
    static func file(at path: String) -> File? {
        var info = Darwin.stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return file(path, info)
    }

    private static func file(_ path: String, _ info: Darwin.stat) -> File {
        func date(_ time: timespec) -> Date { Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1e9) }
        // A volume without creation dates reports none, as zero.
        let born = info.st_birthtimespec
        return File(path: path, size: Int64(info.st_size), createdAt: born.tv_sec > 0 ? date(born) : nil,
                    modifiedAt: date(info.st_mtimespec), changedAt: date(info.st_ctimespec), device: Int64(info.st_dev),
                    inode: Int64(bitPattern: UInt64(info.st_ino)))
    }

    /// Where a file's dates place it in a span: it appeared when its creation date falls in a
    /// stretch, and changed when its modification date does. Either only when the file's inode
    /// last changed before that stretch ended: a copy that kept its dates (`cp -p`, `rsync -a`,
    /// Finder, an archive), or dates `touch` set, made after the stretch isn't placed in it. A file
    /// renamed or given new permissions since is left out too: missed rather than claimed.
    static func place(_ file: File, in span: Span) -> Observed.Kind? {
        for (kind, date) in [(Observed.Kind.appeared, file.createdAt), (.changed, file.modifiedAt)] {
            if let date, let stretch = span.stretch(containing: date), file.changedAt <= stretch.end { return kind }
        }
        return nil
    }
}

extension Indexer {
    /// The folders no workspace walk starts in, holds or enters: the agents' logs and Gleaner's
    /// library, so Gleaner never observes transcripts or itself.
    var ownFolders: [String] {
        [sources.folder(.claudeCode).path, sources.folder(.codex).path, store.objects.path, store.staging.path, registry.path]
    }

    /// A session's span, the workspaces walked for it, and each folder it worked in that isn't
    /// walked, with why: gone, or skipped (`Workspace.skipped`). Nil without a span.
    func span(of log: SessionLog) -> (span: Span, workspaces: [String], unwalked: [String])? {
        guard let span = log.span(grace: spanGrace) else { return nil }
        var workspaces: [String] = [], unwalked: [String] = []
        for folder in log.workingFolders {
            guard let root = Workspace.root(of: folder) else {
                unwalked.append("\(folder): no longer there")
                continue
            }
            if let reason = Workspace.skipped(root, home: home, own: ownFolders) {
                unwalked.append("\(root): not walked, \(reason)")
            } else {
                workspaces.append(root)
            }
        }
        func once(_ list: [String]) -> [String] {
            var seen = Set<String>()
            return list.filter { seen.insert($0).inserted }
        }
        return (span, once(workspaces), once(unwalked))
    }

    /// Observes what appeared or changed during each session not walked since its span or
    /// workspaces last changed, or last walked before its span ended (docs/design/capture.md,
    /// layer 1). Each workspace is walked once, one at a time, and its observations recorded as
    /// each session's are found. A session is marked walked only once all of its observations are
    /// recorded, so a walk cut off by a quit or a failed write is made again next run. Only the
    /// sessions of `providers` are walked: an agent turned off has nothing read. Returns how many
    /// observations were recorded, and per agent what couldn't be.
    func observe(at now: Date, providers: Set<Provider>) -> (recorded: Int, failures: [Provider: [String]]) {
        let pending: [Registry.PendingSpan]
        do {
            pending = try registry.pendingSpans().filter { providers.contains($0.provider) }
        } catch {
            return (0, Dictionary(uniqueKeysWithValues: providers.map { ($0, ["observations not read: \(error)"]) }))
        }
        var recorded = 0, problems: [String: Set<String>] = [:], failed = Set<String>(), failures: [Provider: [String]] = [:]
        let members = Dictionary(grouping: pending.flatMap { session in session.workspaces.map { ($0, session) } }, by: \.0)
        for (workspace, members) in members.sorted(by: { $0.key < $1.key }) {
            let walk = Workspace.walk(workspace, limit: walkLimit)
            // A file a reply named in another spelling (case, a linked folder) is observed under
            // the name the reply gave it, so it is shown beside its delivery, not apart from it.
            var delivered: [FileIdentity: [String]] = [:]
            for path in (try? registry.deliveredPaths(logs: members.map(\.1.logPath), under: workspace)) ?? [] {
                if let id = FileIdentity(path) { delivered[id, default: []].append(path) }
            }
            for (_, session) in members {
                problems[session.logPath, default: []].formUnion(walk.problems)
                var observed: [Observed] = []
                for file in walk.files {
                    guard let kind = Workspace.place(file, in: session.span) else { continue }
                    let named = delivered[FileIdentity(device: file.device, inode: file.inode)]
                    let path = named.map { $0.contains(file.path) ? file.path : $0.min()! } ?? file.path
                    let checkout = Projects.checkout(path: path)
                    observed.append(Observed(
                        path: path, kind: kind, logPath: session.logPath, sessionID: session.sessionID, provider: session.provider,
                        workspace: workspace, size: file.size, createdAt: file.createdAt, modifiedAt: file.modifiedAt,
                        device: file.device, inode: file.inode, repository: checkout?.repository, checkout: checkout?.folder,
                        observedAt: now))
                }
                do {
                    recorded += try registry.transaction { try registry.add(observed) }
                } catch {
                    failed.insert(session.logPath)
                    failures[session.provider, default: []].append("\(workspace): observations not recorded: \(error)")
                }
            }
        }
        for session in pending where !failed.contains(session.logPath) {
            do {
                try registry.transaction {
                    try registry.markWalked(logPath: session.logPath, at: now, problems: (problems[session.logPath] ?? []).sorted())
                }
            } catch {
                failures[session.provider, default: []].append("\(session.logPath): walk not recorded: \(error)")
            }
        }
        return (recorded, failures)
    }
}

/// A file's identity on its volume, as `stat` gives it.
struct FileIdentity: Hashable {
    var device: Int64
    var inode: Int64

    init(device: Int64, inode: Int64) {
        self.device = device
        self.inode = inode
    }

    /// The regular file at `path`, links followed; nil when there is none.
    init?(_ path: String) {
        var info = Darwin.stat()
        guard fstatat(AT_FDCWD, path, &info, 0) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        self.init(device: Int64(info.st_dev), inode: Int64(bitPattern: UInt64(info.st_ino)))
    }
}

extension Registry {
    /// A session whose workspaces wait to be walked.
    struct PendingSpan {
        var logPath: String
        var sessionID: String
        var provider: Provider
        var span: Span
        var workspaces: [String]
    }

    /// Records a session's span and workspaces as derived from its log now, with the folders it
    /// worked in that aren't walked and why. When the span or the workspaces moved, the session
    /// waits to be walked again, and what the last walk couldn't see is forgotten with it.
    func recordSpan(of session: SessionInfo, provider: Provider, span: Span, workspaces: [String], unwalked: [String]) throws {
        let json = { (list: [String]) in String(decoding: try JSONEncoder().encode(list), as: UTF8.self) }
        try db.run("""
            INSERT INTO spans (log_path, session_id, provider, stretches, end_at, workspaces, unwalked) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(log_path) DO UPDATE SET session_id = excluded.session_id, provider = excluded.provider,
                unwalked = excluded.unwalked,
                walked_at = CASE WHEN stretches = excluded.stretches AND workspaces = excluded.workspaces THEN walked_at END,
                problems = CASE WHEN stretches = excluded.stretches AND workspaces = excluded.workspaces THEN problems END,
                stretches = excluded.stretches, end_at = excluded.end_at, workspaces = excluded.workspaces
            """, [session.logPath, session.id, provider.rawValue, span.json, span.end, try json(workspaces),
                  unwalked.isEmpty ? nil : try json(unwalked)])
    }

    /// The sessions to walk: never walked since their span or workspaces last moved, or last
    /// walked before their span ended, when more may have appeared in it.
    func pendingSpans() throws -> [PendingSpan] {
        try db.rows("SELECT log_path, session_id, provider, stretches, workspaces FROM spans WHERE walked_at IS NULL OR walked_at <= end_at")
            .compactMap { row in
                guard let logPath = row["log_path"] as? String, let provider = Provider(rawValue: row["provider"] as? String ?? ""),
                      let span = (row["stretches"] as? String).flatMap(Span.init(json:)),
                      let workspaces = (row["workspaces"] as? String).flatMap({ try? JSONDecoder().decode([String].self, from: Data($0.utf8)) })
                else { return nil }
                return PendingSpan(logPath: logPath, sessionID: row["session_id"] as? String ?? "", provider: provider, span: span,
                                   workspaces: workspaces)
            }
    }

    /// Records that a session's workspaces were walked at `date`, with what the walks couldn't see.
    func markWalked(logPath: String, at date: Date, problems: [String]) throws {
        try db.run("UPDATE spans SET walked_at = ?, problems = ? WHERE log_path = ?",
                   [date, problems.isEmpty ? nil : String(decoding: try JSONEncoder().encode(problems), as: UTF8.self), logPath])
    }

    /// The paths the replies of these logs named, and those named under `workspace` in any case
    /// (as APFS compares names), each once; and the files handed over in the folders among them
    /// and under `workspace` (SPEC §5.4).
    func deliveredPaths(logs: [String], under workspace: String) throws -> [String] {
        let marks = Array(repeating: "?", count: logs.count).joined(separator: ", ")
        // Each folder's files by a range of the files' key, never by reading every file listed.
        let listed = try db.rows("""
            SELECT m.path FROM (SELECT DISTINCT d.path AS folder FROM deliveries d JOIN captures c ON c.delivery_id = d.id
                                WHERE c.kind = 'directory' AND (d.path LIKE ? ESCAPE '\\' OR d.log_path IN (\(marks)))) f
                JOIN members m ON m.path > f.folder || '/' AND m.path < f.folder || '0'
            UNION SELECT path FROM members WHERE path > ? AND path < ?
            """, [Self.pattern(under: workspace)] + logs + [workspace + "/", workspace + "0"]).compactMap { $0["path"] as? String }
        return Array(Set(try namedPaths(logs: logs, under: workspace) + listed))
    }

    /// The paths the replies of these logs named, and those named under `folder` in any case, each once.
    func namedPaths(logs: [String], under folder: String) throws -> [String] {
        let marks = Array(repeating: "?", count: logs.count).joined(separator: ", ")
        return try db.rows("SELECT DISTINCT path FROM deliveries WHERE path LIKE ? ESCAPE '\\' OR log_path IN (\(marks))",
                           [Self.pattern(under: folder)] + logs).compactMap { $0["path"] as? String }
    }

    /// What `LIKE` matches for every path under `folder`, with the folder's own wildcards escaped.
    private static func pattern(under folder: String) -> String {
        folder.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "/%"
    }

    /// Records observations the first time Gleaner sees each file during each session: one already
    /// recorded for the session is never rewritten. Returns how many are new.
    func add(_ observations: [Observed]) throws -> Int {
        var added = 0
        for o in observations {
            added += try db.run("""
                INSERT OR IGNORE INTO observations (path, log_path, kind, workspace, size, created_at, modified_at,
                    device, inode, repository, checkout, observed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [o.path, o.logPath, o.kind.rawValue, o.workspace, o.size, o.createdAt, o.modifiedAt,
                      o.device, o.inode, o.repository, o.checkout, o.observedAt])
        }
        return added
    }

    /// Every observation, with its session's agent, title and the stretch its date falls in.
    public func observations() throws -> [Observed] {
        var spans: [String: Span?] = [:]
        return try db.rows("""
            SELECT o.log_path, o.path, o.kind, o.workspace, o.size, o.created_at, o.modified_at, o.device, o.inode,
                   o.repository, o.checkout, o.observed_at, p.session_id, p.provider, p.stretches, s.title
            FROM observations o LEFT JOIN spans p ON p.log_path = o.log_path LEFT JOIN sessions s ON s.id = p.session_id
            ORDER BY o.path, o.log_path
            """).compactMap { row in
            guard let path = row["path"] as? String, let logPath = row["log_path"] as? String,
                  let kind = Observed.Kind(rawValue: row["kind"] as? String ?? ""),
                  let modified = row["modified_at"] as? Double else { return nil }
            let date = { (key: String) in (row[key] as? Double).map(Date.init(timeIntervalSince1970:)) }
            if spans[logPath] == nil { spans[logPath] = (row["stretches"] as? String).flatMap(Span.init(json:)) }
            var observed = Observed(
                path: path, kind: kind, logPath: logPath, sessionID: row["session_id"] as? String ?? "",
                provider: Provider(rawValue: row["provider"] as? String ?? "") ?? .claudeCode, sessionTitle: row["title"] as? String,
                workspace: row["workspace"] as? String ?? "", size: row["size"] as? Int64 ?? 0, createdAt: date("created_at"),
                modifiedAt: Date(timeIntervalSince1970: modified), device: row["device"] as? Int64 ?? 0, inode: row["inode"] as? Int64 ?? 0,
                repository: row["repository"] as? String, checkout: row["checkout"] as? String,
                observedAt: date("observed_at") ?? Date(timeIntervalSince1970: 0))
            observed.stretch = spans[logPath]??.stretch(containing: observed.date)
            return observed
        }
    }

    /// What the walks of each agent's sessions' workspaces couldn't see, as recorded when each
    /// session was last walked, so it is reported on every run until the session is walked again.
    public func workspaceProblems() throws -> [Provider: [String]] {
        try lists("problems")
    }

    /// The folders each agent's sessions worked in that aren't walked, with why: skipped, or gone.
    /// Not a problem; it says why nothing was observed there.
    public func unwalkedWorkspaces() throws -> [Provider: [String]] {
        try lists("unwalked")
    }

    private func lists(_ column: String) throws -> [Provider: [String]] {
        var lists: [Provider: Set<String>] = [:]
        for row in try db.rows("SELECT provider, \(column) AS list FROM spans WHERE \(column) IS NOT NULL") {
            guard let provider = Provider(rawValue: row["provider"] as? String ?? ""), let text = row["list"] as? String,
                  let list = try? JSONDecoder().decode([String].self, from: Data(text.utf8)) else { continue }
            lists[provider, default: []].formUnion(list)
        }
        return lists.mapValues { $0.sorted() }
    }
}
