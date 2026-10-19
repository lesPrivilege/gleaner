import Foundation

/// What one read of a log counted: its records, those of a type its adapter knows, the closed turns
/// the assistant answered in (not the open last turn, nor one the person interrupted), its final
/// replies (the open last turn's included) and those of closed turns only, and the candidates every
/// final reply names, admitted or not (SPEC §9). Kept per log, so a format change shows as a count
/// that moves.
public struct LogCounts: Sendable, Equatable {
    public var records: Int
    public var knownRecords: Int
    public var turns: Int
    public var finalReplies: Int
    public var closedReplies: Int
    public var candidates: Int

    public init(records: Int, knownRecords: Int, turns: Int, finalReplies: Int, closedReplies: Int, candidates: Int) {
        self.records = records
        self.knownRecords = knownRecords
        self.turns = turns
        self.finalReplies = finalReplies
        self.closedReplies = closedReplies
        self.candidates = candidates
    }
}

/// What reading a log found, kept with the log so every run reports it, not only the run that read it.
public struct LogFindings: Sendable, Equatable {
    /// Record types its adapter didn't recognize, with counts.
    public var unknownRecordTypes: [String: Int] = [:]
    /// Keys its adapter didn't know inside the record types it did, as "type.key", with counts.
    public var unknownFields: [String: Int] = [:]
    /// Nil when it holds no session (a Codex sub-agent thread), or was read before Gleaner counted.
    public var counts: LogCounts?
    /// The read found fewer final replies of closed turns than the complete read before it.
    public var fewerReplies = false
    /// Found shorter than when Gleaner read it, now or on an earlier run (`markShortened`).
    public var shortened = false

    public init(unknownRecordTypes: [String: Int] = [:], unknownFields: [String: Int] = [:], counts: LogCounts? = nil,
                fewerReplies: Bool = false, shortened: Bool = false) {
        self.unknownRecordTypes = unknownRecordTypes
        self.unknownFields = unknownFields
        self.counts = counts
        self.fewerReplies = fewerReplies
        self.shortened = shortened
    }

    /// The assistant answered in a closed turn, but the adapter found no final reply in the log, the
    /// open last turn's included. That turn isn't counted as answered: the session may be running,
    /// or it ended on a tool call. A turn the person interrupted was not answered.
    public var lacksFinalReply: Bool { counts.map { $0.turns > 0 && $0.finalReplies == 0 } ?? false }
}

/// Gleaner's index: sessions, deliveries (one per reply that names a path), and what Gleaner
/// captured of each delivery's bytes, and where. Excerpts are stored redacted; whole logs never are.
public final class Registry: @unchecked Sendable {
    let db: Database
    /// The library file, for another connection to it (`LibraryModel` writes corrections over one).
    public let path: String
    /// One write at a time to a library file, whichever connection makes it: a log's reading and a
    /// person's correction take turns, so a correction waits for the log being read, not for every
    /// log after it, and two connections never meet SQLite's busy timeout.
    let gate: DispatchSemaphore

    private static let gates = Gates()

    private final class Gates: @unchecked Sendable {
        let lock = NSLock()
        var byPath: [String: DispatchSemaphore] = [:]

        func gate(_ path: String) -> DispatchSemaphore {
            lock.withLock {
                if let gate = byPath[path] { return gate }
                let gate = DispatchSemaphore(value: 1)
                byPath[path] = gate
                return gate
            }
        }
    }

    /// Runs `body` holding the library's write gate.
    @discardableResult
    func writing<T>(_ body: () throws -> T) throws -> T {
        gate.wait()
        defer { gate.signal() }
        return try body()
    }

    /// Bump when extraction changes what is derived from logs (requests, evidence, admission, the
    /// record types and fields a log holds that Gleaner doesn't know, what a read counts, each
    /// session's span and workspaces; a session whose span or workspaces moved is walked again).
    /// Logs are then reread and derived fields refreshed; captures, which record what Gleaner saw
    /// at a moment in time, are never rewritten. Bump it too when the tables change: it is the
    /// library's version, and an older Gleaner opens no library of a later one (`Failure.newer`).
    public static let extractorVersion = 17

    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// The library was last opened by a later Gleaner, whose tables and readings this one
        /// doesn't know. Nothing is written to it.
        case newer(version: Int)
        /// The library is an earlier Gleaner's, and couldn't be copied before this one updates it.
        /// Nothing is written to it.
        case backup(String)

        public var description: String {
            switch self {
            case .newer(let version):
                "A newer Gleaner last opened this library (library version \(version); this Gleaner opens up to \(Registry.extractorVersion)). "
                    + "Nothing in it was changed. Open it with that newer Gleaner."
            case .backup(let reason):
                "Gleaner couldn’t back up the library before updating it (\(reason)). Nothing in it was changed."
            }
        }
    }

    public init(path: String) throws {
        self.path = path
        gate = Self.gates.gate(URL(fileURLWithPath: path).standardizedFileURL.path)
        db = try Database(path: path)
        // Before anything is written: setting the version back would have this Gleaner reread a
        // later one's library with its own, older reading, over tables it may not know.
        let found = try db.rows("PRAGMA user_version").first?["user_version"] as? Int64 ?? 0
        if found > Self.extractorVersion { throw Failure.newer(version: Int(found)) }
        // An earlier Gleaner's library is copied whole before this one changes it, so going back to
        // that Gleaner can start from the copy. The saved bytes aren't copied: they are kept by
        // hash and never rewritten.
        if found > 0, found < Self.extractorVersion { try backUp(version: Int(found)) }
        try db.execute("""
            CREATE TABLE IF NOT EXISTS log_files (
                path TEXT PRIMARY KEY, size INTEGER NOT NULL, mtime REAL NOT NULL, unknown_types TEXT, shortened INTEGER,
                unknown_fields TEXT, records INTEGER, known_records INTEGER, turns INTEGER, final_replies INTEGER,
                candidates INTEGER, fewer_replies INTEGER, closed_replies INTEGER);
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
            CREATE INDEX IF NOT EXISTS corrections_subject ON corrections(subject, kind);
            CREATE TABLE IF NOT EXISTS sources_off (provider TEXT PRIMARY KEY, since REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS spans (
                log_path TEXT PRIMARY KEY, session_id TEXT NOT NULL, provider TEXT NOT NULL, stretches TEXT NOT NULL,
                end_at REAL NOT NULL, workspaces TEXT NOT NULL, unwalked TEXT, problems TEXT, walked_at REAL);
            CREATE TABLE IF NOT EXISTS observations (
                path TEXT NOT NULL, log_path TEXT NOT NULL, kind TEXT NOT NULL, workspace TEXT NOT NULL,
                size INTEGER NOT NULL, created_at REAL, modified_at REAL NOT NULL, device INTEGER NOT NULL, inode INTEGER NOT NULL,
                repository TEXT, checkout TEXT, observed_at REAL NOT NULL, PRIMARY KEY (path, log_path)) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS listings (
                delivery_id TEXT PRIMARY KEY, listed_at REAL NOT NULL, members INTEGER NOT NULL, not_unpacked TEXT,
                problems TEXT, repositories TEXT) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS members (
                delivery_id TEXT NOT NULL, path TEXT NOT NULL, kind TEXT NOT NULL, size INTEGER NOT NULL, created_at REAL,
                modified_at REAL NOT NULL, changed_at REAL NOT NULL, device INTEGER NOT NULL, inode INTEGER NOT NULL,
                listed_at REAL NOT NULL, sha256 TEXT, observed_at REAL, saved_at REAL, provenance TEXT NOT NULL,
                PRIMARY KEY (path, delivery_id)) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS units (
                key TEXT PRIMARY KEY, project TEXT NOT NULL, parent TEXT, name TEXT NOT NULL, created_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS kept (
                path TEXT NOT NULL, log_path TEXT NOT NULL, sha256 TEXT NOT NULL, observed_at REAL NOT NULL, saved_at REAL,
                provenance TEXT NOT NULL, PRIMARY KEY (path, log_path)) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS reviews (
                id INTEGER PRIMARY KEY, path TEXT NOT NULL, kind TEXT NOT NULL, note TEXT, sha256 TEXT NOT NULL,
                size INTEGER NOT NULL, created_at REAL, modified_at REAL NOT NULL, inode INTEGER NOT NULL, made_at REAL NOT NULL);
            CREATE INDEX IF NOT EXISTS reviews_path ON reviews(path);
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
        // And the keys it held that Gleaner doesn't know, what its read counted, and whether that read
        // found fewer final replies than the one before: an adapter that stops understanding a format
        // shows in its counts. Each column is added on its own: a library from a build between two of
        // them has some and not the others.
        try db.transaction {
            for (column, type) in [("unknown_fields", "TEXT"), ("records", "INTEGER"), ("known_records", "INTEGER"),
                                   ("turns", "INTEGER"), ("final_replies", "INTEGER"), ("closed_replies", "INTEGER"),
                                   ("candidates", "INTEGER"), ("fewer_replies", "INTEGER")]
            where try !has("log_files", column) {
                try db.execute("ALTER TABLE log_files ADD COLUMN \(column) \(type);")
            }
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
                for column in ["log_path", "path"] where try !has("captures", column) {
                    try db.execute("ALTER TABLE captures ADD COLUMN \(column) TEXT;")
                }
                try db.execute("ALTER TABLE captures ADD COLUMN reply_times TEXT;")
                for row in try db.rows("SELECT id, log_path, path, delivered_at FROM deliveries") {
                    try db.run("UPDATE captures SET log_path = ?, path = ?, reply_times = ? WHERE delivery_id = ?",
                               [row["log_path"] as? String, row["path"] as? String,
                                (row["delivered_at"] as? Double).map { Self.times([$0]) }, row["id"] as? String])
                }
            }
        }
        try db.execute("CREATE INDEX IF NOT EXISTS captures_reply ON captures(log_path, path);")
        // Each delivery keeps the model that wrote its reply, and each session the provider its
        // agent sent requests to, as the log names them: filled when the logs are read again.
        if try !has("deliveries", "model") { try db.execute("ALTER TABLE deliveries ADD COLUMN model TEXT;") }
        if try !has("sessions", "model_provider") { try db.execute("ALTER TABLE sessions ADD COLUMN model_provider TEXT;") }
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
            // Its replies were counted by the older reading, so fewer by this one is no alarm.
            try db.execute("UPDATE log_files SET mtime = -1, closed_replies = NULL; PRAGMA user_version = \(Self.extractorVersion);")
        }
    }

    /// Where an earlier Gleaner's library is copied before this one updates it: `Backups` beside
    /// it. Copies are never removed by Gleaner.
    public static func backups(of path: String) -> URL {
        URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    /// Copies the library, as it is, to `Backups`, named for its version and the time: one
    /// consistent file, the write-ahead log's pages included (`VACUUM INTO`).
    private func backUp(version: Int) throws {
        let folder = Self.backups(of: path), stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let stamp = Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().time(includingFractionalSeconds: false)
            .dateSeparator(.dash).timeSeparator(.omitted).dateTimeSeparator(.standard))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var copy = folder.appendingPathComponent("\(stem)-v\(version)-\(stamp).sqlite"), next = 2
            while FileManager.default.fileExists(atPath: copy.path) {
                copy = folder.appendingPathComponent("\(stem)-v\(version)-\(stamp)-\(next).sqlite")
                next += 1
            }
            try db.run("VACUUM INTO ?", [copy.path])
        } catch {
            throw Failure.backup("\(error)")
        }
    }

    private func has(_ table: String, _ column: String) throws -> Bool {
        try db.rows("PRAGMA table_info(\(table))").contains { $0["name"] as? String == column }
    }

    @discardableResult
    public func transaction<T>(_ body: () throws -> T) throws -> T { try writing { try db.transaction(body) } }

    /// What reading a log found, when it is unchanged since it was read whole. Nil when it must be read.
    public func findings(unchangedLog path: String, size: Int64, mtime: Date) throws -> LogFindings? {
        let rows = try db.rows("SELECT * FROM log_files WHERE path = ?", [path])
        guard let row = rows.first, row["size"] as? Int64 == size, row["mtime"] as? Double == mtime.timeIntervalSince1970
        else { return nil }
        func decoded(_ column: String) -> [String: Int] {
            (row[column] as? String).flatMap { try? JSONDecoder().decode([String: Int].self, from: Data($0.utf8)) } ?? [:]
        }
        let n = ["records", "known_records", "turns", "final_replies", "closed_replies", "candidates"]
            .compactMap { (row[$0] as? Int64).map(Int.init) }
        return LogFindings(
            unknownRecordTypes: decoded("unknown_types"), unknownFields: decoded("unknown_fields"),
            counts: n.count == 6 ? LogCounts(records: n[0], knownRecords: n[1], turns: n[2], finalReplies: n[3],
                                             closedReplies: n[4], candidates: n[5]) : nil,
            fewerReplies: row["fewer_replies"] as? Int64 == 1, shortened: row["shortened"] as? Int64 == 1)
    }

    /// The size a log had when it was last read whole, whether it lost records since Gleaner first
    /// read it, and the final replies of closed turns that read found (nil when it didn't count
    /// them); nil when it never was read whole.
    public func lastRead(logFile path: String) throws -> (size: Int64, shortened: Bool, closedReplies: Int?)? {
        try db.rows("SELECT size, shortened, closed_replies FROM log_files WHERE path = ?", [path]).first.flatMap { row in
            (row["size"] as? Int64).map { ($0, row["shortened"] as? Int64 == 1, (row["closed_replies"] as? Int64).map(Int.init)) }
        }
    }

    /// Keeps what reading a log whole found. Whether it lost records is kept by `markShortened`.
    public func markRead(logFile path: String, size: Int64, mtime: Date, findings: LogFindings) throws {
        func json(_ counts: [String: Int]) throws -> String { String(decoding: try JSONEncoder().encode(counts), as: UTF8.self) }
        let counts = findings.counts
        try db.run("""
            INSERT INTO log_files (path, size, mtime, unknown_types, unknown_fields, records, known_records, turns,
                                   final_replies, closed_replies, candidates, fewer_replies)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET size = excluded.size, mtime = excluded.mtime,
                unknown_types = excluded.unknown_types, unknown_fields = excluded.unknown_fields,
                records = excluded.records, known_records = excluded.known_records, turns = excluded.turns,
                final_replies = excluded.final_replies, closed_replies = excluded.closed_replies,
                candidates = excluded.candidates, fewer_replies = excluded.fewer_replies
            """, [path, size, mtime, try json(findings.unknownRecordTypes), try json(findings.unknownFields),
                  counts?.records, counts?.knownRecords, counts?.turns, counts?.finalReplies, counts?.closedReplies,
                  counts?.candidates, findings.fewerReplies ? 1 : 0])
    }

    /// Records that a log Gleaner has read was found shorter than then: it lost records, for good.
    public func markShortened(logFile path: String) throws {
        try db.run("UPDATE log_files SET shortened = 1 WHERE path = ?", [path])
    }

    public func upsert(_ session: SessionInfo) throws {
        try db.run("""
            INSERT INTO sessions (id, provider, title, cwd, log_path, model_provider) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title = COALESCE(excluded.title, title), cwd = COALESCE(excluded.cwd, cwd), log_path = excluded.log_path,
                model_provider = COALESCE(excluded.model_provider, model_provider)
            """, [session.id, session.provider.rawValue, session.title.map(Redactor.redact), session.cwd, session.logPath,
                  session.modelProvider.map(Redactor.redact)])
    }

    /// True once Gleaner has captured the delivery `id`, whether or not a log still admits it.
    public func hasCapture(_ id: String) throws -> Bool {
        try !db.rows("SELECT 1 FROM captures WHERE delivery_id = ?", [id]).isEmpty
    }

    /// The captures made for `path` from the log at `logPath`, with the times of the records of the
    /// reply each was made for, in seconds since 1970 (empty when it records none).
    public func captures(logPath: String, path: String) throws -> [(id: String, times: Set<Double>)] {
        try db.rows("SELECT delivery_id, reply_times FROM captures WHERE log_path = ? AND path = ? ORDER BY delivery_id",
                    [logPath, path]).compactMap { row in
            (row["delivery_id"] as? String).map { ($0, Self.times(row["reply_times"] as? String)) }
        }
    }

    /// The times of the records of the reply a delivery's capture was made for: nil when there is no
    /// capture, empty for one that records none (made before Gleaner kept them, or for records that
    /// carry no time), tied to its reply only by its id.
    public func captureTimes(_ id: String) throws -> Set<Double>? {
        guard let row = try db.rows("SELECT reply_times FROM captures WHERE delivery_id = ?", [id]).first else { return nil }
        return Self.times(row["reply_times"] as? String)
    }

    /// Records the reply a capture that records none belongs to (`captureTimes`).
    public func place(capture id: String, logPath: String, path: String, times: Set<Double>) throws {
        try db.run("UPDATE captures SET log_path = ?, path = ?, reply_times = ? WHERE delivery_id = ? AND reply_times IS NULL",
                   [logPath, path, Self.times(times), id])
    }

    /// Times as stored: each one's seconds since 1970, written so they read back as the same
    /// number. They stay numbers: a Date made again from one can differ in its last bit.
    static func times(_ times: Set<Double>) -> String? {
        times.isEmpty ? nil : times.map { String($0) }.sorted().joined(separator: " ")
    }

    static func times(_ text: String?) -> Set<Double> {
        Set((text ?? "").split(separator: " ").compactMap { Double($0) })
    }

    /// `replyLine` and `replyRank` place it in its reply (`Delivery`).
    public func upsertDelivery(id: String, sessionID: String, logPath: String, path: String, deliveredAt: Date?,
                               replyLine: Int, replyRank: Int, cwd: String?, request: String?, evidence: [Evidence],
                               model: String? = nil) throws {
        let json = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
        try db.run("""
            INSERT INTO deliveries (id, session_id, log_path, path, delivered_at, reply_line, reply_rank, cwd, request, evidence, model)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET log_path = excluded.log_path, reply_line = excluded.reply_line,
                reply_rank = excluded.reply_rank, cwd = excluded.cwd, request = excluded.request, evidence = excluded.evidence,
                model = excluded.model
            """, [id, sessionID, logPath, path, deliveredAt, replyLine, replyRank, cwd, request.map(Redactor.redact), json,
                  model.map(Redactor.redact)])
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
    public func addCapture(_ capture: Capture, for deliveryID: String, logPath: String, path: String, replyTimes: Set<Double>) throws {
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

    /// Records that `delivery`'s bytes were saved at `date`: in its capture, or, for one of a
    /// delivered folder's files or a kept file, in its row.
    public func markSaved(_ delivery: Delivery, at date: Date) throws {
        if let member = delivery.member {
            try db.run("UPDATE members SET saved_at = ? WHERE delivery_id = ? AND path = ?", [date, member.folderDelivery, delivery.path])
        } else if delivery.kept != nil {
            try db.run("UPDATE kept SET saved_at = ? WHERE path = ? AND log_path = ?", [date, delivery.path, delivery.logPath])
        } else {
            try db.run("UPDATE captures SET saved_at = ? WHERE delivery_id = ?", [date, delivery.id])
        }
    }

    /// Every artifact with its deliveries, newest delivery first, artifacts by latest delivery: the
    /// files replies named, the files handed over in the folders they named (SPEC §5.4), whose
    /// deliveries of one file number together by time, and the files the person kept, each a
    /// revision of its own (`Keeping`).
    public func artifacts() throws -> [Artifact] {
        try artifacts(at: nil)
    }

    /// The artifact at `path` alone, as `artifacts` reads it, without reading the others: what a
    /// first read of a file or a saved copy changed. Nil when no delivery names it.
    public func artifact(at path: String) throws -> Artifact? {
        try artifacts(at: path).first
    }

    private func artifacts(at path: String?) throws -> [Artifact] {
        var found = try deliveries(path.map { ("d.path = ?", [$0]) })
        // The files handed over in folders, each a copy of its folder's delivery, which is read
        // here when only one path is.
        var folders: [String: Found] = [:]
        for item in found where item.delivery.unpacking != nil { folders[item.delivery.id] = item }
        if let path {
            let ids = Set(try db.rows("SELECT delivery_id FROM members WHERE path = ?", [path]).compactMap { $0["delivery_id"] as? String })
                .subtracting(folders.keys).sorted()
            if !ids.isEmpty {
                for item in try deliveries(("d.id IN (\(Array(repeating: "?", count: ids.count).joined(separator: ", ")))", ids)) {
                    folders[item.delivery.id] = item
                }
            }
        }
        // A folder's files are where it is: one that holds a repository isn't unpacked.
        for (id, folder) in folders {
            let artifact = Artifact(path: folder.delivery.path, deliveries: [folder.delivery], repository: folder.repository,
                                    checkout: folder.repository.flatMap { r in folder.checkout.map { Checkout(folder: $0, repository: r) } })
            folders[id]?.location = artifact.location
        }
        found += try members(at: path, folders: folders, after: found.count)
        found += try kept(at: path, after: found.count)

        let artifacts = Dictionary(grouping: found, by: \.delivery.path).map { path, found in
            // Oldest first, deliveries of one time in the order they were read. The earliest recorded
            // repository and checkout win, the likeliest to have been found while a worktree that held
            // the file was there. A file only ever handed over in folders is where its latest folder is.
            let found = Self.onePerReply(found).sorted {
                let (a, b) = ($0.delivery.deliveredAt ?? .distantPast, $1.delivery.deliveredAt ?? .distantPast)
                return a != b ? a < b : $0.order < $1.order
            }
            let deliveries = found.enumerated().map { n, found in
                var delivery = found.delivery
                delivery.number = n + 1
                return delivery
            }
            if let location = found.last?.location, found.allSatisfy({ $0.delivery.member != nil }) {
                return Artifact(path: path, deliveries: deliveries.reversed(), location: location)
            }
            let recorded = found.first { $0.repository != nil }
            let checkout = found.first { $0.repository != nil && $0.checkout != nil }
            return Artifact(path: path, deliveries: deliveries.reversed(), repository: recorded?.repository,
                            checkout: checkout.map { Checkout(folder: $0.checkout!, repository: $0.repository!) })
        }
        return artifacts.sorted {
            let (a, b) = ($0.latest.deliveredAt ?? .distantPast, $1.latest.deliveredAt ?? .distantPast)
            return a != b ? a > b : $0.path < $1.path
        }
    }

    /// The deliveries `filter` picks, as `artifacts` reads them: each with its capture, and a
    /// folder's with its listing.
    private func deliveries(_ filter: (sql: String, arguments: [Any?])?) throws -> [Found] {
        try db.rows("""
            SELECT d.id, d.path, d.delivered_at, d.reply_line, d.reply_rank, d.cwd, d.request, d.evidence, d.model,
                   s.provider, s.title, d.log_path, d.session_id, s.cwd AS session_cwd, s.model_provider,
                   c.sha256, c.size, c.mtime, c.observed_at, c.saved_at, c.provenance, c.kind, c.repository, c.checkout,
                   l.listed_at, l.members, l.not_unpacked, l.problems, l.repositories
            FROM deliveries d JOIN sessions s ON s.id = d.session_id
            LEFT JOIN captures c ON c.delivery_id = d.id
            LEFT JOIN listings l ON l.delivery_id = d.id
            """ + (filter.map { " WHERE " + $0.sql } ?? "") + " ORDER BY d.path, d.delivered_at", filter?.arguments ?? [])
        .enumerated().map { index, row in
            let id = row["id"] as! String, path = row["path"] as! String
            let capture = (row["observed_at"] as? Double).map { observed in
                Capture(
                    sha256: row["sha256"] as? String, size: row["size"] as? Int64,
                    modifiedAt: (row["mtime"] as? Double).map(Date.init(timeIntervalSince1970:)),
                    observedAt: Date(timeIntervalSince1970: observed),
                    savedAt: (row["saved_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
                    provenance: Provenance(rawValue: row["provenance"] as? String ?? "") ?? .firstSeenAfterDelivery,
                    kind: LocatorState.Kind(rawValue: row["kind"] as? String ?? "") ?? .missing)
            }
            var delivery = Self.delivery(row, id: id, path: path, capture: capture, evidence: Self.evidence(row["evidence"] as? String))
            delivery.unpacking = (row["listed_at"] as? Double).map { listed in
                Unpacking(listedAt: Date(timeIntervalSince1970: listed), members: Int(row["members"] as? Int64 ?? 0),
                          notUnpacked: row["not_unpacked"] as? String, problems: Self.list(row["problems"] as? String),
                          repositories: Self.list(row["repositories"] as? String))
            }
            return Found(delivery: delivery, repository: row["repository"] as? String, checkout: row["checkout"] as? String,
                         order: index)
        }
    }

    /// A delivery as `artifacts` reads it, with where the file was found, and its place among the
    /// rows read. A folder's delivery has where its files are shown.
    struct Found {
        var delivery: Delivery
        var repository: String?
        var checkout: String?
        var order: Int
        var location: Artifact.Location?
    }

    /// A delivery from a row of `deliveries` joined with its session: the reply's own fields, and
    /// those given.
    static func delivery(_ row: Database.Row, id: String, path: String, capture: Capture?, evidence: [Evidence]) -> Delivery {
        Delivery(
            id: id, number: 0, path: path,
            deliveredAt: (row["delivered_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
            replyLine: (row["reply_line"] as? Int64).map(Int.init),
            replyRank: (row["reply_rank"] as? Int64).map(Int.init) ?? 0,
            provider: Provider(rawValue: row["provider"] as? String ?? "") ?? .claudeCode,
            sessionID: row["session_id"] as? String ?? "", sessionCwd: row["session_cwd"] as? String,
            sessionTitle: row["title"] as? String, request: row["request"] as? String,
            cwd: row["cwd"] as? String, evidence: evidence,
            logPath: row["log_path"] as? String ?? "", capture: capture,
            model: row["model"] as? String, modelProvider: row["model_provider"] as? String)
    }

    static func evidence(_ json: String?) -> [Evidence] {
        json.flatMap { try? JSONDecoder().decode([Evidence].self, from: Data($0.utf8)) } ?? []
    }

    /// A list kept as JSON; empty when there is none.
    static func list(_ json: String?) -> [String] {
        json.flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
    }
}
