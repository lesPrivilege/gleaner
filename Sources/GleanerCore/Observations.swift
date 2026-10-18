import Foundation

/// A file found on the disk whose dates fall in a session's span, in the session's workspace
/// (docs/design/capture.md). It shows that the file appeared or changed while the session ran,
/// not that the session made it: parallel sessions, copied files and background jobs fall inside
/// spans too. It is a candidate, never a delivery. Gleaner records it the first time it sees it
/// and never rewrites it; a later session's observation of the file is recorded beside it. Only
/// metadata is read: names, sizes, dates and file identity, never the bytes.
public struct Observed: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        /// Its creation date falls in the span.
        case appeared
        /// Its modification date falls in the span, and its creation date doesn't.
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
    /// The session's span, as last derived from its log.
    public var span: DateInterval?
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
}

extension SessionLog {
    /// When the session worked: from its first record to its last reply, widened by `grace` both
    /// ways. The adapters give times for reply records only, so the first record's time is the log
    /// file's creation date, which that record's write set; a log copied later was created after
    /// its records, and its first reply bounds the start. A session without a reply ends at the
    /// log's last write. Nil when nothing gives a time.
    public func span(logCreated: Date?, logModified: Date?, grace: TimeInterval) -> DateInterval? {
        let replies = turns.flatMap(\.parts).compactMap(\.at)
        guard let first = [logCreated, replies.min()].compactMap({ $0 }).min(),
              let last = replies.max() ?? logModified else { return nil }
        return DateInterval(start: first.addingTimeInterval(-grace), end: max(first, last).addingTimeInterval(grace))
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

    /// Folders a walk never enters: the dependency and build caches tools leave. Hidden folders,
    /// `.git`, `.build` and `.venv` among them, aren't entered either. These skips are structural;
    /// no file type is skipped, since a script may itself be what was made.
    static let caches: Set<String> = ["node_modules", "__pycache__", "DerivedData", "target", "dist"]

    /// A regular file as a walk found it, without opening it.
    struct File: Sendable, Equatable {
        var path: String
        var size: Int64
        var createdAt: Date?
        var modifiedAt: Date
        var device: Int64
        var inode: Int64
    }

    /// What one walk found, and why it may not be everything: it stopped at its bound, or a folder
    /// in it couldn't be listed.
    struct Walk: Sendable {
        var files: [File] = []
        var problems: [String] = []
    }

    /// The workspace of a folder a session worked in: the Git checkout holding it (a worktree's own
    /// folder, or the main one), else the folder. Nil when the folder isn't there.
    public static func root(of folder: String) -> String? {
        guard Locator.stat(folder).kind == .directory else { return nil }
        return Projects.resolve(folder)?.folder ?? folder
    }

    /// True for the home folder, the folders holding it and its Library, and for system folders: a
    /// session working there has no workspace of its own. The real home is skipped whatever `home`
    /// is. A folder inside the home's Library is walked: iCloud Drive and cloud storage keep the
    /// person's documents there.
    public static func isSkipped(_ workspace: String, home: String) -> Bool {
        let homes = Set([home, NSHomeDirectory()].map(standardPath))
        if workspace == "/" || homes.contains(where: { $0 == workspace || $0 + "/Library" == workspace || $0.hasPrefix(workspace + "/") }) {
            return true
        }
        if ["/Applications", "/Volumes", "/private", "/var", "/tmp", "/opt", "/cores", "/Network"].contains(workspace) { return true }
        return ["/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/dev", "/private/etc"]
            .contains { workspace == $0 || workspace.hasPrefix($0 + "/") }
    }

    /// Lists every regular file under `root`, by name, size, dates and identity; never opens one.
    /// Hidden folders and caches aren't entered, and links aren't followed. Folders are read in
    /// name order, so a walk cut at `limit` entries stops at the same place each time.
    static func walk(_ root: String, limit: Int = limit) -> Walk {
        var walk = Walk(), seen = 0
        var folders = [root]
        while let folder = folders.popLast() {
            let names: [String]
            do {
                names = try FileManager.default.contentsOfDirectory(atPath: folder).sorted()
            } catch {
                walk.problems.append("\(folder): \(error.localizedDescription)")
                continue
            }
            var inner: [String] = []
            for name in names {
                seen += 1
                guard seen <= limit else {
                    walk.problems.append("\(root): stopped after \(limit) entries")
                    return walk
                }
                let path = folder + "/" + name
                var info = Darwin.stat()
                guard lstat(path, &info) == 0 else { continue }
                switch info.st_mode & S_IFMT {
                case S_IFDIR where !name.hasPrefix(".") && !caches.contains(name):
                    inner.append(path)
                case S_IFREG:
                    walk.files.append(file(path, info))
                default:
                    break
                }
            }
            folders += inner.reversed()
        }
        return walk
    }

    /// A file's metadata, following a link to it: for a session's log.
    static func file(_ path: String) -> File? {
        var info = Darwin.stat()
        // stat(2), by the name `Locator.stat` uses: the struct's name hides the function's.
        guard fstatat(AT_FDCWD, path, &info, 0) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return file(path, info)
    }

    private static func file(_ path: String, _ info: Darwin.stat) -> File {
        func date(_ time: timespec) -> Date { Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1e9) }
        // A volume without creation dates reports none, as zero.
        let born = info.st_birthtimespec
        return File(path: path, size: Int64(info.st_size), createdAt: born.tv_sec > 0 ? date(born) : nil,
                    modifiedAt: date(info.st_mtimespec), device: Int64(info.st_dev), inode: Int64(bitPattern: UInt64(info.st_ino)))
    }
}

extension Indexer {
    /// Observes what appeared or changed during each session read this run (docs/design/capture.md,
    /// layer 1): derives its span and workspaces, walks each workspace once, one at a time, and
    /// records the files whose creation or modification date falls in the span, beside what the
    /// session handed over. Only the sessions read now are matched, so a file copied in later with
    /// older dates isn't put in an old session. Returns, per agent, what couldn't be recorded.
    func observe(_ logs: [(provider: Provider, log: SessionLog)], now: Date) -> [Provider: [String]] {
        var spans: [(provider: Provider, session: SessionInfo, span: DateInterval, workspaces: [String])] = []
        for (provider, log) in logs {
            let file = Workspace.file(log.session.logPath)
            guard let span = log.span(logCreated: file?.createdAt, logModified: file?.modifiedAt, grace: spanGrace) else { continue }
            var seen = Set<String>()
            let workspaces = log.workingFolders.compactMap(Workspace.root(of:))
                .filter { !Workspace.isSkipped($0, home: home) && seen.insert($0).inserted }
            spans.append((provider, log.session, span, workspaces))
        }

        var problems: [Int: Set<String>] = [:], failures: [Provider: [String]] = [:]
        let sessions = Dictionary(grouping: spans.indices.flatMap { i in spans[i].workspaces.map { ($0, i) } }, by: \.0)
        for (workspace, members) in sessions.sorted(by: { $0.key < $1.key }) {
            let walk = Workspace.walk(workspace, limit: walkLimit)
            var observed: [Observed] = []
            for (_, i) in members {
                let (provider, session, span, _) = spans[i]
                problems[i, default: []].formUnion(walk.problems)
                for file in walk.files {
                    let kind: Observed.Kind
                    if let created = file.createdAt, span.contains(created) {
                        kind = .appeared
                    } else if span.contains(file.modifiedAt) {
                        kind = .changed
                    } else {
                        continue
                    }
                    let checkout = Projects.checkout(path: file.path)
                    observed.append(Observed(
                        path: file.path, kind: kind, logPath: session.logPath, sessionID: session.id, provider: provider,
                        span: span, workspace: workspace, size: file.size, createdAt: file.createdAt, modifiedAt: file.modifiedAt,
                        device: file.device, inode: file.inode, repository: checkout?.repository, checkout: checkout?.folder,
                        observedAt: now))
                }
            }
            do {
                try registry.transaction { try registry.add(observed) }
            } catch {
                for (_, i) in members { failures[spans[i].provider, default: []].append("\(workspace): observations not recorded: \(error)") }
            }
        }
        for (i, (provider, session, span, workspaces)) in spans.enumerated() {
            do {
                try registry.transaction {
                    try registry.recordSpan(of: session, provider: provider, span: span, workspaces: workspaces,
                                            problems: (problems[i] ?? []).sorted())
                }
            } catch {
                failures[provider, default: []].append("\(session.logPath): span not recorded: \(error)")
            }
        }
        return failures
    }
}

extension Registry {
    /// Records a session's span and workspaces, as last derived from its log, with what its
    /// workspaces' walks couldn't see. Derived, so refreshed each time the log is read.
    func recordSpan(of session: SessionInfo, provider: Provider, span: DateInterval, workspaces: [String], problems: [String]) throws {
        let json = { (list: [String]) in String(decoding: try JSONEncoder().encode(list), as: UTF8.self) }
        try db.run("""
            INSERT INTO spans (log_path, session_id, provider, start_at, end_at, workspaces, problems) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(log_path) DO UPDATE SET session_id = excluded.session_id, provider = excluded.provider,
                start_at = excluded.start_at, end_at = excluded.end_at, workspaces = excluded.workspaces, problems = excluded.problems
            """, [session.logPath, session.id, provider.rawValue, span.start, span.end, try json(workspaces),
                  problems.isEmpty ? nil : try json(problems)])
    }

    /// Records observations the first time Gleaner sees each file during each session: one already
    /// recorded for the session is never rewritten.
    func add(_ observations: [Observed]) throws {
        for o in observations {
            try db.run("""
                INSERT OR IGNORE INTO observations (log_path, path, session_id, kind, workspace, size, created_at, modified_at,
                    device, inode, repository, checkout, observed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [o.logPath, o.path, o.sessionID, o.kind.rawValue, o.workspace, o.size, o.createdAt, o.modifiedAt,
                      o.device, o.inode, o.repository, o.checkout, o.observedAt])
        }
    }

    /// Every observation, with its session's agent, title and span.
    public func observations() throws -> [Observed] {
        try db.rows("""
            SELECT o.log_path, o.path, o.session_id, o.kind, o.workspace, o.size, o.created_at, o.modified_at, o.device, o.inode,
                   o.repository, o.checkout, o.observed_at, s.provider, s.title, p.start_at, p.end_at
            FROM observations o LEFT JOIN sessions s ON s.id = o.session_id LEFT JOIN spans p ON p.log_path = o.log_path
            ORDER BY o.path, o.log_path
            """).compactMap { row in
            guard let path = row["path"] as? String, let logPath = row["log_path"] as? String,
                  let kind = Observed.Kind(rawValue: row["kind"] as? String ?? ""),
                  let modified = row["modified_at"] as? Double else { return nil }
            let date = { (key: String) in (row[key] as? Double).map(Date.init(timeIntervalSince1970:)) }
            return Observed(
                path: path, kind: kind, logPath: logPath, sessionID: row["session_id"] as? String ?? "",
                provider: Provider(rawValue: row["provider"] as? String ?? "") ?? .claudeCode, sessionTitle: row["title"] as? String,
                span: date("start_at").flatMap { start in date("end_at").map { DateInterval(start: start, end: max(start, $0)) } },
                workspace: row["workspace"] as? String ?? "", size: row["size"] as? Int64 ?? 0, createdAt: date("created_at"),
                modifiedAt: Date(timeIntervalSince1970: modified), device: row["device"] as? Int64 ?? 0, inode: row["inode"] as? Int64 ?? 0,
                repository: row["repository"] as? String, checkout: row["checkout"] as? String,
                observedAt: date("observed_at") ?? Date(timeIntervalSince1970: 0))
        }
    }

    /// What the walks of each agent's sessions' workspaces couldn't see, as recorded when each
    /// session was last read, so it is reported on every run, not only by the run that walked.
    public func workspaceProblems() throws -> [Provider: [String]] {
        var problems: [Provider: Set<String>] = [:]
        for row in try db.rows("SELECT provider, problems FROM spans WHERE problems IS NOT NULL") {
            guard let provider = Provider(rawValue: row["provider"] as? String ?? ""), let text = row["problems"] as? String,
                  let list = try? JSONDecoder().decode([String].self, from: Data(text.utf8)) else { continue }
            problems[provider, default: []].formUnion(list)
        }
        return problems.mapValues { $0.sorted() }
    }
}
