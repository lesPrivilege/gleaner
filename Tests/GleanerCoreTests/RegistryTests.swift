import Foundation
import Testing
@testable import GleanerCore

@Suite struct RegistryTests {
    @Test func rereadingALogKeepsAKnownTitle() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        let registry = try Registry(path: path)
        try registry.upsert(SessionInfo(provider: .codex, id: "s", title: "Import screen", cwd: "/p", logPath: "/l"))
        try registry.upsert(SessionInfo(provider: .codex, id: "s", title: nil, cwd: nil, logPath: "/l"))
        let row = try registry.db.rows("SELECT title, cwd FROM sessions WHERE id = 's'").first
        #expect(row?["title"] as? String == "Import screen")
        #expect(row?["cwd"] as? String == "/p")
    }

    @Test func pruningOneLogNeverTouchesAnotherLogOfTheSameSession() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        let registry = try Registry(path: path)
        try registry.upsert(SessionInfo(provider: .claudeCode, id: "s", title: nil, cwd: nil, logPath: "/a.jsonl"))
        try registry.upsertDelivery(id: "da", sessionID: "s", logPath: "/a.jsonl", path: "/p/a.md", deliveredAt: nil,
                                    cwd: nil, repository: nil, request: nil, evidence: [])
        try registry.upsert(SessionInfo(provider: .claudeCode, id: "s", title: nil, cwd: nil, logPath: "/b.jsonl"))
        try registry.upsertDelivery(id: "db", sessionID: "s", logPath: "/b.jsonl", path: "/p/b.md", deliveredAt: nil,
                                    cwd: nil, repository: nil, request: nil, evidence: [])
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
                                    cwd: nil, repository: "/r", request: nil, evidence: [])
        #expect(try registry.artifacts().first?.projectFolder == "/r")
    }
}
