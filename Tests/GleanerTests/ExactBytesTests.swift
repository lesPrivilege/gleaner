import AppKit
import Foundation
import Testing
@testable import Gleaner
@testable import GleanerCore

/// The bytes the library hands over are the selected delivery's, whatever happened to the log
/// that named them or to the copy Gleaner prepared (the independent review's A1 and A2).
@MainActor @Suite struct ExactBytesTests {
    let root: URL
    let project: URL
    let file: URL
    let log: URL
    let indexer: Indexer
    let then = Date(timeIntervalSince1970: 1_792_281_600)

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("gleaner-exact-\(UUID().uuidString)")
        project = root.appendingPathComponent("project")
        let logs = root.appendingPathComponent("claude/synthetic")
        for dir in [project, logs] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        file = project.appendingPathComponent("report.md")
        log = logs.appendingPathComponent("session.jsonl")
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("handoff")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
    }

    func record(_ type: String, _ text: String, _ at: Date?) throws -> String {
        let content: Any = type == "user" ? text : [["type": "text", "text": text]]
        var object: [String: Any] = ["type": type, "sessionId": "synthetic", "cwd": project.path,
                                     "origin": ["kind": "human"], "message": ["role": type, "content": content]]
        if let at { object["timestamp"] = at.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
    }

    func writeFile(_ text: String, _ at: Date) throws {
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: at], ofItemAtPath: file.path)
    }

    /// What a person gets searching `query` and taking the top result: the delivery, and the bytes
    /// its hand-off copy holds.
    func handedOver(_ query: String) async throws -> (delivery: Delivery, bytes: String) {
        let model = LibraryModel(indexer: indexer)
        model.query = query
        let result = try #require(model.results.first)
        model.selection = result.id
        let delivery = model.delivery(in: result)
        await model.observe(result.artifact)
        await model.stage(sha: try #require(delivery.sha256), artifact: result.artifact)
        return (delivery, try String(contentsOf: try #require(model.selectedHandoffURL), encoding: .utf8))
    }

    /// Two deliveries of report.md: "first version" with VERSION ONE, "second version" with VERSION TWO.
    func deliverTwice() throws -> String {
        let first = try record("user", "first version", then) + record("assistant", "[report](report.md)", then)
        try writeFile("VERSION ONE", then)
        try first.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(1) })
        let secondAt = then.addingTimeInterval(10)
        let both = try first + record("user", "second version", secondAt) + record("assistant", "[report](report.md)", secondAt)
        try writeFile("VERSION TWO", secondAt)
        try both.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { secondAt.addingTimeInterval(1) })
        return both
    }

    @Test func aLogRewrittenWithItsRepliesMovedKeepsEachReplysBytes() async throws {
        let both = try deliverTwice()
        let before = try await handedOver("first version")
        #expect(before.bytes == "VERSION ONE")
        let second = try await handedOver("second version")
        #expect(second.bytes == "VERSION TWO")

        // The same complete log, rewritten with two records in front: every reply moves two lines,
        // and the first reply now sits where the second was.
        try ("{\"type\":\"system\"}\n{\"type\":\"system\"}\n" + both).write(to: log, atomically: true, encoding: .utf8)
        let report = try indexer.run(now: { then.addingTimeInterval(9999) })
        #expect(report.newDeliveries == 0)

        let first = try await handedOver("first version")
        #expect(first.delivery.id == before.delivery.id)
        #expect(first.delivery.sha256 == before.delivery.sha256)
        #expect(first.delivery.capture == before.delivery.capture)
        #expect(first.delivery.request == "first version")
        #expect(first.delivery.evidence.map(\.line) == [4])
        #expect(first.bytes == "VERSION ONE")
        let again = try await handedOver("second version")
        #expect(again.delivery.id == second.delivery.id)
        #expect(again.delivery.evidence.map(\.line) == [6])
        #expect(again.bytes == "VERSION TWO")
        #expect(try indexer.registry.artifacts().flatMap(\.deliveries).count == 2)
    }

    @Test func appendingToALogKeepsEveryDelivery() async throws {
        let both = try deliverTwice()
        let thirdAt = then.addingTimeInterval(20)
        try (both + record("user", "anything else?", thirdAt)).write(to: log, atomically: true, encoding: .utf8)
        #expect(try indexer.run(now: { thirdAt }).newDeliveries == 0)
        #expect(try await handedOver("first version").bytes == "VERSION ONE")
        #expect(try await handedOver("second version").bytes == "VERSION TWO")
    }

    /// A library from before Gleaner kept each capture's reply: its captures are tied to their
    /// replies by the delivery rows they had, so a reread after a rewrite still finds each one.
    @Test func aCaptureFromBeforeRepliesWereKeptIsStillFoundByItsReply() async throws {
        let both = try deliverTwice()
        let before = try await handedOver("first version")
        try indexer.registry.db.execute("""
            DROP INDEX captures_reply; ALTER TABLE captures DROP COLUMN reply_at; ALTER TABLE captures DROP COLUMN path; ALTER TABLE captures DROP COLUMN log_path;
            PRAGMA user_version = 1;
            """)
        let reopened = Indexer(registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
                               store: indexer.store, sources: indexer.sources)
        try ("{\"type\":\"system\"}\n{\"type\":\"system\"}\n" + both).write(to: log, atomically: true, encoding: .utf8)
        #expect(try reopened.run(now: { then.addingTimeInterval(9999) }).newDeliveries == 0)
        let after = try #require(try reopened.registry.artifacts().first).deliveries.first { $0.request == "first version" }
        #expect(after?.id == before.delivery.id)
        #expect(after?.sha256 == before.delivery.sha256)
    }

    /// Two replies Gleaner can't tell apart by the times of their records: neither takes the other's
    /// capture, and reading again settles on the same deliveries instead of capturing anew each time.
    @Test func repliesWithTheSameTimesNeverTakeEachOthersBytes() async throws {
        let first = try record("user", "first version", then) + record("assistant", "[report](report.md)", then)
        try writeFile("VERSION ONE", then)
        try first.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(1) })
        let both = try first + record("user", "second version", then) + record("assistant", "[report](report.md)", then)
        try writeFile("VERSION TWO", then.addingTimeInterval(1))
        try both.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(2) })
        #expect(try await handedOver("first version").bytes == "VERSION ONE")

        try ("{\"type\":\"system\"}\n" + both).write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(9999) })
        let moved = try await handedOver("first version")
        // Never VERSION TWO as what the first request was given: the bytes there now, first seen later.
        #expect(moved.delivery.request == "first version")
        #expect(moved.delivery.capture?.provenance == .firstSeenAfterDelivery)
        let count = try indexer.registry.db.rows("SELECT COUNT(*) AS n FROM captures").first?["n"] as? Int64
        try ("{\"type\":\"system\"}\n" + both + "\n").write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(19999) })
        #expect(try indexer.registry.db.rows("SELECT COUNT(*) AS n FROM captures").first?["n"] as? Int64 == count)
    }
}
