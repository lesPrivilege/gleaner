import Foundation

/// What one read of a log counted: its records, those of a type its adapter knows, the turns the
/// assistant answered in (the last only once it has a final reply), the final replies among them,
/// and the candidates those replies name, admitted or not (SPEC §9). Kept per log, so a format
/// change shows as a count that moves.
public struct LogCounts: Sendable, Equatable {
    public var records: Int
    public var knownRecords: Int
    public var turns: Int
    public var finalReplies: Int
    public var candidates: Int

    public init(records: Int, knownRecords: Int, turns: Int, finalReplies: Int, candidates: Int) {
        self.records = records
        self.knownRecords = knownRecords
        self.turns = turns
        self.finalReplies = finalReplies
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
    /// The read found fewer final replies than the complete read before it.
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

    /// The assistant answered in a turn other than the log's last, but the adapter found no final
    /// reply. A last turn without one is still open: the session may be running, or it ended on a
    /// tool call.
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
    func writing<T>(_ body: () throws -> T) throws -> T {
        gate.wait()
        defer { gate.signal() }
        return try body()
    }

    /// Bump when extraction changes what is derived from logs (requests, evidence, admission, the
    /// record types and fields a log holds that Gleaner doesn't know, what a read counts), or when
    /// the library gains something its readers need: `init(readingAt:)` reads no other version.
    /// Logs are then reread and derived fields refreshed; captures, which record what Gleaner saw
    /// at a moment in time, are never rewritten.
    public static let extractorVersion = 18

    public init(path: String) throws {
        self.path = path
        gate = Self.gates.gate(URL(fileURLWithPath: path).standardizedFileURL.path)
        db = try Database(path: path)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value);
            CREATE TABLE IF NOT EXISTS log_files (
                path TEXT PRIMARY KEY, size INTEGER NOT NULL, mtime REAL NOT NULL, unknown_types TEXT, shortened INTEGER,
                unknown_fields TEXT, records INTEGER, known_records INTEGER, turns INTEGER, final_replies INTEGER,
                candidates INTEGER, fewer_replies INTEGER);
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
            CREATE TABLE IF NOT EXISTS sources_off (provider TEXT PRIMARY KEY, since REAL NOT NULL);
            """)
        // The library's namespace, made once with it: every delivery id is unique only within it.
        // Written only when missing, and through the gate: a library already made is opened without
        // a write, so a second connection opened while a log is read (`LibraryModel`'s, for
        // corrections) never waits on SQLite's lock.
        if try db.rows("SELECT 1 FROM meta WHERE key = 'library'").isEmpty {
            try writing { try db.run("INSERT OR IGNORE INTO meta (key, value) VALUES ('library', ?)", [UUID().uuidString.lowercased()]) }
        }
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
        // shows in its counts.
        if try !has("log_files", "records") {
            try db.transaction {
                try db.execute("""
                    ALTER TABLE log_files ADD COLUMN unknown_fields TEXT;
                    ALTER TABLE log_files ADD COLUMN records INTEGER;
                    ALTER TABLE log_files ADD COLUMN known_records INTEGER;
                    ALTER TABLE log_files ADD COLUMN turns INTEGER;
                    ALTER TABLE log_files ADD COLUMN final_replies INTEGER;
                    ALTER TABLE log_files ADD COLUMN candidates INTEGER;
                    ALTER TABLE log_files ADD COLUMN fewer_replies INTEGER;
                    """)
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
        // the disk gave at the time; they now have one (`Paths.standard`). Versions 13 to 17 were
        // numbered on two lines of work, only one of which made this change, so every library
        // from before 18 gets it; a path already in its one form is left as it is.
        if version < 18 {
            try db.transaction {
                for (table, key, columns) in [("captures", "delivery_id", ["path", "repository", "checkout"]), ("deliveries", "id", ["path"])] {
                    for column in columns {
                        for row in try db.rows("SELECT \(key) AS key, \(column) AS value FROM \(table) WHERE \(column) LIKE '/private/%'") {
                            guard let value = row["value"] as? String, Paths.standard(value) != value else { continue }
                            try db.run("UPDATE \(table) SET \(column) = ? WHERE \(key) = ?", [Paths.standard(value), row["key"] as? String])
                        }
                    }
                }
            }
        }
        if version != Int64(Self.extractorVersion) {
            // No log has this modification time, so every log is read again; each keeps the size
            // it was read at, and whether it lost records, so one that did still removes nothing.
            // The last run's status was another version's reading, kept in that version's shape:
            // none is given until this version's first run ends (`recordRun`).
            try db.execute("""
                UPDATE log_files SET mtime = -1; DELETE FROM meta WHERE key = 'sources';
                PRAGMA user_version = \(Self.extractorVersion);
                """)
        }
    }

    /// Opens the library at `path` to read only, as the query core does: no schema change, and no
    /// reread scheduled. A library that isn't there, that can't be read as it is, or that another
    /// version of Gleaner wrote, is refused (`Catalog.Failure`); opening Gleaner makes, restores or
    /// updates it. One that lost its write-ahead log, say to another SQLite client that removed it
    /// on closing, can't be read until Gleaner opens it to write and makes the log again.
    public init(readingAt path: String) throws {
        self.path = path
        gate = Self.gates.gate(URL(fileURLWithPath: path).standardizedFileURL.path)
        guard FileManager.default.fileExists(atPath: path) else { throw Catalog.Failure.noLibrary(path) }
        let version: Int64
        do {
            db = try Database(readingAt: path)
            version = try db.rows("PRAGMA user_version").first?["user_version"] as? Int64 ?? 0
        } catch {
            throw Catalog.Failure.unreadableLibrary(path, reason: "\(error)")
        }
        guard version == Int64(Self.extractorVersion) else { throw Catalog.Failure.wrongVersion(path, found: Int(version)) }
    }

    private func has(_ table: String, _ column: String) throws -> Bool {
        try db.rows("PRAGMA table_info(\(table))").contains { $0["name"] as? String == column }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T { try writing { try db.transaction(body) } }

    /// Records a completed run of the indexer: one more generation, when it finished, how the logs
    /// of each agent it read read, and the agents it didn't read because they are turned off (`off`).
    public func recordRun(finishedAt date: Date, sources: [Provider: Indexer.Report.Source], off: Set<Provider>) throws {
        var status = Dictionary(uniqueKeysWithValues: sources.map { ($0.key.rawValue, Catalog.Source($0.value)) })
        for provider in off { status[provider.rawValue] = Catalog.Source(state: .off) }
        let json = String(decoding: try Catalog.encoder.encode(status), as: UTF8.self)
        try transaction {
            try db.run("""
                INSERT INTO meta (key, value) VALUES ('generation', 1)
                ON CONFLICT(key) DO UPDATE SET value = value + 1
                """)
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('scanned_at', ?)", [date])
            try db.run("INSERT OR REPLACE INTO meta (key, value) VALUES ('sources', ?)", [json])
        }
    }

    /// The library's namespace and its last completed run (`recordRun`), with each agent turned off
    /// now as `off`: turning one off starts no run, and its deliveries are left out at once.
    public func index() throws -> Catalog.Index {
        var meta: [String: Any] = [:]
        for row in try db.rows("SELECT key, value FROM meta") {
            if let key = row["key"] as? String { meta[key] = row["value"] }
        }
        guard let library = meta["library"] as? String else { throw Database.Failure(description: "the library has no id") }
        var sources = try (meta["sources"] as? String).map {
            try Catalog.decoder.decode([String: Catalog.Source].self, from: Data($0.utf8))
        } ?? [:]
        // None until this version's first run ends: the status stays empty until then.
        if !sources.isEmpty {
            for provider in try sourcesOff() { sources[provider.rawValue] = Catalog.Source(state: .off) }
        }
        return Catalog.Index(
            library: library, generation: (meta["generation"] as? Int64).map(Int.init) ?? 0,
            scannedAt: (meta["scanned_at"] as? Double).map(Date.init(timeIntervalSince1970:)), sources: sources)
    }

    /// What reading a log found, when it is unchanged since it was read whole. Nil when it must be read.
    public func findings(unchangedLog path: String, size: Int64, mtime: Date) throws -> LogFindings? {
        let rows = try db.rows("SELECT * FROM log_files WHERE path = ?", [path])
        guard let row = rows.first, row["size"] as? Int64 == size, row["mtime"] as? Double == mtime.timeIntervalSince1970
        else { return nil }
        func decoded(_ column: String) -> [String: Int] {
            (row[column] as? String).flatMap { try? JSONDecoder().decode([String: Int].self, from: Data($0.utf8)) } ?? [:]
        }
        let n = ["records", "known_records", "turns", "final_replies", "candidates"].compactMap { (row[$0] as? Int64).map(Int.init) }
        return LogFindings(
            unknownRecordTypes: decoded("unknown_types"), unknownFields: decoded("unknown_fields"),
            counts: n.count == 5 ? LogCounts(records: n[0], knownRecords: n[1], turns: n[2], finalReplies: n[3], candidates: n[4]) : nil,
            fewerReplies: row["fewer_replies"] as? Int64 == 1, shortened: row["shortened"] as? Int64 == 1)
    }

    /// The size a log had when it was last read whole, whether it lost records since Gleaner first
    /// read it, and the final replies that read found (nil when it didn't count them); nil when it
    /// never was read whole.
    public func lastRead(logFile path: String) throws -> (size: Int64, shortened: Bool, finalReplies: Int?)? {
        try db.rows("SELECT size, shortened, final_replies FROM log_files WHERE path = ?", [path]).first.flatMap { row in
            (row["size"] as? Int64).map { ($0, row["shortened"] as? Int64 == 1, (row["final_replies"] as? Int64).map(Int.init)) }
        }
    }

    /// Keeps what reading a log whole found. Whether it lost records is kept by `markShortened`.
    public func markRead(logFile path: String, size: Int64, mtime: Date, findings: LogFindings) throws {
        func json(_ counts: [String: Int]) throws -> String { String(decoding: try JSONEncoder().encode(counts), as: UTF8.self) }
        let counts = findings.counts
        try db.run("""
            INSERT INTO log_files (path, size, mtime, unknown_types, unknown_fields, records, known_records, turns,
                                   final_replies, candidates, fewer_replies)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET size = excluded.size, mtime = excluded.mtime,
                unknown_types = excluded.unknown_types, unknown_fields = excluded.unknown_fields,
                records = excluded.records, known_records = excluded.known_records, turns = excluded.turns,
                final_replies = excluded.final_replies, candidates = excluded.candidates, fewer_replies = excluded.fewer_replies
            """, [path, size, mtime, try json(findings.unknownRecordTypes), try json(findings.unknownFields),
                  counts?.records, counts?.knownRecords, counts?.turns, counts?.finalReplies, counts?.candidates,
                  findings.fewerReplies ? 1 : 0])
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

    public func markSaved(deliveryID: String, at date: Date) throws {
        try db.run("UPDATE captures SET saved_at = ? WHERE delivery_id = ?", [date, deliveryID])
    }

    /// Every artifact with its deliveries, newest delivery first, artifacts by latest delivery.
    public func artifacts() throws -> [Artifact] {
        let rows = try db.rows("""
            SELECT d.id, d.path, d.delivered_at, d.reply_line, d.reply_rank, d.cwd, d.request, d.evidence, d.model,
                   s.provider, s.title, d.log_path, d.session_id, s.cwd AS session_cwd, s.model_provider,
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
                logPath: row["log_path"] as? String ?? "", capture: capture,
                model: row["model"] as? String, modelProvider: row["model_provider"] as? String))
            byPath[path] = list
        }
        let artifacts = byPath.map { path, deliveries in
            Artifact(path: path, deliveries: deliveries.reversed(), repository: repositories[path], checkout: checkouts[path])
        }
        return artifacts.sorted(by: Artifact.newerFirst)
    }
}
