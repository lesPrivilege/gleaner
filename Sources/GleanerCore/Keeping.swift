import CryptoKit
import Foundation

/// How a file observed during a session came into the library: the person kept it
/// (docs/design/review.md). No reply handed it over, so this is the person's admission, traced to
/// that decision and the session (SPEC Invariant 1). Its one revision is the file as the session's
/// observation recorded it, listed by size and dates as a delivered folder's file is (SPEC §5.4),
/// and read when the person acts on it.
public struct Keeping: Sendable, Equatable {
    /// When the person kept it.
    public var keptAt: Date
    /// Whether it appeared or changed during the session.
    public var observed: Observed.Kind

    public init(keptAt: Date, observed: Observed.Kind) {
        self.keptAt = keptAt
        self.observed = observed
    }

    /// The id of the revision kept from the observation of `path` during the session whose log is
    /// `logPath`, the same on every read.
    static func id(path: String, logPath: String) -> String {
        SHA256.hash(data: Data("kept\n\(logPath)\n\(path)".utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
}

extension Registry {
    /// Each file the person kept, as a revision of its own (`Keeping`): the observation it was kept
    /// from, with its session, dated by the file's last write then. Its capture is that
    /// observation's size and dates, `listed`, until Gleaner first reads the file while it is still
    /// as observed (`completeKept`); a package is a folder, never read. Only the file at `path`,
    /// when given. `after` places them after the rows `artifacts` read before.
    func kept(at path: String?, after order: Int) throws -> [Found] {
        try db.rows("""
            SELECT c.made_at, o.path, o.log_path, o.kind, o.workspace, o.size, o.created_at, o.modified_at, o.repository,
                   o.checkout, o.observed_at, p.session_id, p.provider, s.title, s.cwd AS session_cwd, s.model_provider,
                   k.sha256, k.observed_at AS read_at, k.saved_at, k.provenance
            FROM corrections c JOIN observations o ON o.path = c.subject AND o.log_path = c.target
            LEFT JOIN spans p ON p.log_path = o.log_path LEFT JOIN sessions s ON s.id = p.session_id
            LEFT JOIN kept k ON k.path = o.path AND k.log_path = o.log_path
            WHERE c.kind = 'kept'
            """ + (path == nil ? "" : " AND c.subject = ?") + " ORDER BY o.path", path.map { [$0] } ?? [])
        .enumerated().compactMap { index, row in
            guard let path = row["path"] as? String, let logPath = row["log_path"] as? String,
                  let kind = Observed.Kind(rawValue: row["kind"] as? String ?? ""), let modified = row["modified_at"] as? Double
            else { return nil }
            let date = { (key: String) in (row[key] as? Double).map(Date.init(timeIntervalSince1970:)) }
            let modifiedAt = Date(timeIntervalSince1970: modified)
            let package = Workspace.isPackage((path as NSString).lastPathComponent)
            var capture: Capture
            if let sha = row["sha256"] as? String {
                capture = Capture(sha256: sha, size: row["size"] as? Int64, modifiedAt: modifiedAt,
                                  observedAt: date("read_at") ?? modifiedAt, savedAt: date("saved_at"),
                                  provenance: Provenance(rawValue: row["provenance"] as? String ?? "") ?? .firstSeenAfterDelivery,
                                  kind: .file)
            } else {
                // A package is a folder: listed and never read, seen when it was observed.
                capture = Capture(sha256: nil, size: package ? nil : row["size"] as? Int64, modifiedAt: modifiedAt,
                                  observedAt: date("observed_at") ?? modifiedAt, savedAt: nil,
                                  provenance: package ? .firstSeenAfterDelivery : .listed, kind: package ? .directory : .file)
            }
            capture.createdAt = date("created_at")
            var delivery = Delivery(
                id: Keeping.id(path: path, logPath: logPath), number: 0, path: path, deliveredAt: modifiedAt, replyLine: nil,
                provider: Provider(rawValue: row["provider"] as? String ?? "") ?? .claudeCode,
                sessionID: row["session_id"] as? String ?? "", sessionCwd: row["session_cwd"] as? String,
                sessionTitle: row["title"] as? String, request: nil, cwd: row["workspace"] as? String, evidence: [],
                logPath: logPath, capture: capture, modelProvider: row["model_provider"] as? String)
            delivery.kept = Keeping(keptAt: date("made_at") ?? modifiedAt, observed: kind)
            return Found(delivery: delivery, repository: row["repository"] as? String, checkout: row["checkout"] as? String,
                         order: order + index)
        }
    }

    /// The observation a kept file at `path` was kept from, while it isn't read yet and the file
    /// still matches it: the same size, creation and modification dates and inode, as a listed file
    /// is matched (SPEC §5.4). With the date of the write it records.
    struct ListedKept {
        var logPath: String
        var modifiedAt: Date
    }

    func listedKept(of path: String, as file: Workspace.File) throws -> [ListedKept] {
        try db.rows("""
            SELECT o.log_path, o.modified_at FROM corrections c JOIN observations o ON o.path = c.subject AND o.log_path = c.target
            WHERE c.kind = 'kept' AND c.subject = ? AND o.size = ? AND o.modified_at = ? AND o.created_at IS ? AND o.inode = ?
                AND NOT EXISTS (SELECT 1 FROM kept k WHERE k.path = o.path AND k.log_path = o.log_path)
            """, [path, file.size, file.modifiedAt, file.createdAt, file.inode]).compactMap { row in
            guard let log = row["log_path"] as? String, let modified = row["modified_at"] as? Double else { return nil }
            return ListedKept(logPath: log, modifiedAt: Date(timeIntervalSince1970: modified))
        }
    }

    /// Completes a kept file's revision once with what Gleaner first read of it. Kept with its
    /// observation, which is never rewritten, so keeping the file again after an undo finds it.
    func complete(kept path: String, logPath: String, with read: Capture, provenance: Provenance) throws {
        try db.run("""
            INSERT OR IGNORE INTO kept (path, log_path, sha256, observed_at, saved_at, provenance) VALUES (?, ?, ?, ?, ?, ?)
            """, [path, logPath, read.sha256, read.observedAt, read.savedAt, provenance.rawValue])
    }

    /// The hash recorded for a revision listed and not read when it was made, a delivered folder's
    /// file or a kept one: nil until Gleaner read it as listed.
    public func sha256(ofListed delivery: Delivery) throws -> String? {
        if let member = delivery.member { return try sha256(of: member, path: delivery.path) }
        guard delivery.kept != nil else { return delivery.sha256 }
        return try db.rows("SELECT sha256 FROM kept WHERE path = ? AND log_path = ?", [delivery.path, delivery.logPath])
            .first?["sha256"] as? String
    }
}

extension Indexer {
    /// Completes the revisions kept from observations of `path` that the file still matches, with
    /// `read`, the bytes Gleaner read of it as `file`, as a listed file is completed (SPEC §5.4),
    /// with the write the observation recorded for the reply's time: at delivery only when the read
    /// came within the live window of that write and the file was last written and its inode last
    /// changed by then; else first seen after it.
    func completeKept(of path: String, with read: Capture, file: Workspace.File) throws {
        for kept in try registry.listedKept(of: path, as: file) {
            let by = kept.modifiedAt.addingTimeInterval(clockTolerance)
            let live = isLive(read.observedAt, after: kept.modifiedAt) && file.modifiedAt <= by && file.changedAt <= by
            try registry.complete(kept: path, logPath: kept.logPath, with: read, provenance: live ? .atDelivery : .firstSeenAfterDelivery)
        }
    }
}
