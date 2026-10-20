import Foundation
import Testing
@testable import GleanerCore

@Suite struct CaptureTimingTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString)")
    let delivered = Date(timeIntervalSince1970: 1_790_000_000)

    func provenance(modified: TimeInterval, capturedAfter: TimeInterval) throws -> Provenance {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("\(UUID().uuidString).md")
        try "bytes".write(to: file, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: delivered.addingTimeInterval(modified)], ofItemAtPath: file.path)
        let indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("\(UUID().uuidString).sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("handoff")),
            sources: LogSources(claudeProjects: root, codexHome: root))
        return indexer.capture(file.path, deliveredAt: delivered, now: delivered.addingTimeInterval(capturedAfter)).provenance
    }

    @Test func bytesWrittenBeforeTheReplyAndReadSoonAfterAreTheDelivery() throws {
        #expect(try provenance(modified: -30, capturedAfter: 5) == .atDelivery)
        #expect(try provenance(modified: 1, capturedAfter: 5) == .atDelivery)
    }

    @Test func bytesWrittenAfterTheReplyAreFirstSeenLater() throws {
        #expect(try provenance(modified: 3, capturedAfter: 5) == .firstSeenAfterDelivery)
        #expect(try provenance(modified: 61, capturedAfter: 90) == .firstSeenAfterDelivery)
    }

    @Test func aLateFirstLookIsFirstSeenLaterEvenIfUnmodified() throws {
        #expect(try provenance(modified: -30, capturedAfter: 601) == .firstSeenAfterDelivery)
    }

    @Test func aReplyDatedAfterTheLookIsNotTheDelivery() throws {
        // A clock moved, or a log carries a wrong time: a look a day before the reply proves nothing.
        #expect(try provenance(modified: -86_430, capturedAfter: -86_400) == .firstSeenAfterDelivery)
        // Within the tolerance, the writers' clocks merely disagree.
        #expect(try provenance(modified: -30, capturedAfter: -1) == .atDelivery)
    }
}
