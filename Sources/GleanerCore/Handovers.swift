import Foundation

/// One reply and every file it named, with the request it answered (docs/design/structure.md).
/// Derived from deliveries alone: one log and one reply line make one handover, however many
/// records the reply took (review rulings §2, A8).
public struct Handover: Sendable, Identifiable {
    /// A file the reply named, with that file's delivery from this reply.
    public struct Item: Sendable, Identifiable {
        public var artifact: Artifact
        public var delivery: Delivery
        public var id: Delivery.ID { delivery.id }
    }

    public var logPath: String
    public var replyLine: Int?
    /// The reply's earliest recorded time; nil when none of its records has one.
    public var deliveredAt: Date?
    /// In the order the reply named them.
    public var items: [Item]

    public var id: String { items[0].delivery.id }
    public var first: Delivery { items[0].delivery }
    public var request: String? { first.request }
    public var provider: Provider { first.provider }
    public var sessionTitle: String? { first.sessionTitle }

    /// The reply's own words that named these files, in reply order, each once.
    public var excerpts: [String] {
        var seen = Set<String>()
        return items.flatMap(\.delivery.evidence).sorted { $0.line < $1.line }
            .map(\.excerpt).filter { seen.insert($0).inserted }
    }
}

/// A day of handovers in a timeline. `day` is nil for handovers with no recorded time.
public struct HandoverDay: Sendable, Identifiable {
    public var day: Date?
    public var handovers: [Handover]
    public var id: Double { day?.timeIntervalSince1970 ?? -1 }
}

public enum Handovers {
    /// Every handover of `artifacts`, newest first, holding only their files. A delivery read
    /// before Gleaner recorded reply lines is a handover of its own: nothing says which reply it
    /// shared. A delivered folder's files come with their folder, and a file the person kept was
    /// handed over by no reply, so neither is one.
    public static func all(_ artifacts: [Artifact]) -> [Handover] {
        var groups: [String: Handover] = [:]
        for artifact in artifacts {
            for delivery in artifact.deliveries where delivery.member == nil && delivery.kept == nil {
                groups[delivery.replyKey ?? delivery.id, default: Handover(logPath: delivery.logPath, replyLine: delivery.replyLine, items: [])]
                    .items.append(.init(artifact: artifact, delivery: delivery))
            }
        }
        return groups.values.map { group in
            var group = group
            group.items.sort { ($0.delivery.replyRank, $0.artifact.path) < ($1.delivery.replyRank, $1.artifact.path) }
            group.deliveredAt = group.items.compactMap(\.delivery.deliveredAt).min()
            return group
        }
        .sorted(by: newestFirst)
    }

    /// One log's handovers in the order the log holds them: what one conversation produced.
    public static func thread(logPath: String, in artifacts: [Artifact]) -> [Handover] {
        all(artifacts.filter { $0.deliveries.contains { $0.logPath == logPath } })
            .filter { $0.logPath == logPath }
            .sorted { a, b in
                switch (a.replyLine, b.replyLine) {
                case let (x?, y?): x < y
                // Without a line, by time, and after the replies placed in the log.
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): newestFirst(b, a)
                }
            }
    }

    /// The handovers of `artifacts`, newest first and grouped by day, across every log, with the
    /// undated last. Only those files are kept in each handover: files the same reply named that
    /// aren't listed are left out.
    public static func timeline(_ artifacts: [Artifact], calendar: Calendar = .current) -> [HandoverDay] {
        var days: [HandoverDay] = []
        for handover in all(artifacts) {
            let day = handover.deliveredAt.map { calendar.startOfDay(for: $0) }
            if let last = days.indices.last, days[last].day == day {
                days[last].handovers.append(handover)
            } else {
                days.append(HandoverDay(day: day, handovers: [handover]))
            }
        }
        return days
    }

    static func newestFirst(_ a: Handover, _ b: Handover) -> Bool {
        let (x, y) = (a.deliveredAt ?? .distantPast, b.deliveredAt ?? .distantPast)
        return x != y ? x > y : a.id < b.id
    }
}
