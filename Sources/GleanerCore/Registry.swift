import Foundation

/// Gleaner's index: sessions, deliveries (one per reply that names a path), and what Gleaner
/// captured of each delivery's bytes. Excerpts are stored redacted; whole logs never are.
public final class Registry: @unchecked Sendable {
    let db: Database

    /// Bump when extraction changes what is derived from logs (requests, evidence, admission, the
    /// record types a log holds that Gleaner doesn't know).
    /// Logs are then reread and derived fields refreshed; captures, which record what Gleaner saw
    /// at a moment in time, are never rewritten.
    public static let extractorVersion = 12

    public init(path: String) throws {
        db = try Database(path: path)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS log_files (
                path TEXT PRIMARY KEY, size INTEGER NOT NULL, mtime REAL NOT NULL, unknown_types TEXT);
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY, provider TEXT NOT NULL, title TEXT, cwd TEXT, log_path TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS deliveries (
                id TEXT PRIMARY KEY, session_id TEXT NOT NULL, path TEXT NOT NULL, delivered_at REAL,
                cwd TEXT, request TEXT, evidence TEXT NOT NULL, log_path TEXT, repository TEXT, checkout TEXT,
                reply_line INTEGER, reply_rank INTEGER);
            CREATE INDEX IF NOT EXISTS deliveries_path ON deliveries(path);
            CREATE TABLE IF NOT EXISTS captures (
                delivery_id TEXT PRIMARY KEY, sha256 TEXT, size INTEGER, mtime REAL, observed_at REAL NOT NULL,
                saved_at REAL, provenance TEXT NOT NULL, kind TEXT NOT NULL);
            """)
        // Each delivery names the log it came from: two logs can share a session id.
        if try !db.rows("PRAGMA table_info(deliveries)").contains(where: { $0["name"] as? String == "log_path" }) {
            try db.execute("""
                ALTER TABLE deliveries ADD COLUMN log_path TEXT;
                UPDATE deliveries SET log_path = (SELECT log_path FROM sessions WHERE sessions.id = deliveries.session_id);
                """)
        }
        // Each delivery keeps the repository it was found in: a deleted external worktree leaves
        // nothing on disk that leads back to it.
        if try !db.rows("PRAGMA table_info(deliveries)").contains(where: { $0["name"] as? String == "repository" }) {
            try db.execute("ALTER TABLE deliveries ADD COLUMN repository TEXT;")
        }
        // And the checkout it was in: once a worktree is removed, the path no longer shows which
        // one held it, or where in the repository's history the file is.
        if try !db.rows("PRAGMA table_info(deliveries)").contains(where: { $0["name"] as? String == "checkout" }) {
            try db.execute("ALTER TABLE deliveries ADD COLUMN checkout TEXT;")
        }
        // Each delivery keeps its place in the reply that made it, so the files one reply named are
        // found together, in its order, however many records it took.
        if try !db.rows("PRAGMA table_info(deliveries)").contains(where: { $0["name"] as? String == "reply_line" }) {
            try db.execute("ALTER TABLE deliveries ADD COLUMN reply_line INTEGER; ALTER TABLE deliveries ADD COLUMN reply_rank INTEGER;")
        }
        // Each read log keeps the record types it held that Gleaner doesn't know, so a format change
        // is reported on every run, not only by the run that read the log.
        if try !db.rows("PRAGMA table_info(log_files)").contains(where: { $0["name"] as? String == "unknown_types" }) {
            try db.execute("ALTER TABLE log_files ADD COLUMN unknown_types TEXT;")
        }
        // Each capture keeps what was at the path, so one without a hash says why. Before, it kept
        // only whether that was a folder, and a file it couldn't read was recorded as seen.
        if try !db.rows("PRAGMA table_info(captures)").contains(where: { $0["name"] as? String == "kind" }) {
            try db.execute("""
                ALTER TABLE captures ADD COLUMN kind TEXT;
                UPDATE captures SET
                    kind = CASE WHEN is_directory = 1 THEN 'directory' WHEN sha256 IS NOT NULL THEN 'file'
                                WHEN provenance = 'never_observed' THEN 'missing' ELSE 'unreadable' END,
                    provenance = CASE WHEN is_directory = 0 AND sha256 IS NULL THEN 'never_observed' ELSE provenance END;
                ALTER TABLE captures DROP COLUMN is_directory;
                """)
        }
        let version = try db.rows("PRAGMA user_version").first?["user_version"] as? Int64 ?? 0
        if version != Int64(Self.extractorVersion) {
            // No log has this modification time, so every log is read again; each keeps the size
            // it was read at, so one that is shorter since still removes nothing.
            try db.execute("UPDATE log_files SET mtime = -1; PRAGMA user_version = \(Self.extractorVersion);")
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T { try db.transaction(body) }

    /// The record types a log held that its adapter didn't recognize, with counts, when the log is
    /// unchanged since it was read whole; nil when it must be read.
    public func unknownRecordTypes(unchangedLog path: String, size: Int64, mtime: Date) throws -> [String: Int]? {
        let rows = try db.rows("SELECT size, mtime, unknown_types FROM log_files WHERE path = ?", [path])
        guard let row = rows.first, row["size"] as? Int64 == size, row["mtime"] as? Double == mtime.timeIntervalSince1970
        else { return nil }
        return (row["unknown_types"] as? String).flatMap { try? JSONDecoder().decode([String: Int].self, from: Data($0.utf8)) } ?? [:]
    }

    /// The size a log had when it was last read whole; nil when it never was.
    public func readSize(logFile path: String) throws -> Int64? {
        try db.rows("SELECT size FROM log_files WHERE path = ?", [path]).first?["size"] as? Int64
    }

    public func markRead(logFile path: String, size: Int64, mtime: Date, unknownRecordTypes: [String: Int]) throws {
        let json = String(decoding: try JSONEncoder().encode(unknownRecordTypes), as: UTF8.self)
        try db.run("INSERT OR REPLACE INTO log_files (path, size, mtime, unknown_types) VALUES (?, ?, ?, ?)",
                   [path, size, mtime, json])
    }

    public func upsert(_ session: SessionInfo) throws {
        try db.run("""
            INSERT INTO sessions (id, provider, title, cwd, log_path) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title = COALESCE(excluded.title, title), cwd = COALESCE(excluded.cwd, cwd), log_path = excluded.log_path
            """, [session.id, session.provider.rawValue, session.title.map(Redactor.redact), session.cwd, session.logPath])
    }

    /// True once Gleaner has captured the delivery `id`, whether or not a log still admits it.
    public func hasCapture(_ id: String) throws -> Bool {
        try !db.rows("SELECT 1 FROM captures WHERE delivery_id = ?", [id]).isEmpty
    }

    /// `repository` and `checkout` (its folder) are kept once recorded: a later reread may find
    /// none, or an unrelated one around a deleted worktree. `replyLine` and `replyRank` place it in
    /// its reply (`Delivery`).
    public func upsertDelivery(id: String, sessionID: String, logPath: String, path: String, deliveredAt: Date?,
                               replyLine: Int, replyRank: Int, cwd: String?, repository: String?, checkout: String?,
                               request: String?, evidence: [Evidence]) throws {
        let json = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
        try db.run("""
            INSERT INTO deliveries (id, session_id, log_path, path, delivered_at, reply_line, reply_rank, cwd, repository,
                                    checkout, request, evidence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET log_path = excluded.log_path, reply_line = excluded.reply_line,
                reply_rank = excluded.reply_rank, cwd = excluded.cwd,
                repository = COALESCE(repository, excluded.repository), checkout = COALESCE(checkout, excluded.checkout),
                request = excluded.request, evidence = excluded.evidence
            """, [id, sessionID, logPath, path, deliveredAt, replyLine, replyRank, cwd, repository, checkout,
                  request.map(Redactor.redact), json])
    }

    /// Removes deliveries a reread log no longer admits. They are derived from the log and come
    /// back if it admits them again; their captures, which record what Gleaner saw, stay, so a
    /// delivery admitted again gets its own back. Saved copies stay in the store.
    public func removeDeliveries(logPath: String, except kept: Set<String>) throws {
        let keep = String(decoding: try JSONEncoder().encode(Array(kept)), as: UTF8.self)
        try db.run("""
            DELETE FROM deliveries WHERE log_path = ? AND id NOT IN (SELECT value FROM json_each(?))
            """, [logPath, keep])
    }

    /// Records what Gleaner first saw of a delivery's bytes. A delivery has one capture; it is
    /// never replaced, only completed once when it has no hash (`complete(capturesOf:with:)`).
    public func addCapture(_ capture: Capture, for deliveryID: String) throws {
        try db.run("""
            INSERT INTO captures (delivery_id, sha256, size, mtime, observed_at, saved_at, provenance, kind)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, [deliveryID, capture.sha256, capture.size, capture.modifiedAt, capture.observedAt, capture.savedAt,
                  capture.provenance.rawValue, capture.kind.rawValue])
    }

    /// True when a delivery of `path` has a capture without a hash that a read could complete:
    /// Gleaner found nothing there, a file it couldn't read, or one that isn't a regular file.
    public func hasIncompleteCapture(path: String) throws -> Bool {
        try !db.rows("""
            SELECT 1 FROM captures JOIN deliveries ON deliveries.id = captures.delivery_id
            WHERE deliveries.path = ? AND captures.sha256 IS NULL AND captures.kind != 'directory'
            """, [path]).isEmpty
    }

    /// Completes those captures with `capture`, the bytes of a later read: once, and as first seen
    /// after delivery (SPEC §5.1). A capture with a hash, or of a folder, is never rewritten.
    public func complete(capturesOf path: String, with capture: Capture) throws {
        try db.run("""
            UPDATE captures SET sha256 = ?, size = ?, mtime = ?, observed_at = ?, saved_at = ?,
                provenance = ?, kind = ?
            WHERE sha256 IS NULL AND kind != 'directory'
                AND delivery_id IN (SELECT id FROM deliveries WHERE path = ?)
            """, [capture.sha256, capture.size, capture.modifiedAt, capture.observedAt, capture.savedAt,
                  Provenance.firstSeenAfterDelivery.rawValue, capture.kind.rawValue, path])
    }

    public func markSaved(deliveryID: String, at date: Date) throws {
        try db.run("UPDATE captures SET saved_at = ? WHERE delivery_id = ?", [date, deliveryID])
    }

    /// Every artifact with its deliveries, newest delivery first, artifacts by latest delivery.
    public func artifacts() throws -> [Artifact] {
        let rows = try db.rows("""
            SELECT d.id, d.path, d.delivered_at, d.reply_line, d.reply_rank, d.cwd, d.repository, d.checkout, d.request,
                   d.evidence,
                   s.provider, s.title, d.log_path,
                   c.sha256, c.size, c.mtime, c.observed_at, c.saved_at, c.provenance, c.kind
            FROM deliveries d JOIN sessions s ON s.id = d.session_id
            LEFT JOIN captures c ON c.delivery_id = d.id
            ORDER BY d.path, d.delivered_at
            """)
        var byPath: [String: [Delivery]] = [:]
        var repositories: [String: String] = [:]
        var checkouts: [String: Checkout] = [:]
        for row in rows {
            let path = row["path"] as! String
            // Rows run oldest first: the newest recorded repository and checkout win.
            if let repository = row["repository"] as? String {
                repositories[path] = repository
                if let folder = row["checkout"] as? String { checkouts[path] = Checkout(folder: folder, repository: repository) }
            }
            let capture = (row["observed_at"] as? Double).map { observed in
                Capture(
                    sha256: row["sha256"] as? String, size: row["size"] as? Int64,
                    modifiedAt: (row["mtime"] as? Double).map(Date.init(timeIntervalSince1970:)),
                    observedAt: Date(timeIntervalSince1970: observed),
                    savedAt: (row["saved_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
                    provenance: Provenance(rawValue: row["provenance"] as? String ?? "") ?? .firstSeenAfterDelivery,
                    kind: LocatorState.Kind(rawValue: row["kind"] as? String ?? "") ?? .missing)
            }
            let evidence = (row["evidence"] as? String).flatMap {
                try? JSONDecoder().decode([Evidence].self, from: Data($0.utf8))
            } ?? []
            var list = byPath[path, default: []]
            list.append(Delivery(
                id: row["id"] as! String, number: list.count + 1, path: path,
                deliveredAt: (row["delivered_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
                replyLine: (row["reply_line"] as? Int64).map(Int.init),
                replyRank: (row["reply_rank"] as? Int64).map(Int.init) ?? 0,
                provider: Provider(rawValue: row["provider"] as? String ?? "") ?? .claudeCode,
                sessionTitle: row["title"] as? String, request: row["request"] as? String,
                cwd: row["cwd"] as? String, evidence: evidence,
                logPath: row["log_path"] as? String ?? "", capture: capture))
            byPath[path] = list
        }
        let artifacts = byPath.map { path, deliveries in
            Artifact(path: path, deliveries: deliveries.reversed(), repository: repositories[path], checkout: checkouts[path])
        }
        return artifacts.sorted {
            let (a, b) = ($0.latest.deliveredAt ?? .distantPast, $1.latest.deliveredAt ?? .distantPast)
            return a != b ? a > b : $0.path < $1.path
        }
    }
}
