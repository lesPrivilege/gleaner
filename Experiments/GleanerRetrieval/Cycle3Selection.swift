import Foundation
import GleanerCore

/// Isolated selection experiments. Organization.search owns matching and Work owns identity.
/// Context coverage is a presentation heuristic, never evidence of importance or acceptance.
public enum Cycle3Selection {
    public enum Policy: String, Codable, CaseIterable, Sendable {
        case baseline, diversified
        case taskConditioned = "task_conditioned"
    }

    public enum ByteState: String, Codable, Sendable {
        case any, reviewed, approved, published
    }

    public struct TaskScope: Codable, Sendable {
        public var additionalTerms: [String]
        public var projectKey: String?
        public var unitKey: String?
        /// State of the matched capture's bytes, not any historical state of the work.
        public var byteState: ByteState

        public init(additionalTerms: [String] = [], projectKey: String? = nil, unitKey: String? = nil, byteState: ByteState = .any) {
            self.additionalTerms = additionalTerms
            self.projectKey = projectKey
            self.unitKey = unitKey
            self.byteState = byteState
        }

        var isExplicit: Bool {
            !Search.tokens(additionalTerms.joined(separator: " ")).isEmpty || projectKey != nil || unitKey != nil || byteState != .any
        }
    }

    public struct Representation: Codable, Equatable, Sendable {
        public var path: String
        public var latestDeliveryID: String
        public var latestCapturedSha: String?
    }

    public struct StateEvidence: Codable, Equatable, Sendable {
        public var verdictID: Int64?
        public var verdictKind: String?
        public var publicationID: Int64?
    }

    public struct Candidate: Codable, Equatable, Sendable {
        public var workID: String
        /// The base query's match, retained when additional terms match a different revision.
        public var rawDeliveryID: String
        /// The shared core's matched representation/version; never an invented representative.
        public var deliveryID: String
        public var path: String
        public var sha256: String?
        public var captureProvenance: String?
        public var deliveryEvidence: String
        public var project: String
        public var unit: String?
        public var nativeReply: FirstLayerPolicies.NativeReply?
        /// Only the files already in this Work, including explicit human joins.
        public var representations: [Representation]
        public var stateEvidence: StateEvidence?
    }

    public struct Context: Codable, Equatable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable { case unit, reply, work }
        public var kind: Kind
        public var project: String
        public var unitKey: String?
        public var nativeReply: FirstLayerPolicies.NativeReply?
        public var workID: String?
    }

    public struct ContextSummary: Codable, Sendable {
        public var context: Context
        public var projectName: String
        public var unitName: String?
        public var workIDs: [String]
        public var count: Int
    }

    public struct OperationCounts: Codable, Sendable {
        public var sharedSearchCalls: Int
        /// Calls to Review.standing, not disk verification or model requests.
        public var byteStateChecks: Int
        /// Candidate priorities compared while filling the diversified first layer.
        public var candidateComparisons: Int
    }

    public struct Result: Codable, Sendable {
        public enum Mode: String, Codable, Sendable { case results; case scopeNeeded = "scope_needed" }
        public var policy: Policy
        public var mode: Mode
        public var rawCandidates: [Candidate]
        public var eligibleCandidates: [Candidate]
        public var selected: [Candidate]
        public var deferred: [Candidate]
        public var unmatched: [Candidate]
        public var unmatchedReasons: [String: String]
        public var overview: [ContextSummary]
        public var operationCounts: OperationCounts
        /// A requested clarification, not a count of executed user interactions.
        public var clarificationNeeded: Bool
    }

    public static func evaluate(organization: Organization, terms: [String], policy: Policy,
                                task: TaskScope? = nil, reviews: Reviews = Reviews([]), limit: Int = 5) throws -> Result {
        guard (1...1_000).contains(limit) else { throw Catalog.Failure.usage("Experimental selection limit must be between 1 and 1000.") }
        let tokens = Search.tokens(terms.joined(separator: " "))
        let raw = organization.search(tokens)
        let rawCandidates = raw.map { candidate($0.work, delivery: $0.matched, rawDeliveryID: $0.matched.id) }
        let rawByWork = Dictionary(uniqueKeysWithValues: rawCandidates.map { ($0.workID, $0) })
        let scope = task ?? TaskScope()
        let extra = Search.tokens(scope.additionalTerms.joined(separator: " "))
        let conditioned = extra.isEmpty ? raw : organization.search(tokens + extra)
        var operations = OperationCounts(sharedSearchCalls: extra.isEmpty ? 1 : 2, byteStateChecks: 0, candidateComparisons: 0)
        var reasons = Dictionary(uniqueKeysWithValues: rawCandidates.map { ($0.workID, "additional_terms_did_not_match") })
        var eligible: [Candidate] = []
        for (work, delivery) in conditioned {
            guard let original = rawByWork[work.id] else { continue }
            if let project = scope.projectKey, work.project != project {
                reasons[work.id] = "outside_requested_project"
                continue
            }
            if let unit = scope.unitKey, work.unit != unit {
                reasons[work.id] = "outside_requested_unit"
                continue
            }
            var item = candidate(work, delivery: delivery, rawDeliveryID: original.deliveryID)
            if scope.byteState != .any {
                guard let sha = delivery.sha256 else {
                    reasons[work.id] = "matched_capture_bytes_unknown"
                    continue
                }
                // Existing byte-bound state semantics: newest verdict on this hash, and a
                // publication mark on this hash. No scan for an older, differently matched version.
                let verdict: Review? = if case .current(let review) = Review.standing(reviews.verdicts(of: work), now: .read(sha)) { review } else { nil }
                let publication: Review? = if case .current(let review) = Review.standing(reviews.published(of: work), now: .read(sha)) { review } else { nil }
                operations.byteStateChecks += 2
                item.stateEvidence = StateEvidence(verdictID: verdict?.id, verdictKind: verdict?.kind.rawValue, publicationID: publication?.id)
                let accepted = switch scope.byteState {
                case .any: true
                case .reviewed: verdict != nil
                case .approved: verdict?.kind == .approved
                case .published: publication != nil
                }
                guard accepted else {
                    reasons[work.id] = "matched_capture_not_\(scope.byteState.rawValue)"
                    continue
                }
            }
            reasons[work.id] = nil
            eligible.append(item)
        }
        let unmatched = rawCandidates.filter { reasons[$0.workID] != nil }
        let needsScope = policy == .taskConditioned && !scope.isExplicit && !rawCandidates.isEmpty
        let selected: [Candidate]
        if needsScope {
            selected = []
        } else if policy == .diversified {
            selected = diversify(eligible, limit: limit, comparisons: &operations.candidateComparisons)
        } else {
            selected = Array(eligible.prefix(limit))
        }
        let selectedIDs = Set(selected.map(\.workID))
        return Result(policy: policy, mode: needsScope ? .scopeNeeded : .results,
                      rawCandidates: rawCandidates, eligibleCandidates: eligible, selected: selected,
                      deferred: eligible.filter { !selectedIDs.contains($0.workID) }, unmatched: unmatched,
                      unmatchedReasons: reasons, overview: needsScope ? overview(rawCandidates, organization: organization) : [],
                      operationCounts: operations, clarificationNeeded: needsScope)
    }

    private static func candidate(_ work: Work, delivery: Delivery, rawDeliveryID: String) -> Candidate {
        let native: FirstLayerPolicies.NativeReply?
        if delivery.kept == nil, let line = delivery.replyLine, !delivery.sessionID.isEmpty, !delivery.logPath.isEmpty {
            native = FirstLayerPolicies.NativeReply(project: work.project, provider: delivery.provider.rawValue,
                                                   sessionID: delivery.sessionID, logPath: delivery.logPath, replyLine: line)
        } else {
            native = nil
        }
        return Candidate(workID: work.id, rawDeliveryID: rawDeliveryID, deliveryID: delivery.id, path: delivery.path,
                         sha256: delivery.sha256, captureProvenance: delivery.capture?.provenance.rawValue,
                         deliveryEvidence: delivery.kept != nil ? "kept_observation" : delivery.member != nil ? "folder_member" : "explicit_delivery",
                         project: work.project, unit: work.unit, nativeReply: native,
                         representations: work.files.map { Representation(path: $0.path, latestDeliveryID: $0.latest.id, latestCapturedSha: $0.latest.sha256) })
    }

    private static func context(_ item: Candidate) -> Context {
        if let unit = item.unit { return Context(kind: .unit, project: item.project, unitKey: unit) }
        if let reply = item.nativeReply { return Context(kind: .reply, project: item.project, nativeReply: reply) }
        return Context(kind: .work, project: item.project, workID: item.workID)
    }

    private static func overview(_ items: [Candidate], organization: Organization) -> [ContextSummary] {
        var summaries: [ContextSummary] = [], positions: [Context: Int] = [:]
        for item in items {
            let key = context(item)
            if let index = positions[key] {
                summaries[index].workIDs.append(item.workID)
                summaries[index].count += 1
            } else {
                positions[key] = summaries.count
                summaries.append(ContextSummary(context: key, projectName: organization.projectName(item.project),
                                                unitName: item.unit.map(organization.unitName), workIDs: [item.workID], count: 1))
            }
        }
        return summaries
    }

    /// Prefer less represented existing projects, then less represented existing contexts, then
    /// the shared core's original rank. This intentionally trades relevance rank for coverage;
    /// a similar required series can be deferred. No context is asserted equally useful.
    private static func diversify(_ items: [Candidate], limit: Int, comparisons: inout Int) -> [Candidate] {
        let contexts = items.map(context)
        var used: Set<Int> = [], projects: [String: Int] = [:], counts: [Context: Int] = [:], chosen: [Candidate] = []
        for _ in 0..<Swift.min(limit, items.count) {
            var best: Int?
            for index in items.indices where !used.contains(index) {
                comparisons += 1
                guard let previous = best else { best = index; continue }
                let priority = (projects[items[index].project, default: 0], counts[contexts[index], default: 0])
                let current = (projects[items[previous].project, default: 0], counts[contexts[previous], default: 0])
                if priority < current { best = index }
            }
            guard let best else { break }
            used.insert(best)
            chosen.append(items[best])
            projects[items[best].project, default: 0] += 1
            counts[contexts[best], default: 0] += 1
        }
        return chosen
    }
}
