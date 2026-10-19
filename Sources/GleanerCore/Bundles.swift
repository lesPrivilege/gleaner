import CryptoKit
import Foundation

/// How a file came with a delivered folder (SPEC §5.4). A reply that names a folder names what is
/// in it, so each of its files is delivered by that reply, traceable to it through the folder.
public struct Membership: Sendable, Equatable {
    /// The folder's delivery, and the folder as its reply named it.
    public var folderDelivery: String
    public var folder: String
    /// The file's inode changed after the reply, so it may have been changed or replaced since it
    /// was handed over. Decided when the folder was listed, and never rewritten.
    public var changedSince: Bool

    public init(folderDelivery: String, folder: String, changedSince: Bool) {
        self.folderDelivery = folderDelivery
        self.folder = folder
        self.changedSince = changedSince
    }

    /// The id of the delivery of `path` handed over in the folder delivery `folder`, the same on
    /// every read.
    static func id(folder: String, path: String) -> String {
        SHA256.hash(data: Data("member\n\(folder)\n\(path)".utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `file`, found in a folder a reply named at `deliveredAt`, was handed over with it,
    /// from its dates alone: created by then, it was; created later, it was added after and isn't
    /// (nil). One handed over whose inode changed after the reply may have been changed or replaced
    /// since (true). A volume without creation dates shows only that: a file whose inode changed
    /// after the reply isn't shown to have been there, and isn't counted. `grace` absorbs the
    /// granularity of the log's clock and the disk's.
    static func changedSince(_ file: Workspace.File, deliveredAt: Date, grace: TimeInterval) -> Bool? {
        let by = deliveredAt.addingTimeInterval(grace)
        let changed = file.changedAt > by
        guard let created = file.createdAt else { return changed ? nil : false }
        return created <= by ? changed : nil
    }
}

/// What listing a delivered folder's files found, recorded once, when Gleaner first listed it
/// (SPEC §5.4).
public struct Unpacking: Sendable, Equatable {
    public var listedAt: Date
    /// How many files were handed over in it.
    public var members: Int
    /// Why its files aren't listed (the home folder, a folder directly in it, a project's own
    /// folder…); nil when they are.
    public var notUnpacked: String?
    /// What the listing couldn't see: it stopped at its bound, or a folder in it couldn't be read.
    public var problems: [String]

    public init(listedAt: Date, members: Int, notUnpacked: String?, problems: [String]) {
        self.listedAt = listedAt
        self.members = members
        self.notUnpacked = notUnpacked
        self.problems = problems
    }
}

extension Indexer {
    /// Lists the files of each delivered folder not listed yet (SPEC §5.4): a folder delivered since
    /// the last run, or one a library held before Gleaner listed folders. A folder is walked as a
    /// workspace is (`Workspace.walk`), by metadata only, once per run whatever the number of its
    /// deliveries; each delivery takes the files its reply's time shows were there, and never the
    /// hidden ones. A folder that is a project's own, or holds one, the home or a folder directly in
    /// it, or what a workspace walk skips, isn't unpacked, and why is kept. A delivery's listing and
    /// its files are recorded together, so a listing that couldn't be recorded is made next run.
    /// Only the folders of `providers` are listed. Returns, per agent, what couldn't be recorded.
    func unpack(at now: Date, providers: Set<Provider>) -> [Provider: [String]] {
        let pending: [Registry.PendingFolder]
        do {
            pending = try registry.pendingFolders().filter { providers.contains($0.provider) }
        } catch {
            return Dictionary(uniqueKeysWithValues: providers.map { ($0, ["delivered folders not listed: \(error)"]) })
        }
        var failures: [Provider: [String]] = [:], walks: [String: Workspace.Walk] = [:]
        for folder in pending {
            var unpacking = Unpacking(listedAt: now, members: 0, notUnpacked: notUnpacked(folder), problems: [])
            var members: [(file: Workspace.File, changedSince: Bool)] = []
            if unpacking.notUnpacked == nil, let deliveredAt = folder.deliveredAt {
                let walk = walks[folder.path] ?? Workspace.walk(folder.path, limit: walkLimit, stopsAtCheckout: true)
                walks[folder.path] = walk
                if walk.checkout != nil {
                    unpacking.notUnpacked = "a folder holding a Git checkout"
                } else {
                    unpacking.problems = walk.problems
                    members = walk.files.compactMap { file in
                        guard !(file.path as NSString).lastPathComponent.hasPrefix(".") else { return nil }
                        return Membership.changedSince(file, deliveredAt: deliveredAt, grace: clockTolerance).map { (file: file, changedSince: $0) }
                    }
                }
            }
            do {
                try registry.transaction { try registry.record(unpacking, members: members, of: folder.id) }
            } catch {
                failures[folder.provider, default: []].append("\(folder.path): its files not recorded: \(error)")
            }
        }
        return failures
    }

    /// Why a delivered folder's files aren't listed, or nil when they are. Handing over a project's
    /// own folder (a Git checkout's, or the one its conversation worked in), or a folder holding
    /// one, points at the project, and what changed there is observed instead (SPEC §5.3). Nor are
    /// the home folder, a folder directly in it, which holds the person's things rather than one
    /// deliverable, or a folder a workspace walk skips or doesn't enter. Compared as the disk has
    /// them, as `Workspace.skipped` compares.
    func notUnpacked(_ folder: Registry.PendingFolder) -> String? {
        guard folder.deliveredAt != nil else { return "its reply carries no time" }
        guard Locator.stat(folder.path).kind == .directory else { return "no longer a folder" }
        if let reason = Workspace.skipped(folder.path, home: home, own: ownFolders) { return reason }
        let path = Workspace.resolved(folder.path)
        if Set([home, NSHomeDirectory()].map(Workspace.resolved)).contains((path as NSString).deletingLastPathComponent) {
            return "a folder directly in the home"
        }
        if Workspace.caches.contains((path as NSString).lastPathComponent) || FileManager.default.fileExists(atPath: path + "/CACHEDIR.TAG") {
            return "a cache a tool left"
        }
        if FileManager.default.fileExists(atPath: path + "/.git") { return "a Git checkout’s folder" }
        let roots = folder.workingFolders.map { Workspace.resolved(Workspace.root(of: $0) ?? $0) }
        if roots.contains(path) { return "the folder its conversation worked in" }
        if roots.contains(where: { $0.hasPrefix(path == "/" ? "/" : path + "/") }) { return "a folder holding the one its conversation worked in" }
        return nil
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
    /// A delivered folder whose files wait to be listed, with the folders its conversation worked
    /// in, as its records and its walk name them.
    struct PendingFolder {
        var id: String
        var path: String
        var deliveredAt: Date?
        var provider: Provider
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
                                 provider: provider,
                                 workingFolders: ([row["session_cwd"] as? String].compactMap { $0 } + worked[log]!).map(standardPath))
        }
    }

    /// Records what listing a folder delivery's files found, and each file handed over in it, the
    /// first time: one already recorded is never rewritten.
    func record(_ unpacking: Unpacking, members: [(file: Workspace.File, changedSince: Bool)], of id: String) throws {
        try db.run("INSERT OR IGNORE INTO listings (delivery_id, listed_at, not_unpacked, problems) VALUES (?, ?, ?, ?)",
                   [id, unpacking.listedAt, unpacking.notUnpacked,
                    unpacking.problems.isEmpty ? nil : String(decoding: try JSONEncoder().encode(unpacking.problems), as: UTF8.self)])
        for (file, changed) in members {
            try db.run("""
                INSERT OR IGNORE INTO members (delivery_id, path, size, created_at, modified_at, changed_at, device, inode,
                    changed_since, listed_at, provenance) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [id, file.path, file.size, file.createdAt, file.modifiedAt, file.changedAt, file.device, file.inode,
                      changed ? 1 : 0, unpacking.listedAt, Provenance.listed.rawValue])
        }
    }

    /// Each file handed over in a delivered folder, as a delivery of its own (SPEC §5.4): its
    /// folder's reply, session, request, time and evidence, and its own capture, listed or read.
    /// `after` places them after the rows `artifacts` read before, so deliveries of one time keep
    /// the order they were read in. A folder delivery that a reread dropped takes its files with it.
    func members(after order: Int) throws -> [Found] {
        var evidence: [String: [Evidence]] = [:]
        return try db.rows("""
            SELECT m.path, m.size, m.modified_at, m.changed_since, m.listed_at, m.sha256, m.observed_at, m.saved_at, m.provenance,
                   d.id, d.path AS folder, d.delivered_at, d.reply_line, d.reply_rank, d.cwd, d.request, d.evidence, d.model,
                   s.provider, s.title, d.log_path, d.session_id, s.cwd AS session_cwd, s.model_provider, c.repository, c.checkout
            FROM members m JOIN deliveries d ON d.id = m.delivery_id JOIN sessions s ON s.id = d.session_id
            LEFT JOIN captures c ON c.delivery_id = d.id
            ORDER BY m.path, d.delivered_at
            """).enumerated().compactMap { index, row in
            guard let path = row["path"] as? String, let folder = row["id"] as? String, let listed = row["listed_at"] as? Double
            else { return nil }
            if evidence[folder] == nil { evidence[folder] = Self.evidence(row["evidence"] as? String) }
            let capture = Capture(
                sha256: row["sha256"] as? String, size: row["size"] as? Int64,
                modifiedAt: (row["modified_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
                observedAt: Date(timeIntervalSince1970: row["observed_at"] as? Double ?? listed),
                savedAt: (row["saved_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
                provenance: Provenance(rawValue: row["provenance"] as? String ?? "") ?? .listed, kind: .file)
            var delivery = Self.delivery(row, id: Membership.id(folder: folder, path: path), path: path, capture: capture,
                                         evidence: evidence[folder]!)
            delivery.member = Membership(folderDelivery: folder, folder: row["folder"] as? String ?? "",
                                         changedSince: row["changed_since"] as? Int64 == 1)
            return Found(delivery: delivery, repository: row["repository"] as? String, checkout: row["checkout"] as? String,
                         order: order + index)
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

    /// A delivered folder's row for `path` not read yet whose listing the file still matches: the
    /// same identity, size and modification date. With the time of the folder's reply.
    struct ListedMember {
        var folder: String
        var deliveredAt: Date?
    }

    func listedMembers(of path: String, as file: Workspace.File) throws -> [ListedMember] {
        try db.rows("""
            SELECT m.delivery_id, d.delivered_at FROM members m LEFT JOIN deliveries d ON d.id = m.delivery_id
            WHERE m.path = ? AND m.sha256 IS NULL AND m.size = ? AND m.modified_at = ? AND m.device = ? AND m.inode = ?
            """, [path, file.size, file.modifiedAt, file.device, file.inode]).compactMap { row in
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
