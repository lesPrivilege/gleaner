import Foundation
import Testing
@testable import GleanerCore

/// Handovers, threads and timelines are regrouped deliveries: nothing is inferred or authored.
@Suite struct HandoverTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func delivery(_ path: String, log: String, at offset: TimeInterval?, request: String? = nil,
                  excerpt: String = "", line: Int = 1) -> Delivery {
        Delivery(id: "\(log)|\(path)|\(offset ?? -1)", number: 1, path: path, deliveredAt: offset.map(start.addingTimeInterval),
                 provider: .claudeCode, sessionTitle: log, request: request, cwd: "/p",
                 evidence: [Evidence(line: line, syntax: "link", rawTarget: path, anchor: nil, excerpt: excerpt)],
                 logPath: log, capture: nil)
    }

    /// Artifacts as the registry returns them: each file's deliveries newest first, numbered.
    func library(_ deliveries: [Delivery]) -> [Artifact] {
        Dictionary(grouping: deliveries, by: \.path).map { path, list in
            let ordered = list.sorted { ($0.deliveredAt ?? .distantPast) < ($1.deliveredAt ?? .distantPast) }
                .enumerated().map { i, d in var d = d; d.number = i + 1; return d }
            return Artifact(path: path, deliveries: ordered.reversed())
        }
        .sorted { ($0.latest.deliveredAt ?? .distantPast) > ($1.latest.deliveredAt ?? .distantPast) }
    }

    var sample: [Artifact] {
        library([
            delivery("/p/report.md", log: "a", at: 0, request: "retry policy", excerpt: "Report: report.md", line: 1),
            delivery("/p/diagram.svg", log: "a", at: 0, request: "retry policy", excerpt: "Diagram: diagram.svg", line: 2),
            delivery("/p/report.md", log: "a", at: 3600, request: "tighten it", excerpt: "Updated report.md"),
            delivery("/p/notes.md", log: "b", at: 1800, request: "notes", excerpt: "Notes"),
            delivery("/p/notes.md", log: "b", at: 2 * 86_400, request: "more notes", excerpt: "More notes"),
            delivery("/p/old.md", log: "c", at: nil),
        ])
    }

    @Test func oneReplyIsOneHandover() throws {
        let all = Handovers.all(sample)
        #expect(all.count == 5)
        let first = try #require(all.first { $0.request == "retry policy" })
        #expect(first.items.map(\.artifact.name) == ["diagram.svg", "report.md"])
        #expect(first.excerpts == ["Report: report.md", "Diagram: diagram.svg"])
        #expect(all.map(\.request) == ["more notes", "tighten it", "notes", "retry policy", nil])
    }

    @Test func threadIsOneLogOldestFirst() {
        let thread = Handovers.thread(logPath: "a", in: sample)
        #expect(thread.map(\.request) == ["retry policy", "tighten it"])
        #expect(thread.map { $0.items.map(\.delivery.number) } == [[1, 1], [2]])
        #expect(Handovers.thread(logPath: "b", in: sample).map(\.request) == ["notes", "more notes"])
    }

    @Test func timelineGroupsByDayNewestFirstAcrossLogs() {
        let days = Handovers.timeline(sample, calendar: utc)
        #expect(days.map { $0.handovers.map(\.request) } == [["more notes"], ["tighten it", "notes", "retry policy"], [nil]])
        #expect(days.last?.day == nil)
        // Only the files asked for: the diagram's own timeline drops the report it was delivered with.
        let diagram = sample.filter { $0.name == "diagram.svg" }
        #expect(Handovers.timeline(diagram, calendar: utc).flatMap(\.handovers).map { $0.items.map(\.artifact.name) } == [["diagram.svg"]])
    }

    @Test func ordersByLatestActivityAndName() {
        let day: TimeInterval = 86_400
        let files = library([
            delivery("/p/busy.md", log: "a", at: 1 * day), delivery("/p/busy.md", log: "a", at: 2 * day),
            delivery("/p/busy.md", log: "b", at: 3 * day), delivery("/p/fresh.md", log: "a", at: 5 * day),
            delivery("/p/old/stale.md", log: "c", at: -30 * day), delivery("/p/stale.md", log: "c", at: -29 * day),
        ])
        let now = start.addingTimeInterval(6 * day)
        #expect(LibraryOrder.latest.sorted(files, now: now).map(\.name) == ["fresh.md", "busy.md", "stale.md", "stale.md"])
        #expect(LibraryOrder.activity.sorted(files, now: now).map(\.name) == ["busy.md", "fresh.md", "stale.md", "stale.md"])
        #expect(LibraryOrder.name.sorted(files, now: now).map(\.path) == ["/p/busy.md", "/p/fresh.md", "/p/old/stale.md", "/p/stale.md"])
        #expect(files.map { LibraryOrder.recentDeliveries($0, now: now) } == [1, 3, 0, 0])
    }
}
