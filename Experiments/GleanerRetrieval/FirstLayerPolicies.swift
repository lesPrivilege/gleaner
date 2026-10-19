import Foundation
import GleanerCore

/// Development-only presentation policies over Organization.search. This experiment never changes
/// matching, work identity or the order inside a tier. Every match remains explicitly reachable.
public enum FirstLayerPolicies {
    public enum Policy: String, Codable, CaseIterable, Sendable {
        case baseline
        case namedFocus = "named_focus"
        case nativeReplyGroups = "native_reply_groups"
    }

    public struct Candidate: Codable, Equatable, Sendable {
        public var workID: String
        public var project: String
        public var path: String
        public var deliveryID: String
        public var capturedSha: String?
        public var captureProvenance: String?
        public var namedMatch: Bool
    }

    public struct NativeReply: Codable, Equatable, Hashable, Sendable {
        public var project: String
        public var provider: String
        public var sessionID: String
        public var logPath: String
        public var replyLine: Int
    }

    public struct Group: Codable, Sendable {
        public enum Kind: String, Codable, Sendable { case work, reply }
        public var kind: Kind
        public var nativeReply: NativeReply?
        /// Multiple members require expansion/selection; none is promoted to representative truth.
        public var members: [Candidate]
    }

    public struct Result: Codable, Sendable {
        public var policy: Policy
        public var firstLayer: [Group]
        /// Matches outside the first layer, still in the shared search's order.
        public var deferred: [Candidate]
        public var allMatches: [Candidate]
        public var usedNamedFocus: Bool
        public var totalGroups: Int
    }

    public static func evaluate(organization: Organization, terms: [String], policy: Policy,
                                limit: Int = 5, project: String? = nil) throws -> Result {
        guard (1...1_000).contains(limit) else { throw Catalog.Failure.usage("Experimental layer limit must be between 1 and 1000.") }
        let tokens = Search.tokens(terms.joined(separator: " "))
        let matches = organization.search(tokens) { project == nil || $0.project == project }
        let candidates = matches.map { work, matched in
            // The same predicate Organization.search uses for its first tier. Reusing the public
            // core predicate avoids maintaining another lexical matcher or relevance score.
            let shared = ([organization.projectName(work.project)] + organization.unitNames(of: work)).joined(separator: " ")
            return Candidate(workID: work.id, project: work.project, path: matched.path,
                             deliveryID: matched.id, capturedSha: matched.sha256,
                             captureProvenance: matched.capture?.provenance.rawValue,
                             namedMatch: work.files.contains { $0.isNamed(by: tokens, project: shared) })
        }
        let focused = policy == .namedFocus && candidates.contains(where: \.namedMatch)
        var groups: [Group] = []
        var grouped: [NativeReply: Int] = [:]
        for (index, candidate) in candidates.enumerated() where !focused || candidate.namedMatch {
            let delivery = matches[index].matched
            if policy == .nativeReplyGroups, delivery.kept == nil, let line = delivery.replyLine,
               !delivery.sessionID.isEmpty, !delivery.logPath.isEmpty {
                let reply = NativeReply(project: candidate.project, provider: delivery.provider.rawValue,
                                        sessionID: delivery.sessionID, logPath: delivery.logPath, replyLine: line)
                if let group = grouped[reply] {
                    groups[group].members.append(candidate)
                } else {
                    grouped[reply] = groups.count
                    groups.append(Group(kind: .reply, nativeReply: reply, members: [candidate]))
                }
            } else {
                groups.append(Group(kind: .work, nativeReply: nil, members: [candidate]))
            }
        }
        let first = Array(groups.prefix(limit))
        let visible = Set(first.flatMap(\.members).map(\.workID))
        return Result(policy: policy, firstLayer: first, deferred: candidates.filter { !visible.contains($0.workID) },
                      allMatches: candidates, usedNamedFocus: focused, totalGroups: groups.count)
    }
}
