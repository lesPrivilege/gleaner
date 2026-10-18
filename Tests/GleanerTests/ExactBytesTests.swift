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
    // Fractional, as real logs have them: a time that doesn't read back exactly fails these tests.
    let then = Date(timeIntervalSince1970: 1_792_281_600.4075909)

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
        await model.observe(model.file(in: result))
        await model.stage(sha: try #require(delivery.sha256), artifact: model.file(in: result))
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
            DROP INDEX captures_reply; ALTER TABLE captures DROP COLUMN reply_times; ALTER TABLE captures DROP COLUMN path; ALTER TABLE captures DROP COLUMN log_path;
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

    /// Two replies whose records share their time: the time can't tell them apart, so each is
    /// found by its place, as before Gleaner kept the times. A log that only grows keeps each one's
    /// bytes, read after read, inside the window where a new capture would count as at delivery.
    @Test func repliesWithTheSameTimesKeepTheirBytesAsTheLogGrows() async throws {
        let first = try record("user", "first version", then) + record("assistant", "[report](report.md)", then)
        try writeFile("VERSION ONE", then)
        try first.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(1) })
        let both = try first + record("user", "second version", then) + record("assistant", "[report](report.md)", then)
        try writeFile("VERSION TWO", then.addingTimeInterval(1))
        try both.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(2) })
        try (both + record("user", "anything else?", then.addingTimeInterval(4))).write(to: log, atomically: true, encoding: .utf8)
        #expect(try indexer.run(now: { then.addingTimeInterval(5) }).newDeliveries == 0)
        #expect(try await handedOver("first version").bytes == "VERSION ONE")
        #expect(try await handedOver("second version").bytes == "VERSION TWO")
        #expect(try indexer.registry.db.rows("SELECT COUNT(*) AS n FROM captures").first?["n"] as? Int64 == 2)
    }

    /// A rewritten log that puts a reply Gleaner never captured, written at the same time as one it
    /// did, before it: that time is shared, so neither is found by it, and the new reply doesn't
    /// take the captured one's bytes from its time alone.
    @Test func aNewReplyWithAnotherReplysTimeNeverTakesItsCaptureByThatTime() async throws {
        let mine = try record("user", "first version", then) + record("assistant", "[report](report.md)", then)
        try writeFile("VERSION ONE", then)
        try mine.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(1) })
        let other = try record("user", "second version", then) + record("assistant", "[report](report.md)", then)
        try writeFile("VERSION TWO", then.addingTimeInterval(1))
        try ("{\"type\":\"system\"}\n{\"type\":\"system\"}\n{\"type\":\"system\"}\n" + other + mine)
            .write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(9999) })
        #expect(try await handedOver("second version").delivery.capture?.provenance == .firstSeenAfterDelivery)
    }

    /// A reply with a record time no other reply has is found by it, though its first mention's
    /// time is shared: rewritten after a reply written at that same time, it keeps its own bytes,
    /// and the other reply never takes them at delivery.
    @Test func aReplyIsFoundByATimeOfItsOwnWhenItsFirstMentionsTimeIsShared() async throws {
        let y = try record("user", "y request", then) + record("assistant", "[report](report.md)", then)
        try writeFile("Y BYTES", then)
        try y.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(1) })
        let later = then.addingTimeInterval(5)
        let x = try record("user", "x request", then) + record("assistant", "[report](report.md)", then) + record("assistant", "All done.", later)
        try writeFile("X BYTES", then.addingTimeInterval(1))
        try (y + x).write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { later.addingTimeInterval(1) })
        #expect(try await handedOver("x request").bytes == "X BYTES")

        try (x + y).write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(9999) })
        #expect(try await handedOver("x request").bytes == "X BYTES")
        let other = try await handedOver("y request")
        #expect(other.bytes == "Y BYTES" || other.delivery.capture?.provenance == .firstSeenAfterDelivery)
    }

    /// A reply whose place another reply's capture holds, and whose times another reply shares,
    /// gets an id of its own once, and the same one on every read after.
    @Test func aReplyGivenAnIdOfItsOwnKeepsItAsTheLogGrows() async throws {
        let tb = then.addingTimeInterval(-100)
        let b = try record("user", "b request", tb) + record("assistant", "[report](report.md)", tb)
        try writeFile("B BYTES", tb)
        try b.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { tb.addingTimeInterval(1) })
        let a = try record("user", "a request", then) + record("assistant", "[report](report.md)", then)
        let x = try record("user", "x request", then) + record("assistant", "[report](report.md)", then)
        try writeFile("A BYTES", then)
        var text = a + x + b
        try text.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(1) })
        let first = try await handedOver("a request").delivery.id
        for n in 1...3 {
            text += try record("user", "more \(n)", then.addingTimeInterval(Double(10 * n)))
            try text.write(to: log, atomically: true, encoding: .utf8)
            #expect(try indexer.run(now: { then.addingTimeInterval(Double(10 * n + 1)) }).newDeliveries == 0)
            #expect(try await handedOver("a request").delivery.id == first)
        }
        #expect(try await handedOver("b request").bytes == "B BYTES")
    }

    /// A reply Gleaner never captured, with a time of its own, rewritten into the place of a reply
    /// written at its other time: it doesn't take that reply's bytes by the place.
    @Test func aNewReplyWithATimeOfItsOwnNeverTakesACaptureAtItsPlace() async throws {
        let y = try record("user", "y request", then) + record("assistant", "[report](report.md)", then)
        try writeFile("Y BYTES", then)
        try y.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(1) })
        let x = try record("user", "x request", then) + record("assistant", "[report](report.md)", then)
            + record("assistant", "All done.", then.addingTimeInterval(5))
        try writeFile("X BYTES", then.addingTimeInterval(1))
        try (x + y).write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(9999) })
        let taken = try await handedOver("x request")
        #expect(taken.bytes != "Y BYTES" || taken.delivery.capture?.provenance != .atDelivery)
    }

    /// A reply whose records carry no time, at a place another reply's capture holds, gets an id of
    /// its own once, and keeps it as the log grows.
    @Test func aReplyWithoutTimesKeepsTheIdItWasGiven() async throws {
        let b = try record("user", "b request", then) + record("assistant", "[report](report.md)", then)
        try writeFile("B BYTES", then)
        try b.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(1) })
        let a = try record("user", "a request", nil) + record("assistant", "[report](report.md)", nil)
        try writeFile("A BYTES", then.addingTimeInterval(2))
        var text = a + b
        try text.write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { then.addingTimeInterval(3) })
        let first = try await handedOver("a request").delivery.id
        for n in 1...3 {
            try writeFile("A BYTES CHANGED \(n)", then.addingTimeInterval(Double(10 * n)))
            text += try record("user", "more \(n)", then.addingTimeInterval(Double(10 * n)))
            try text.write(to: log, atomically: true, encoding: .utf8)
            #expect(try indexer.run(now: { then.addingTimeInterval(Double(10 * n + 1)) }).newDeliveries == 0)
            #expect(try await handedOver("a request").delivery.id == first)
        }
    }
}
