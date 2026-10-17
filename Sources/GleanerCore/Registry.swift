import Foundation

/// Gleaner's index: sessions, deliveries (one per reply that names a path), and what Gleaner
/// captured of each delivery's bytes. Excerpts are stored redacted; whole logs never are.
public final class Registry: @unchecked Sendable {
    let db: Database

    /// Bump when extraction changes what is derived from logs (requests, evidence, admission, the
    /// record types a log holds that Gleaner doesn't know).
    /// Logs are then reread and derived fields refreshed; captures, which record what Gleaner saw
    /// at a moment in time, are never rewritten.
    public static let extractorVersion = 10

    public init(path: String) throws {
        db = try Database(path: path)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS log_files (
                path TEXT PRIMARY KEY, size INTEGER NOT NULL, mtime REAL NOT NULL, unknown_types TEXT);
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY, provider TEXT NOT NULL, title TEXT, cwd TEXT, log_path TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS deliveries (
                id TEXT PRIMARY KEY, session_id TEXT NOT NULL, path TEXT NOT NULL, delivered_at REAL,
                cwd TEXT, request TEXT, evidence TEXT NOT NULL, log_path TEXT, repository TEXT, checkout TEXT);
            CREATE INDEX IF NOT EXISTS deliveries_path ON deliveries(path);
            CREATE TABLE IF NOT EXISTS captures (
                delivery_id TEXT PRIMARY KEY, sha256 TEXT, size INTEGER, mtime REAL, observed_at REAL NOT NULL,
                saved_at REAL, provenance TEXT NOT NULL, is_directory INTEGER NOT NULL);
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
        // Each read log keeps the record types it held that Gleaner doesn't know, so a format change
        // is reported on every run, not only by the run that read the log.
        if try !db.rows("PRAGMA table_info(log_files)").contains(where: { $0["name"] as? String == "unknown_types" }) {
            try db.execute("ALTER TABLE log_files ADD COLUMN unknown_types TEXT;")
        }
        let version = try db.rows("PRAGMA user_version").first?["user_version"] as? Int64 ?? 0
        if version != Int64(Self.extractorVersion) {
            try db.execute("DELETE FROM log_files; PRAGMA user_version = \(Self.extractorVersion);")
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

    public func hasDelivery(_ id: String) throws -> Bool {
        try !db.rows("SELECT 1 FROM deliveries WHERE id = ?", [id]).isEmpty
    }

    /// `repository` and `checkout` (its folder) are kept once recorded: a later reread may find
    /// none, or an unrelated one around a deleted worktree.
    public func upsertDelivery(id: String, sessionID: String, logPath: String, path: String, deliveredAt: Date?,
                               cwd: String?, repository: String?, checkout: String?, request: String?,
                               evidence: [Evidence]) throws {
        let json = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
        try db.run("""
            INSERT INTO deliveries (id, session_id, log_path, path, delivered_at, cwd, repository, checkout, request, evidence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET log_path = excluded.log_path, cwd = excluded.cwd,
                repository = COALESCE(repository, excluded.repository), checkout = COALESCE(checkout, excluded.checkout),
                request = excluded.request, evidence = excluded.evidence
            """, [id, sessionID, logPath, path, deliveredAt, cwd, repository, checkout, request.map(Redactor.redact), json])
    }

    /// Removes deliveries a reread log no longer admits, with their captures. They are derived
    /// from the log and come back if the log admits them again; saved copies stay in the store.
    public func removeDeliveries(logPath: String, except kept: Set<String>) throws {
        let keep = String(decoding: try JSONEncoder().encode(Array(kept)), as: UTF8.self)
        let stale = """
            SELECT id FROM deliveries WHERE log_path = ? AND id NOT IN (SELECT value FROM json_each(?))
            """
        try db.run("DELETE FROM captures WHERE delivery_id IN (\(stale))", [logPath, keep])
        try db.run("DELETE FROM deliveries WHERE id IN (\(stale))", [logPath, keep])
    }

    public func setCapture(_ capture: Capture, for deliveryID: String) throws {
        try db.run("""
            INSERT OR REPLACE INTO captures (delivery_id, sha256, size, mtime, observed_at, saved_at, provenance, is_directory)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, [deliveryID, capture.sha256, capture.size, capture.modifiedAt, capture.observedAt, capture.savedAt,
                  capture.provenance.rawValue, capture.isDirectory ? 1 : 0])
    }

    public func markSaved(deliveryID: String, at date: Date) throws {
        try db.run("UPDATE captures SET saved_at = ? WHERE delivery_id = ?", [date, deliveryID])
    }

    /// Every artifact with its deliveries, newest delivery first, artifacts by latest delivery.
    public func artifacts() throws -> [Artifact] {
        let rows = try db.rows("""
            SELECT d.id, d.path, d.delivered_at, d.cwd, d.repository, d.checkout, d.request, d.evidence,
                   s.provider, s.title, d.log_path,
                   c.sha256, c.size, c.mtime, c.observed_at, c.saved_at, c.provenance, c.is_directory
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
                    isDirectory: row["is_directory"] as? Int64 == 1)
            }
            let evidence = (row["evidence"] as? String).flatMap {
                try? JSONDecoder().decode([Evidence].self, from: Data($0.utf8))
            } ?? []
            var list = byPath[path, default: []]
            list.append(Delivery(
                id: row["id"] as! String, number: list.count + 1, path: path,
                deliveredAt: (row["delivered_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
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
