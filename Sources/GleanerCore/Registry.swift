import Foundation

/// Gleaner's index: sessions, deliveries (one per reply that names a path), and what Gleaner
/// captured of each delivery's bytes, and where. Excerpts are stored redacted; whole logs never are.
public final class Registry: @unchecked Sendable {
    let db: Database

    /// Bump when extraction changes what is derived from logs (requests, evidence, admission, the
    /// record types a log holds that Gleaner doesn't know).
    /// Logs are then reread and derived fields refreshed; captures, which record what Gleaner saw
    /// at a moment in time, are never rewritten.
    public static let extractorVersion = 13

    public init(path: String) throws {
        db = try Database(path: path)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS log_files (
                path TEXT PRIMARY KEY, size INTEGER NOT NULL, mtime REAL NOT NULL, unknown_types TEXT, shortened INTEGER);
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY, provider TEXT NOT NULL, title TEXT, cwd TEXT, log_path TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS deliveries (
                id TEXT PRIMARY KEY, session_id TEXT NOT NULL, path TEXT NOT NULL, delivered_at REAL,
                cwd TEXT, request TEXT, evidence TEXT NOT NULL, log_path TEXT, reply_line INTEGER, reply_rank INTEGER);
            CREATE INDEX IF NOT EXISTS deliveries_path ON deliveries(path);
            CREATE TABLE IF NOT EXISTS captures (
                delivery_id TEXT PRIMARY KEY, sha256 TEXT, size INTEGER, mtime REAL, observed_at REAL NOT NULL,
                saved_at REAL, provenance TEXT NOT NULL, kind TEXT NOT NULL, repository TEXT, checkout TEXT,
                log_path TEXT, path TEXT, reply_times TEXT);
            CREATE TABLE IF NOT EXISTS projects (key TEXT PRIMARY KEY, name TEXT NOT NULL, created_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS corrections (
                id INTEGER PRIMARY KEY, kind TEXT NOT NULL, subject TEXT NOT NULL, target TEXT NOT NULL, made_at REAL NOT NULL);
            """)
        // Each change of several statements is made whole or not at all: a launch that stops partway,
        // say while another copy of Gleaner holds the library, leaves all of it to the next launch.

        // Each delivery names the log it came from: two logs can share a session id.
        if try !has("deliveries", "log_path") {
            try db.transaction {
                try db.execute("""
                    ALTER TABLE deliveries ADD COLUMN log_path TEXT;
                    UPDATE deliveries SET log_path = (SELECT log_path FROM sessions WHERE sessions.id = deliveries.session_id);
                    """)
            }
        }
        // Each delivery keeps its place in the reply that made it, so the files one reply named are
        // found together, in its order, however many records it took.
        if try !has("deliveries", "reply_line") {
            try db.transaction {
                try db.execute("ALTER TABLE deliveries ADD COLUMN reply_line INTEGER; ALTER TABLE deliveries ADD COLUMN reply_rank INTEGER;")
            }
        }
        // Each read log keeps the record types it held that Gleaner doesn't know, so a format change
        // is reported on every run, not only by the run that read the log.
        if try !has("log_files", "unknown_types") {
            try db.execute("ALTER TABLE log_files ADD COLUMN unknown_types TEXT;")
        }
        // And whether it was ever found shorter than when Gleaner read it: the records it lost stay
        // lost, however it grows again.
        if try !has("log_files", "shortened") {
            try db.execute("ALTER TABLE log_files ADD COLUMN shortened INTEGER;")
        }
        // Each capture keeps what was at the path, so one without a hash says why. Before, it kept
        // only whether that was a folder, and a file it couldn't read was recorded as seen.
        if try !has("captures", "kind") {
            try db.transaction {
                try db.execute("""
                    ALTER TABLE captures ADD COLUMN kind TEXT;
                    UPDATE captures SET
                        kind = CASE WHEN is_directory = 1 THEN 'directory' WHEN sha256 IS NOT NULL THEN 'file'
                                    WHEN provenance = 'never_observed' THEN 'missing' ELSE 'unreadable' END,
                        provenance = CASE WHEN is_directory = 0 AND sha256 IS NULL THEN 'never_observed' ELSE provenance END;
                    ALTER TABLE captures DROP COLUMN is_directory;
                    """)
            }
        }
        // Each capture keeps the repository and the checkout the file was found in: a deleted
        // external worktree leaves nothing on disk that leads back to its repository, and a removed
        // worktree's path no longer shows which checkout held it. Kept with its delivery before, they
        // went with it when a reread dropped it.
        if try !has("captures", "checkout") {
            try db.transaction {
                try db.execute("ALTER TABLE captures ADD COLUMN repository TEXT; ALTER TABLE captures ADD COLUMN checkout TEXT;")
                for column in ["repository", "checkout"] where try has("deliveries", column) {
                    try db.execute("""
                        UPDATE captures SET \(column) = (SELECT \(column) FROM deliveries WHERE deliveries.id = captures.delivery_id);
                        ALTER TABLE deliveries DROP COLUMN \(column);
                        """)
                }
            }
        }
        // Each capture keeps the reply it was made for: its log, its file and the times of the
        // reply's records. A delivery's id comes from where its reply sat in the log, so a log
        // rewritten with its replies moved would hand one reply's capture to another; the reply
        // finds its own capture by these instead. Filled from each delivery's row (the time of the
        // record that named the file); a capture whose delivery a reread dropped has none and is
        // found by its id, as before.
        if try !has("captures", "reply_times") {
            try db.transaction {
                try db.execute("ALTER TABLE captures ADD COLUMN log_path TEXT; ALTER TABLE captures ADD COLUMN path TEXT; ALTER TABLE captures ADD COLUMN reply_times TEXT;")
                for row in try db.rows("SELECT id, log_path, path, delivered_at FROM deliveries") {
                    try db.run("UPDATE captures SET log_path = ?, path = ?, reply_times = ? WHERE delivery_id = ?",
                               [row["log_path"] as? String, row["path"] as? String,
                                (row["delivered_at"] as? Double).map { Self.times([Date(timeIntervalSince1970: $0)]) }, row["id"] as? String])
                }
            }
        }
        try db.execute("CREATE INDEX IF NOT EXISTS captures_reply ON captures(log_path, path);")
        let version = try db.rows("PRAGMA user_version").first?["user_version"] as? Int64 ?? 0
        // Paths under /private/var, /private/tmp and /private/etc were kept in whichever spelling
        // the disk gave at the time; they now have one (`standardPath`).
        if version < 13 {
            try db.transaction {
                for (table, key, columns) in [("captures", "delivery_id", ["path", "repository", "checkout"]), ("deliveries", "id", ["path"])] {
                    for column in columns {
                        for row in try db.rows("SELECT \(key) AS key, \(column) AS value FROM \(table) WHERE \(column) LIKE '/private/%'") {
                            guard let value = row["value"] as? String, standardPath(value) != value else { continue }
                            try db.run("UPDATE \(table) SET \(column) = ? WHERE \(key) = ?", [standardPath(value), row["key"] as? String])
                        }
                    }
                }
            }
        }
        if version != Int64(Self.extractorVersion) {
            // No log has this modification time, so every log is read again; each keeps the size
            // it was read at, and whether it lost records, so one that did still removes nothing.
            try db.execute("UPDATE log_files SET mtime = -1; PRAGMA user_version = \(Self.extractorVersion);")
        }
    }

    private func has(_ table: String, _ column: String) throws -> Bool {
        try db.rows("PRAGMA table_info(\(table))").contains { $0["name"] as? String == column }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T { try db.transaction(body) }

    /// What reading a log found, when it is unchanged since it was read whole: the record types its
    /// adapter didn't recognize, with counts, and whether it had lost records (`markShortened`).
    /// Nil when it must be read.
    public func findings(unchangedLog path: String, size: Int64, mtime: Date) throws
        -> (unknownRecordTypes: [String: Int], shortened: Bool)? {
        let rows = try db.rows("SELECT size, mtime, unknown_types, shortened FROM log_files WHERE path = ?", [path])
        guard let row = rows.first, row["size"] as? Int64 == size, row["mtime"] as? Double == mtime.timeIntervalSince1970
        else { return nil }
        let unknown = (row["unknown_types"] as? String).flatMap { try? JSONDecoder().decode([String: Int].self, from: Data($0.utf8)) }
        return (unknown ?? [:], row["shortened"] as? Int64 == 1)
    }

    /// The size a log had when it was last read whole, and whether it lost records since Gleaner
    /// first read it; nil when it never was read whole.
    public func lastRead(logFile path: String) throws -> (size: Int64, shortened: Bool)? {
        try db.rows("SELECT size, shortened FROM log_files WHERE path = ?", [path]).first.flatMap { row in
            (row["size"] as? Int64).map { ($0, row["shortened"] as? Int64 == 1) }
        }
    }

    /// A read log keeps whether it lost records (`markShortened`).
    public func markRead(logFile path: String, size: Int64, mtime: Date, unknownRecordTypes: [String: Int]) throws {
        let json = String(decoding: try JSONEncoder().encode(unknownRecordTypes), as: UTF8.self)
        try db.run("""
            INSERT INTO log_files (path, size, mtime, unknown_types) VALUES (?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET size = excluded.size, mtime = excluded.mtime, unknown_types = excluded.unknown_types
            """, [path, size, mtime, json])
    }

    /// Records that a log Gleaner has read was found shorter than then: it lost records, for good.
    public func markShortened(logFile path: String) throws {
        try db.run("UPDATE log_files SET shortened = 1 WHERE path = ?", [path])
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

    /// The captures made for `path` from the log at `logPath`, with the times of the records of the
    /// reply each was made for (empty when it records none).
    public func captures(logPath: String, path: String) throws -> [(id: String, times: Set<Date>)] {
        try db.rows("SELECT delivery_id, reply_times FROM captures WHERE log_path = ? AND path = ? ORDER BY delivery_id",
                    [logPath, path]).compactMap { row in
            (row["delivery_id"] as? String).map { ($0, Self.times(row["reply_times"] as? String)) }
        }
    }

    /// The times of the records of the reply a delivery's capture was made for: nil when there is no
    /// capture, empty for one that records none (made before Gleaner kept them, or for records that
    /// carry no time), tied to its reply only by its id.
    public func captureTimes(_ id: String) throws -> Set<Date>? {
        guard let row = try db.rows("SELECT reply_times FROM captures WHERE delivery_id = ?", [id]).first else { return nil }
        return Self.times(row["reply_times"] as? String)
    }

    /// Records the reply a capture that records none belongs to (`captureTimes`).
    public func place(capture id: String, logPath: String, path: String, times: Set<Date>) throws {
        try db.run("UPDATE captures SET log_path = ?, path = ?, reply_times = ? WHERE delivery_id = ? AND reply_times IS NULL",
                   [logPath, path, Self.times(times), id])
    }

    /// Times as stored: each one's exact seconds, so they read back equal.
    static func times(_ times: Set<Date>) -> String? {
        times.isEmpty ? nil : times.map { String($0.timeIntervalSince1970) }.sorted().joined(separator: " ")
    }

    static func times(_ text: String?) -> Set<Date> {
        Set((text ?? "").split(separator: " ").compactMap { Double($0) }.map(Date.init(timeIntervalSince1970:)))
    }

    /// `replyLine` and `replyRank` place it in its reply (`Delivery`).
    public func upsertDelivery(id: String, sessionID: String, logPath: String, path: String, deliveredAt: Date?,
                               replyLine: Int, replyRank: Int, cwd: String?, request: String?, evidence: [Evidence]) throws {
        let json = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
        try db.run("""
            INSERT INTO deliveries (id, session_id, log_path, path, delivered_at, reply_line, reply_rank, cwd, request, evidence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET log_path = excluded.log_path, reply_line = excluded.reply_line,
                reply_rank = excluded.reply_rank, cwd = excluded.cwd, request = excluded.request, evidence = excluded.evidence
            """, [id, sessionID, logPath, path, deliveredAt, replyLine, replyRank, cwd, request.map(Redactor.redact), json])
    }

    /// Removes deliveries a reread log no longer admits. They are derived from the log and come
    /// back if it admits them again; their captures, which record what Gleaner saw and where, stay,
    /// so a delivery admitted again gets its own back. Saved copies stay in the store.
    public func removeDeliveries(logPath: String, except kept: Set<String>) throws {
        let keep = String(decoding: try JSONEncoder().encode(Array(kept)), as: UTF8.self)
        try db.run("""
            DELETE FROM deliveries WHERE log_path = ? AND id NOT IN (SELECT value FROM json_each(?))
            """, [logPath, keep])
    }

    /// Records what Gleaner first saw of a delivery's bytes, with the reply it was made for: the
    /// log, the file, and the times of the reply's records. A delivery has one capture; it is
    /// never replaced, only completed once when it has no hash (`complete(capturesOf:with:)`).
    public func addCapture(_ capture: Capture, for deliveryID: String, logPath: String, path: String, replyTimes: Set<Date>) throws {
        try db.run("""
            INSERT INTO captures (delivery_id, sha256, size, mtime, observed_at, saved_at, provenance, kind, log_path, path, reply_times)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [deliveryID, capture.sha256, capture.size, capture.modifiedAt, capture.observedAt, capture.savedAt,
                  capture.provenance.rawValue, capture.kind.rawValue, logPath, path, Self.times(replyTimes)])
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

    /// Records the repository the delivery `id`'s file belongs to and the checkout (its folder)
    /// holding it, once: a later reread may find none, or an unrelated one around a deleted
    /// worktree. Kept with its capture, it outlives the delivery's row.
    public func record(repository: String, checkout: String?, of id: String) throws {
        try db.run("UPDATE captures SET repository = ?, checkout = ? WHERE delivery_id = ? AND repository IS NULL",
                   [repository, checkout, id])
    }

    public func markSaved(deliveryID: String, at date: Date) throws {
        try db.run("UPDATE captures SET saved_at = ? WHERE delivery_id = ?", [date, deliveryID])
    }

    /// Every artifact with its deliveries, newest delivery first, artifacts by latest delivery.
    public func artifacts() throws -> [Artifact] {
        let rows = try db.rows("""
            SELECT d.id, d.path, d.delivered_at, d.reply_line, d.reply_rank, d.cwd, d.request, d.evidence,
                   s.provider, s.title, d.log_path, d.session_id, s.cwd AS session_cwd,
                   c.sha256, c.size, c.mtime, c.observed_at, c.saved_at, c.provenance, c.kind, c.repository, c.checkout
            FROM deliveries d JOIN sessions s ON s.id = d.session_id
            LEFT JOIN captures c ON c.delivery_id = d.id
            ORDER BY d.path, d.delivered_at
            """)
        var byPath: [String: [Delivery]] = [:]
        var repositories: [String: String] = [:]
        var checkouts: [String: Checkout] = [:]
        for row in rows {
            let path = row["path"] as! String
            // Rows run oldest first: the earliest recorded repository and checkout win, the likeliest
            // to have been found while a worktree that held the file was there.
            if let repository = row["repository"] as? String {
                if repositories[path] == nil { repositories[path] = repository }
                if checkouts[path] == nil, let folder = row["checkout"] as? String {
                    checkouts[path] = Checkout(folder: folder, repository: repository)
                }
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
                sessionID: row["session_id"] as? String ?? "", sessionCwd: row["session_cwd"] as? String,
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
