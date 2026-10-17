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
}
