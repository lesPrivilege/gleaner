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

    /// A delivery from the reply at `reply` in `log`, the `rank`th file it named.
    func delivery(_ path: String, log: String, reply: Int?, at offset: TimeInterval?, rank: Int = 0,
                  request: String? = nil, excerpt: String = "", line: Int = 1) -> Delivery {
        Delivery(id: "\(log)|\(path)|\(reply ?? -1)|\(offset ?? -1)", number: 1, path: path,
                 deliveredAt: offset.map(start.addingTimeInterval), replyLine: reply, replyRank: rank,
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
            // One reply written as two records, seconds apart: one handover, in the order it named them.
            delivery("/p/report.md", log: "a", reply: 10, at: 5, rank: 0, request: "retry policy", excerpt: "Report: report.md", line: 1),
            delivery("/p/diagram.svg", log: "a", reply: 10, at: 0, rank: 1, request: "retry policy", excerpt: "Diagram: diagram.svg", line: 2),
            delivery("/p/report.md", log: "a", reply: 20, at: 3600, request: "tighten it", excerpt: "Updated report.md"),
            delivery("/p/notes.md", log: "b", reply: 4, at: 1800, request: "notes", excerpt: "Notes"),
            delivery("/p/notes.md", log: "b", reply: 9, at: 2 * 86_400, request: "more notes", excerpt: "More notes"),
            delivery("/p/old.md", log: "c", reply: nil, at: nil),
        ])
    }

    @Test func oneReplyIsOneHandover() throws {
        let all = Handovers.all(sample)
        #expect(all.count == 5)
        let first = try #require(all.first { $0.request == "retry policy" })
        #expect(first.items.map(\.artifact.name) == ["report.md", "diagram.svg"])
        #expect(first.excerpts == ["Report: report.md", "Diagram: diagram.svg"])
        // The reply's earliest record dates it.
        #expect(first.deliveredAt == start)
        #expect(all.map(\.request) == ["more notes", "tighten it", "notes", "retry policy", nil])
    }

    @Test func twoRepliesAtOneTimeStayApart() {
        let files = library([
            delivery("/p/a.md", log: "a", reply: 3, at: 0, request: "first"),
            delivery("/p/b.md", log: "a", reply: 7, at: 0, request: "second"),
        ])
        #expect(Handovers.all(files).map { $0.items.map(\.artifact.name) }.sorted { $0[0] < $1[0] } == [["a.md"], ["b.md"]])
    }

    @Test func foldersFilesAndKeptFilesAreNoHandovers() {
        var member = delivery("/p/site/index.html", log: "a", reply: 3, at: 0)
        member.member = Membership(folderDelivery: "folder", folder: "/p/site")
        var kept = delivery("/p/scratch.png", log: "a", reply: nil, at: 0)
        kept.kept = Keeping(keptAt: start, observed: .appeared)
        let files = library([delivery("/p/site", log: "a", reply: 3, at: 0), member, kept])
        #expect(Handovers.all(files).map { $0.items.map(\.artifact.path) } == [["/p/site"]])
    }

    @Test func threadIsOneLogInReplyOrder() {
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

    @Test func timelineOfOneUndatedDelivery() {
        let days = Handovers.timeline(library([delivery("/p/old.md", log: "c", reply: nil, at: nil)]), calendar: utc)
        #expect(days.count == 1)
        #expect(days[0].day == nil)
        #expect(days[0].handovers.map { $0.items.map(\.artifact.name) } == [["old.md"]])
    }

    @Test func timelineOfOnlyUndatedDeliveries() {
        let days = Handovers.timeline(library([
            delivery("/p/old.md", log: "c", reply: nil, at: nil),
            delivery("/p/older.md", log: "c", reply: 2, at: nil),
            delivery("/p/oldest.md", log: "d", reply: 5, at: nil),
            delivery("/p/with-oldest.md", log: "d", reply: 5, at: nil, rank: 1),
        ]), calendar: utc)
        #expect(days.count == 1)
        #expect(days[0].day == nil)
        #expect(days[0].handovers.map(\.items.count).sorted() == [1, 1, 2])
    }

    @Test func emptyLibraryHasNoTimeline() {
        #expect(Handovers.timeline([], calendar: utc).isEmpty)
    }
}
