import Foundation

/// One reply and every file it named, with the request it answered (docs/design/structure.md).
/// Derived from deliveries alone: one log and one reply time make one handover.
public struct Handover: Sendable, Identifiable {
    /// A file the reply named, with that file's delivery from this reply.
    public struct Item: Sendable, Identifiable {
        public var artifact: Artifact
        public var delivery: Delivery
        public var id: Delivery.ID { delivery.id }
    }

    public var logPath: String
    public var deliveredAt: Date?
    /// By file name.
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

/// A day of handovers in a project timeline. `day` is nil for deliveries with no recorded time.
public struct HandoverDay: Sendable, Identifiable {
    public var day: Date?
    public var handovers: [Handover]
    public var id: Double { day?.timeIntervalSince1970 ?? -1 }
}

public enum Handovers {
    /// Every handover, newest first. A delivery with no recorded time is a handover of its own:
    /// nothing says which reply it shared.
    public static func all(_ artifacts: [Artifact]) -> [Handover] {
        var groups: [String: Handover] = [:]
        for artifact in artifacts {
            for delivery in artifact.deliveries {
                let key = delivery.deliveredAt.map { "\(delivery.logPath)|\($0.timeIntervalSince1970)" } ?? delivery.id
                groups[key, default: Handover(logPath: delivery.logPath, deliveredAt: delivery.deliveredAt, items: [])]
                    .items.append(.init(artifact: artifact, delivery: delivery))
            }
        }
        return groups.values.map { group in
            var group = group
            group.items.sort { ($0.artifact.name, $0.artifact.path) < ($1.artifact.name, $1.artifact.path) }
            return group
        }
        .sorted(by: newestFirst)
    }

    /// One log's handovers, oldest first: what one conversation produced, in order.
    public static func thread(logPath: String, in artifacts: [Artifact]) -> [Handover] {
        all(artifacts.filter { $0.deliveries.contains { $0.logPath == logPath } })
            .filter { $0.logPath == logPath }
            .reversed()
    }

    /// The handovers of the given files, newest first and grouped by day, across every log. Only
    /// those files are kept in each handover; files the same reply named elsewhere are left out.
    public static func timeline(_ artifacts: [Artifact], calendar: Calendar = .current) -> [HandoverDay] {
        var days: [HandoverDay] = []
        for handover in all(artifacts) {
            let day = handover.deliveredAt.map { calendar.startOfDay(for: $0) }
            if days.last?.day == day { days[days.count - 1].handovers.append(handover) }
            else { days.append(HandoverDay(day: day, handovers: [handover])) }
        }
        return days
    }

    static func newestFirst(_ a: Handover, _ b: Handover) -> Bool {
        let (x, y) = (a.deliveredAt ?? .distantPast, b.deliveredAt ?? .distantPast)
        return x != y ? x > y : a.id < b.id
    }
}

/// How the library lists files (docs/design/structure.md, ordering choices).
public enum LibraryOrder: String, Sendable, CaseIterable {
    /// What arrived most recently.
    case latest
    /// Most deliveries in the last `activityWindow`, then latest; shows where work is happening now.
    case activity
    /// Scanning for a known file.
    case name

    public static let activityWindow: TimeInterval = 14 * 24 * 3600

    /// Deliveries of `artifact` within the activity window before `now`.
    public static func recentDeliveries(_ artifact: Artifact, now: Date) -> Int {
        let start = now.addingTimeInterval(-activityWindow)
        return artifact.deliveries.count { ($0.deliveredAt ?? .distantPast) >= start }
    }

    /// `artifacts` in this order. They arrive in latest-delivery order, which breaks ties.
    public func sorted(_ artifacts: [Artifact], now: Date) -> [Artifact] {
        switch self {
        case .latest:
            return artifacts
        case .activity:
            let counts = artifacts.map { Self.recentDeliveries($0, now: now) }
            return artifacts.indices.sorted { counts[$0] != counts[$1] ? counts[$0] > counts[$1] : $0 < $1 }.map { artifacts[$0] }
        case .name:
            return artifacts.sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order != .orderedSame ? order == .orderedAscending : $0.path < $1.path
            }
        }
    }
}
