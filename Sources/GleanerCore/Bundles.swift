import CryptoKit
import Foundation

/// How a file came with a delivered folder (SPEC §5.4). A reply that names a folder names what is
/// in it, so each of its files is delivered by that reply, traceable to it through the folder.
public struct Membership: Sendable, Equatable {
    /// The folder's delivery, and the folder as its reply named it.
    public var folderDelivery: String
    public var folder: String

    public init(folderDelivery: String, folder: String) {
        self.folderDelivery = folderDelivery
        self.folder = folder
    }

    /// The id of the delivery of `path` handed over in the folder delivery `folder`, the same on
    /// every read.
    static func id(folder: String, path: String) -> String {
        SHA256.hash(data: Data("member\n\(folder)\n\(path)".utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `file`, found in a folder a reply named at `deliveredAt`, was handed over with it,
    /// from its dates alone: only when it was created by then and its inode last changed by then,
    /// so what was listed is what the folder held at the reply. A file whose inode changed after the
    /// reply isn't shown to have been there: one moved or linked in, or copied in keeping its dates,
    /// carries a creation date from before the reply, and only its change date tells. It is missed
    /// rather than claimed, as `Workspace.place` misses one. On a volume without creation dates the
    /// change date alone decides. `grace` absorbs the granularity of the log's clock and the disk's.
    static func handedOver(_ file: Workspace.File, deliveredAt: Date, grace: TimeInterval) -> Bool {
        let by = deliveredAt.addingTimeInterval(grace)
        return file.changedAt <= by && (file.createdAt ?? file.changedAt) <= by
    }
}

/// What listing a delivered folder's files found, recorded once, when Gleaner first listed it
/// (SPEC §5.4).
public struct Unpacking: Sendable, Equatable {
    public var listedAt: Date
    /// How many files were handed over in it.
    public var members: Int
    /// Why its files aren't listed (the home folder, a folder directly in it, a project's own
    /// folder…), in words that complete "it is"; nil when they are.
    public var notUnpacked: String?
    /// What the listing couldn't see: it stopped at its bound, or a folder in it couldn't be read.
    public var problems: [String]
    /// The Git repositories inside it, each another project, whose files the listing left out:
    /// where each is in the folder.
    public var repositories: [String]

    public init(listedAt: Date, members: Int, notUnpacked: String?, problems: [String], repositories: [String] = []) {
        self.listedAt = listedAt
        self.members = members
        self.notUnpacked = notUnpacked
        self.problems = problems
        self.repositories = repositories
    }

    /// Whether the folder isn't unpacked because handing it over points at a project: it is a
    /// repository's own folder or the one its conversation worked in, or holds that one.
    public var pointsAtProject: Bool {
        notUnpacked.map([Self.checkout, Self.repository, Self.workedIn, Self.holdingWorkedIn].contains) ?? false
    }

    static let checkout = "a Git checkout’s folder"
    static let repository = "a Git repository"
    static let workedIn = "the folder its conversation worked in"
    static let holdingWorkedIn = "a folder holding the one its conversation worked in"
    static let package = "a package, which Finder shows as one file"
}

extension Indexer {
    /// What listing a delivered folder's files does now (SPEC §5.4).
    enum Listability: Equatable {
        case list
        /// Its files are never listed, for this reason, kept with the folder.
        case never(String)
        /// Not now: the folder is gone, isn't one, or can't be read. Its listing waits for a run
        /// that can make it, since whenever that is, it claims only what the dates show.
        case later(String, isProblem: Bool)
    }

    /// A file Gleaner read while reading the logs, as it was then: what completes the listings of
    /// the folders that hold it, once the run has listed them.
    struct Read {
        var path: String
        var capture: Capture
        var file: Workspace.File?
    }

    /// Lists the files of each delivered folder not listed yet (SPEC §5.4): a folder delivered since
    /// the last run, or one a library held before Gleaner listed folders, or one that couldn't be
    /// listed before. A folder is walked as a workspace is (`Workspace.walk`), by metadata only,
    /// once per run whatever the number of its deliveries, without entering a repository inside it,
    /// which is another project; each delivery takes the files and packages its reply's time shows
    /// were there, and never the hidden ones. A package is one of them, a folder, captured as a
    /// delivered folder is. A folder that is never unpacked (`listability`) keeps why. A delivery's
    /// listing and its files are recorded together, so a listing that couldn't be recorded is made
    /// next run, as is one of a folder that is gone or can't be read now. Only the folders of
    /// `providers` are listed. Returns, per agent, what couldn't be listed or recorded, and the
    /// folders whose listing waits because they are gone, with why.
    func unpack(at now: Date, providers: Set<Provider>) -> (problems: [Provider: [String]], gone: [Provider: [String]]) {
        let pending: [Registry.PendingFolder]
        do {
            pending = try registry.pendingFolders().filter { providers.contains($0.provider) }
        } catch {
            return (Dictionary(uniqueKeysWithValues: providers.map { ($0, ["delivered folders not listed: \(error)"]) }), [:])
        }
        var problems: [Provider: [String]] = [:], gone: [Provider: [String]] = [:], walks: [String: Workspace.Walk] = [:]
        for folder in pending {
            var unpacking = Unpacking(listedAt: now, members: 0, notUnpacked: nil, problems: [])
            var members: [(file: Workspace.File, provenance: Provenance)] = []
            switch listability(folder) {
            case .later(let reason, let isProblem):
                if isProblem {
                    problems[folder.provider, default: []].append("\(folder.path): not listed yet, \(reason)")
                } else {
                    gone[folder.provider, default: []].append("\(folder.path): not listed yet, \(reason)")
                }
                continue
            case .never(let reason):
                unpacking.notUnpacked = reason
            case .list:
                let walk = walks[folder.path] ?? Workspace.walk(folder.path, limit: walkLimit, entersRepositories: false)
                walks[folder.path] = walk
                guard walk.listedRoot, let deliveredAt = folder.deliveredAt else {
                    problems[folder.provider, default: []].append("\(folder.path): not listed yet, couldn’t be read")
                    continue
                }
                let named = namedIdentities(in: folder)
                unpacking.problems = walk.problems
                unpacking.repositories = walk.repositories.map { String($0.dropFirst(folder.path.count + 1)) }
                // A package is captured as a delivered folder is: seen at delivery when listed within
                // the live window of a reply that came after its last write (SPEC §5.1).
                let live = now.timeIntervalSince(deliveredAt) <= liveWindow
                members = walk.files.compactMap { file in
                    guard !(file.path as NSString).lastPathComponent.hasPrefix("."),
                          Membership.handedOver(file, deliveredAt: deliveredAt, grace: clockTolerance) else { return nil }
                    var file = file
                    if let names = named[FileIdentity(device: file.device, inode: file.inode)], !names.contains(file.path) {
                        file.path = names.min()!
                    }
                    guard file.isPackage else { return (file, .listed) }
                    let seen = live && file.modifiedAt <= deliveredAt.addingTimeInterval(clockTolerance)
                    return (file, seen ? .atDelivery : .firstSeenAfterDelivery)
                }
                unpacking.members = members.count
            }
            do {
                try registry.transaction { try registry.record(unpacking, members: members, of: folder.id) }
            } catch {
                problems[folder.provider, default: []].append("\(folder.path): its files not recorded: \(error)")
            }
        }
        return (problems, gone)
    }

    /// The files in `folder` that its reply's log, or any reply naming a path in it, named in
    /// another spelling (another case, a linked folder), by identity: a walked file is listed
    /// under the name a reply gave it, so a reply that named the folder and the file delivers it
    /// once, as named, and its deliveries number together.
    private func namedIdentities(in folder: Registry.PendingFolder) -> [FileIdentity: [String]] {
        let root = Workspace.resolved(folder.path) + "/"
        var named: [FileIdentity: [String]] = [:]
        for path in (try? registry.namedPaths(logs: [folder.logPath], under: folder.path)) ?? []
        where Workspace.resolved(path).hasPrefix(root) {
            if let id = FileIdentity(path) { named[id, default: []].append(path) }
        }
        return named
    }

    /// Whether a delivered folder's files are listed (SPEC §5.4). Never: a folder named by a reply
    /// without a time, which dates can't be compared with; a link, since no link is followed; a
    /// folder a workspace walk skips; one that holds a person's things rather than one deliverable,
    /// as the home, a volume and a cloud drive do, or a folder directly in one of them, decided by
    /// depth, not names; a cache, or a folder inside a cache or a hidden folder, counted from the
    /// folder holding the Git checkout it is in, so the checkout's own name counts (`~/.config`
    /// kept as a repository is hidden) and an agent's worktree kept in a hidden folder
    /// (`.claude/worktrees/<name>`) is unpacked as its repository's folders are, as a workspace
    /// walk walks it; a package, which Finder shows as one file and no walk enters; a Git
    /// repository's own folder; or the folder its conversation worked in or its checkout, or one
    /// holding either, since handing over the project points at the project, and what changed
    /// there is observed instead (SPEC §5.3). A repository inside it is another project, which its
    /// listing leaves out. Not now: a folder gone, no longer one, or that can't be read. Compared
    /// as the disk has them, as `Workspace.skipped` compares.
    func listability(_ folder: Registry.PendingFolder) -> Listability {
        guard folder.deliveredAt != nil else { return .never("named by a reply without a time") }
        var info = Darwin.stat()
        if lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFLNK { return .never("a link") }
        switch Locator.stat(folder.path).kind {
        case .directory: break
        case .missing: return .later("no longer there", isProblem: false)
        case .file, .special: return .later("no longer a folder", isProblem: false)
        case .unreadable: return .later("couldn’t be read", isProblem: true)
        }
        if let reason = Workspace.skipped(folder.path, home: home, own: ownFolders) { return .never(reason) }
        let path = Workspace.resolved(folder.path)
        let homes = Set([home, NSHomeDirectory()].map(Workspace.resolved))

        func device(_ path: String) -> dev_t? {
            var info = Darwin.stat()
            return fstatat(AT_FDCWD, path, &info, 0) == 0 ? info.st_dev : nil
        }
        /// What a folder is when it holds a person's things, as the home does.
        func whole(_ folder: String) -> String? {
            if homes.contains(folder) { return "the home" }
            let parent = (folder as NSString).deletingLastPathComponent
            if homes.contains(where: { [$0 + "/Library/CloudStorage", $0 + "/Library/Mobile Documents"].contains(parent) }) { return "a cloud drive" }
            return folder == "/" || device(folder) != device(parent) ? "a volume" : nil
        }
        // The home itself is skipped above.
        if let whole = whole(path) { return .never(whole) }
        if let whole = whole((path as NSString).deletingLastPathComponent) {
            return .never(whole == "a volume" ? "a folder directly on a volume" : "a folder directly in \(whole)")
        }

        let checkout = Projects.resolve(path)?.folder
        let boundary = checkout.map { ($0 as NSString).deletingLastPathComponent } ?? homes.first { path.hasPrefix($0 + "/") } ?? "/"
        var inner = path
        while inner != boundary, inner != "/", !inner.isEmpty {
            let name = (inner as NSString).lastPathComponent
            if Workspace.caches.contains(name) || FileManager.default.fileExists(atPath: inner + "/CACHEDIR.TAG") {
                return .never(inner == path ? "a cache a tool left" : "inside a cache a tool left")
            }
            // The folder's own name is checked by `Workspace.skipped`.
            if name.hasPrefix(".") { return .never("inside a hidden folder") }
            inner = (inner as NSString).deletingLastPathComponent
        }
        if Workspace.isPackage((path as NSString).lastPathComponent) { return .never(Unpacking.package) }

        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return .later("couldn’t be read", isProblem: true)
        }
        if names.contains(".git") { return .never(Unpacking.checkout) }
        if Workspace.isRepository(Set(names)) { return .never(Unpacking.repository) }
        let roots = folder.workingFolders.flatMap { [Workspace.resolved($0), Workspace.resolved(Workspace.root(of: $0) ?? $0)] }
        if roots.contains(path) { return .never(Unpacking.workedIn) }
        if roots.contains(where: { $0.hasPrefix(path + "/") }) { return .never(Unpacking.holdingWorkedIn) }
        return .list
    }

    /// Completes the rows of `path`'s deliveries in folders whose listing the file still matches,
    /// with `read`, the bytes Gleaner read of it as `file` (SPEC §5.4): at delivery only when the
    /// read came within the live window of the reply, and the file, unchanged since it was listed,
    /// was last written and its inode last changed by the reply's time (§5.1); else first seen
    /// after it. Nothing is completed when the file changed while it was read.
    func completeMembers(of path: String, with read: Capture, file: Workspace.File?) throws {
        guard let file, read.sha256 != nil, read.size == file.size, Workspace.file(at: path) == file else { return }
        for member in try registry.listedMembers(of: path, as: file) {
            let live = member.deliveredAt.map { reply in
                let by = reply.addingTimeInterval(clockTolerance)
                return read.observedAt.timeIntervalSince(reply) <= liveWindow && file.modifiedAt <= by && file.changedAt <= by
            } ?? false
            try registry.complete(member: member.folder, path: path, with: read, provenance: live ? .atDelivery : .firstSeenAfterDelivery)
        }
    }
}

extension Registry {
    /// A delivered folder whose files wait to be listed, with its reply's log and the folders its
    /// conversation worked in, as its records and its walk name them.
    struct PendingFolder {
        var id: String
        var path: String
        var deliveredAt: Date?
        var provider: Provider
        var logPath: String
        var workingFolders: [String]
    }

    /// The deliveries of a folder (what was at the path when Gleaner first looked) not listed yet.
    func pendingFolders() throws -> [PendingFolder] {
        var worked: [String: [String]] = [:]
        return try db.rows("""
            SELECT d.id, d.path, d.delivered_at, d.log_path, s.provider, s.cwd AS session_cwd
            FROM deliveries d JOIN captures c ON c.delivery_id = d.id JOIN sessions s ON s.id = d.session_id
            WHERE c.kind = 'directory' AND NOT EXISTS (SELECT 1 FROM listings l WHERE l.delivery_id = d.id)
            ORDER BY d.path, d.delivered_at
            """).compactMap { row in
            guard let id = row["id"] as? String, let path = row["path"] as? String, let log = row["log_path"] as? String,
                  let provider = Provider(rawValue: row["provider"] as? String ?? "") else { return nil }
            if worked[log] == nil {
                let cwds = try db.rows("SELECT DISTINCT cwd FROM deliveries WHERE log_path = ? AND cwd IS NOT NULL", [log])
                    .compactMap { $0["cwd"] as? String }
                let walked = try db.rows("SELECT workspaces FROM spans WHERE log_path = ?", [log]).first
                    .map { Self.list($0["workspaces"] as? String) } ?? []
                worked[log] = cwds + walked
            }
            return PendingFolder(id: id, path: path, deliveredAt: (row["delivered_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
                                 provider: provider, logPath: log,
                                 workingFolders: ([row["session_cwd"] as? String].compactMap { $0 } + worked[log]!).map(standardPath))
        }
    }

    /// Records what listing a folder delivery's files found, and each file handed over in it, the
    /// first time: one already recorded is never rewritten. A file waits, listed, for its first
    /// read; a package, a folder, is recorded as seen at the listing, with its `provenance`.
    func record(_ unpacking: Unpacking, members: [(file: Workspace.File, provenance: Provenance)], of id: String) throws {
        let json = { (list: [String]) in list.isEmpty ? nil : String(decoding: try JSONEncoder().encode(list), as: UTF8.self) }
        try db.run("""
            INSERT OR IGNORE INTO listings (delivery_id, listed_at, members, not_unpacked, problems, repositories)
            VALUES (?, ?, ?, ?, ?, ?)
            """, [id, unpacking.listedAt, unpacking.members, unpacking.notUnpacked, try json(unpacking.problems),
                  try json(unpacking.repositories)])
        for (file, provenance) in members {
            try db.run("""
                INSERT OR IGNORE INTO members (delivery_id, path, kind, size, created_at, modified_at, changed_at, device, inode,
                    listed_at, observed_at, provenance) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [id, file.path, (file.isPackage ? LocatorState.Kind.directory : .file).rawValue, file.size, file.createdAt,
                      file.modifiedAt, file.changedAt, file.device, file.inode, unpacking.listedAt,
                      file.isPackage ? unpacking.listedAt : nil, provenance.rawValue])
        }
    }

    /// Each file handed over in a delivered folder, as a delivery of its own (SPEC §5.4): a copy of
    /// its folder's delivery (`folders`, by id), whose reply, session, request, time and evidence
    /// it carries without reading them again for each file, with its own id, path and capture,
    /// listed or read; a package's, a folder's, with no size and none of its files listed. Only the
    /// files at `path`, when given. `after` places them after the rows `artifacts` read before, so
    /// deliveries of one time keep the order they were read in. A file whose folder delivery a
    /// reread dropped goes with it.
    func members(at path: String?, folders: [String: Found], after order: Int) throws -> [Found] {
        try db.rows("""
            SELECT delivery_id, path, kind, size, created_at, modified_at, listed_at, sha256, observed_at, saved_at, provenance
            FROM members
            """ + (path == nil ? "" : " WHERE path = ?") + " ORDER BY path, delivery_id", path.map { [$0] } ?? [])
        .enumerated().compactMap { index, row in
            guard let id = row["delivery_id"] as? String, let folder = folders[id], let path = row["path"] as? String,
                  let listed = row["listed_at"] as? Double else { return nil }
            let kind = LocatorState.Kind(rawValue: row["kind"] as? String ?? "") ?? .file
            let date = { (key: String) in (row[key] as? Double).map(Date.init(timeIntervalSince1970:)) }
            var found = folder
            found.delivery.id = Membership.id(folder: id, path: path)
            found.delivery.path = path
            var capture = Capture(
                sha256: row["sha256"] as? String, size: kind == .directory ? nil : row["size"] as? Int64,
                modifiedAt: date("modified_at"), observedAt: date("observed_at") ?? Date(timeIntervalSince1970: listed),
                savedAt: date("saved_at"), provenance: Provenance(rawValue: row["provenance"] as? String ?? "") ?? .listed, kind: kind)
            capture.createdAt = date("created_at")
            found.delivery.capture = capture
            found.delivery.member = Membership(folderDelivery: id, folder: folder.delivery.path)
            found.delivery.unpacking = kind == .directory
                ? Unpacking(listedAt: Date(timeIntervalSince1970: listed), members: 0, notUnpacked: Unpacking.package, problems: [])
                : nil
            found.order = order + index
            return found
        }
    }

    /// One delivery of a file per reply: a reply that names a file and also a folder holding it
    /// delivers the file once, as named; one naming two folders that hold it, once, in the
    /// innermost.
    static func onePerReply(_ found: [Found]) -> [Found] {
        guard found.contains(where: { $0.delivery.member != nil }) else { return found }
        func reply(_ d: Delivery) -> String {
            d.logPath + "\n" + (d.replyLine.map { "\($0)" } ?? d.deliveredAt.map { "\($0.timeIntervalSince1970)" } ?? d.id)
        }
        let named = found.filter { $0.delivery.member == nil }
        let replies = Set(named.map { reply($0.delivery) })
        var inFolders: [String: Found] = [:]
        for item in found {
            guard let member = item.delivery.member, !replies.contains(reply(item.delivery)) else { continue }
            if let other = inFolders[reply(item.delivery)], other.delivery.member!.folder.count >= member.folder.count { continue }
            inFolders[reply(item.delivery)] = item
        }
        return named + inFolders.values
    }

    /// A delivered folder's row for `path` listed and not read yet whose listing the file still
    /// matches: the same inode, creation and modification dates, and size, on the volume the path
    /// names. The device number isn't compared: a volume mounted again may be given another. With
    /// the time of the folder's reply.
    struct ListedMember {
        var folder: String
        var deliveredAt: Date?
    }

    func listedMembers(of path: String, as file: Workspace.File) throws -> [ListedMember] {
        try db.rows("""
            SELECT m.delivery_id, d.delivered_at FROM members m LEFT JOIN deliveries d ON d.id = m.delivery_id
            WHERE m.path = ? AND m.provenance = 'listed' AND m.size = ? AND m.modified_at = ? AND m.created_at IS ? AND m.inode = ?
            """, [path, file.size, file.modifiedAt, file.createdAt, file.inode]).compactMap { row in
            (row["delivery_id"] as? String).map {
                ListedMember(folder: $0, deliveredAt: (row["delivered_at"] as? Double).map(Date.init(timeIntervalSince1970:)))
            }
        }
    }

    /// The hash recorded for a file handed over in a folder: nil until Gleaner read it as listed.
    public func sha256(of member: Membership, path: String) throws -> String? {
        try db.rows("SELECT sha256 FROM members WHERE delivery_id = ? AND path = ?", [member.folderDelivery, path]).first?["sha256"] as? String
    }

    /// Completes a listed row once with what Gleaner first read of its file.
    func complete(member folder: String, path: String, with read: Capture, provenance: Provenance) throws {
        try db.run("""
            UPDATE members SET sha256 = ?, observed_at = ?, saved_at = ?, provenance = ?
            WHERE delivery_id = ? AND path = ? AND sha256 IS NULL
            """, [read.sha256, read.observedAt, read.savedAt, provenance.rawValue, folder, path])
    }

    /// Per agent, the delivered folders whose listing couldn't see everything, with why, and those
    /// not unpacked, with why: kept with each listing, so they are reported on every run.
    public func unpackings() throws -> (problems: [Provider: [String]], notUnpacked: [Provider: [String]]) {
        var problems: [Provider: Set<String>] = [:], notUnpacked: [Provider: Set<String>] = [:]
        for row in try db.rows("""
            SELECT s.provider, d.path, l.not_unpacked, l.problems FROM listings l
            JOIN deliveries d ON d.id = l.delivery_id JOIN sessions s ON s.id = d.session_id
            WHERE l.not_unpacked IS NOT NULL OR l.problems IS NOT NULL
            """) {
            guard let provider = Provider(rawValue: row["provider"] as? String ?? ""), let path = row["path"] as? String else { continue }
            if let reason = row["not_unpacked"] as? String { notUnpacked[provider, default: []].insert("\(path): not unpacked, \(reason)") }
            problems[provider, default: []].formUnion(Self.list(row["problems"] as? String))
        }
        return (problems.mapValues { $0.sorted() }, notUnpacked.mapValues { $0.sorted() })
    }
}
