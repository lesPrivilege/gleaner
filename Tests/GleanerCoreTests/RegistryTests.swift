import Foundation
import Testing
@testable import GleanerCore

@Suite struct RegistryTests {
    @Test func aLibraryAlreadyMadeOpensWithoutAWriteWhileALogIsRead() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        let library = try Registry(path: path).index().library
        // Another connection holds the write lock, as the indexer does while it reads a log; opening
        // the library again, as the app does to record a correction, waits for no write.
        let reading = try Database(path: path)
        try reading.execute("BEGIN IMMEDIATE")
        defer { try? reading.execute("ROLLBACK") }
        #expect(try Registry(path: path).index().library == library)
    }

    @Test func rereadingALogKeepsAKnownTitle() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        let registry = try Registry(path: path)
        try registry.upsert(SessionInfo(provider: .codex, id: "s", title: "Import screen", cwd: "/p", logPath: "/l"))
        try registry.upsert(SessionInfo(provider: .codex, id: "s", title: nil, cwd: nil, logPath: "/l"))
        let row = try registry.db.rows("SELECT title, cwd FROM sessions WHERE id = 's'").first
        #expect(row?["title"] as? String == "Import screen")
        #expect(row?["cwd"] as? String == "/p")
    }

    @Test func aFilesDecisionsAreFoundByItsPathNotByReadingEveryOne() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        let registry = try Registry(path: path)
        // Every read of a file asks whether it was kept; every decision appended grows the table.
        let plans = try registry.db.rows("EXPLAIN QUERY PLAN SELECT target, made_at FROM corrections WHERE kind = 'kept' AND subject = ?",
                                         ["/p/a.png"]).compactMap { $0["detail"] as? String }
        #expect(plans.contains { $0.hasPrefix("SEARCH") && $0.contains("INDEX corrections_subject") }, "\(plans)")
    }

    @Test func pruningOneLogNeverTouchesAnotherLogOfTheSameSession() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        let registry = try Registry(path: path)
        try registry.upsert(SessionInfo(provider: .claudeCode, id: "s", title: nil, cwd: nil, logPath: "/a.jsonl"))
        try registry.upsertDelivery(id: "da", sessionID: "s", logPath: "/a.jsonl", path: "/p/a.md", deliveredAt: nil,
                                    replyLine: 1, replyRank: 0, cwd: nil, request: nil, evidence: [])
        try registry.upsert(SessionInfo(provider: .claudeCode, id: "s", title: nil, cwd: nil, logPath: "/b.jsonl"))
        try registry.upsertDelivery(id: "db", sessionID: "s", logPath: "/b.jsonl", path: "/p/b.md", deliveredAt: nil,
                                    replyLine: 1, replyRank: 0, cwd: nil, request: nil, evidence: [])
        try registry.removeDeliveries(logPath: "/b.jsonl", except: [])
        let left = try registry.db.rows("SELECT id, log_path FROM deliveries")
        #expect(left.map { $0["id"] as? String } == ["da"])
        #expect(try registry.artifacts().first?.latest.logPath == "/a.jsonl")
    }

    @Test func aLibraryFromBeforeRepositoriesWereRecordedGainsThem() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        try Database(path: path).execute("""
            CREATE TABLE deliveries (
                id TEXT PRIMARY KEY, session_id TEXT NOT NULL, path TEXT NOT NULL, delivered_at REAL,
                cwd TEXT, request TEXT, evidence TEXT NOT NULL, log_path TEXT);
            """)
        let registry = try Registry(path: path)
        try registry.upsert(SessionInfo(provider: .claudeCode, id: "s", title: nil, cwd: nil, logPath: "/a.jsonl"))
        try registry.upsertDelivery(id: "d", sessionID: "s", logPath: "/a.jsonl", path: "/r/a.md", deliveredAt: nil,
                                    replyLine: 1, replyRank: 0, cwd: nil, request: nil, evidence: [])
        try registry.addCapture(Capture(sha256: "abc", size: 1, modifiedAt: nil, observedAt: Date(), savedAt: nil,
                                        provenance: .atDelivery, kind: .file), for: "d", logPath: "/a.jsonl", path: "/r/a.md", replyTimes: [])
        try registry.record(repository: "/r", checkout: "/r-feature", of: "d")
        #expect(try registry.artifacts().first?.projectFolder == "/r")
        #expect(try registry.artifacts().first?.checkout == Checkout(folder: "/r-feature", repository: "/r"))
    }

    @Test func aLibraryThatKeptCheckoutsWithItsDeliveriesKeepsThemWithItsCaptures() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        try Database(path: path).execute("""
            CREATE TABLE sessions (id TEXT PRIMARY KEY, provider TEXT NOT NULL, title TEXT, cwd TEXT, log_path TEXT NOT NULL);
            CREATE TABLE deliveries (
                id TEXT PRIMARY KEY, session_id TEXT NOT NULL, path TEXT NOT NULL, delivered_at REAL,
                cwd TEXT, request TEXT, evidence TEXT NOT NULL, log_path TEXT, repository TEXT, checkout TEXT,
                reply_line INTEGER, reply_rank INTEGER);
            CREATE TABLE captures (
                delivery_id TEXT PRIMARY KEY, sha256 TEXT, size INTEGER, mtime REAL, observed_at REAL NOT NULL,
                saved_at REAL, provenance TEXT NOT NULL, kind TEXT NOT NULL);
            INSERT INTO sessions VALUES ('s', 'claude_code', NULL, NULL, '/a.jsonl');
            INSERT INTO deliveries VALUES ('d', 's', '/r/wt/a.md', 0, NULL, NULL, '[]', '/a.jsonl', '/r', '/r/wt', 1, 0);
            INSERT INTO captures VALUES ('d', 'abc', 1, 0, 0, 0, 'at_delivery', 'file');
            """)
        let registry = try Registry(path: path)
        #expect(try registry.artifacts().first?.checkout == Checkout(folder: "/r/wt", repository: "/r"))
        // A reread that drops the delivery leaves them with its capture.
        try registry.removeDeliveries(logPath: "/a.jsonl", except: [])
        #expect(try registry.db.rows("SELECT repository, checkout FROM captures").first?["checkout"] as? String == "/r/wt")
    }

    @Test func aMigrationStoppedPartwayIsMadeWholeNextLaunch() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        try Database(path: path).execute("""
            CREATE TABLE captures (
                delivery_id TEXT PRIMARY KEY, sha256 TEXT, size INTEGER, mtime REAL, observed_at REAL NOT NULL,
                saved_at REAL, provenance TEXT NOT NULL, is_directory INTEGER NOT NULL);
            INSERT INTO captures VALUES ('file', 'abc', 1, 0, 0, 0, 'at_delivery', 0);
            CREATE INDEX folders ON captures(is_directory);
            """)
        // The index keeps the old column from being dropped, as a lock another copy of Gleaner holds would.
        #expect(throws: (any Error).self) { try Registry(path: path) }
        try Database(path: path).execute("DROP INDEX folders")

        let registry = try Registry(path: path)
        #expect(try !registry.db.rows("PRAGMA table_info(captures)").contains { $0["name"] as? String == "is_directory" })
        #expect(try registry.db.rows("SELECT kind FROM captures").map { $0["kind"] as? String } == ["file"])
        try registry.addCapture(Capture(sha256: "def", size: 1, modifiedAt: nil, observedAt: Date(), savedAt: nil,
                                        provenance: .atDelivery, kind: .file), for: "new", logPath: "/a.jsonl", path: "/a.md", replyTimes: [])
    }

    @Test func aLibraryFromBeforeCapturesSaidWhatTheyFoundGainsIt() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        try Database(path: path).execute("""
            CREATE TABLE captures (
                delivery_id TEXT PRIMARY KEY, sha256 TEXT, size INTEGER, mtime REAL, observed_at REAL NOT NULL,
                saved_at REAL, provenance TEXT NOT NULL, is_directory INTEGER NOT NULL);
            INSERT INTO captures VALUES ('file', 'abc', 1, 0, 0, 0, 'at_delivery', 0);
            INSERT INTO captures VALUES ('folder', NULL, NULL, 0, 0, NULL, 'at_delivery', 1);
            INSERT INTO captures VALUES ('gone', NULL, NULL, NULL, 0, NULL, 'never_observed', 0);
            INSERT INTO captures VALUES ('unread', NULL, 3, 0, 0, NULL, 'first_seen_after_delivery', 0);
            """)
        let registry = try Registry(path: path)
        let rows = try registry.db.rows("SELECT delivery_id, kind, provenance FROM captures ORDER BY delivery_id")
        #expect(rows.map { "\($0["delivery_id"]!) \($0["kind"]!) \($0["provenance"]!)" } == [
            "file file at_delivery", "folder directory at_delivery",
            "gone missing never_observed",
            // A file Gleaner couldn't read was recorded as seen; it never was.
            "unread unreadable never_observed",
        ])
        #expect(try !registry.db.rows("PRAGMA table_info(captures)").contains { $0["name"] as? String == "is_directory" })
    }

    /// A library from before paths had one spelling keeps its captures under the spelling the
    /// logs now give, so a reread finds them.
    @Test func pathsStoredUnderPrivateAreRespelledOnce() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        let registry = try Registry(path: path)
        try registry.addCapture(Capture(sha256: "abc", size: 1, modifiedAt: nil, observedAt: Date(), savedAt: nil, provenance: .atDelivery, kind: .file),
                                for: "d", logPath: "/l.jsonl", path: "/private/tmp/p/report.md", replyTimes: [1])
        try registry.record(repository: "/private/var/x/app", checkout: "/private/var/x/app", of: "d")
        try registry.db.execute("PRAGMA user_version = 12")
        let reopened = try Registry(path: path)
        let row = try #require(try reopened.db.rows("SELECT path, repository, checkout FROM captures").first)
        #expect(row["path"] as? String == "/tmp/p/report.md")
        #expect(row["repository"] as? String == "/var/x/app")
        #expect(try reopened.captures(logPath: "/l.jsonl", path: "/tmp/p/report.md").map(\.id) == ["d"])
    }

    /// A library a later Gleaner opened is left as it is: its version isn't set back, so that Gleaner
    /// finds it as it left it, and no table is made or changed.
    @Test func aLibraryOfALaterGleanerIsRefusedUnchanged() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        let later = Registry.extractorVersion + 1
        do {
            let db = try Database(path: path)
            try db.execute("CREATE TABLE later (x INTEGER); PRAGMA user_version = \(later);")
        }
        #expect(throws: Registry.Failure.newer(version: later)) { try Registry(path: path) }
        let db = try Database(path: path)
        #expect(try db.rows("PRAGMA user_version").first?["user_version"] as? Int64 == Int64(later))
        #expect(try db.rows("SELECT name FROM sqlite_master").compactMap { $0["name"] as? String } == ["later"])
    }

    /// An earlier Gleaner's library is copied whole, as it was, before this one updates it; a new
    /// library, or one already this version's, isn't.
    @Test func anEarlierLibraryIsBackedUpBeforeItIsUpdated() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("registry.sqlite").path, backups = Registry.backups(of: path)
        func copies() -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []).sorted() }
        do {
            let registry = try Registry(path: path)
            try registry.db.execute("CREATE TABLE marker (x TEXT); INSERT INTO marker VALUES ('before');")
        }
        #expect(copies().isEmpty)
        _ = try Registry(path: path)
        #expect(copies().isEmpty)

        let earlier = Registry.extractorVersion - 1
        try Database(path: path).execute("PRAGMA user_version = \(earlier)")
        let updated = try Registry(path: path)
        #expect(try updated.db.rows("PRAGMA user_version").first?["user_version"] as? Int64 == Int64(Registry.extractorVersion))
        let names = copies()
        try #require(names.count == 1)
        #expect(names[0].hasPrefix("registry-v\(earlier)-"))
        let copy = try Database(path: backups.appendingPathComponent(names[0]).path)
        #expect(try copy.rows("PRAGMA user_version").first?["user_version"] as? Int64 == Int64(earlier))
        #expect(try copy.rows("SELECT x FROM marker").first?["x"] as? String == "before")
        #expect(try copy.rows("SELECT mtime FROM log_files").isEmpty)
    }
}
