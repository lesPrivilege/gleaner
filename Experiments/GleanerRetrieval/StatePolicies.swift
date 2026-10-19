import Foundation
import GleanerCore

/// Competing development-only selection policies. Facts expose their own basis: a delivered,
/// reviewed, published or currently observed hash is never relabeled as another state.
public enum StatePolicies {
    public enum Intent: String, Codable, CaseIterable, Sendable {
        case currentWorking = "current_working"
        case currentOriginal = "current_original"
        case lastDelivered = "last_delivered"
        case lastReviewed = "last_reviewed"
        case lastPublished = "last_published"
    }

    public enum Policy: String, Codable, CaseIterable, Sendable {
        /// A deliberately naive control: choose the newest delivery regardless of the request.
        /// Its returned fact stays labeled last_delivered; this is not a product recommendation.
        case newestDeliveryControl = "newest_delivery_control"
        case explicitIntent = "explicit_intent"
        case discloseAllStates = "disclose_all_states"
    }

    public struct Fact: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable { case known, bytesUnknown = "bytes_unknown", unknown, absent }
        public var intent: Intent
        public var status: Status
        public var path: String?
        public var sha256: String?
        public var captureProvenance: String?
        public var deliveryID: String?
        public var deliveryEvidence: String?
        public var reviewID: Int64?
        /// A review is not necessarily approval; publication is not a verdict.
        public var reviewKind: String?
        public var reason: String?
    }

    public struct Result: Codable, Sendable {
        public var workID: String
        public var project: String
        public var requestedIntent: Intent
        public var policy: Policy
        public var selected: Fact?
        public var disclosures: [Fact]
        /// These are derived only by Review.standing, not by the experiment's selector.
        public var currentVerdictStanding: String
        public var currentPublicationStanding: String
    }

    public static func evaluate(work: Work, reviews: Reviews, present: Present? = nil, presentPath: String? = nil,
                                intent: Intent, policy: Policy) -> Result {
        let working = Fact(intent: .currentWorking, status: .unknown, reason: "No explicit working-state marker exists in the current core; latest, approved and published do not establish it.")
        let original: Fact
        // The caller must choose a work member's locator explicitly. A work's newest delivery
        // path is not evidence that this is where active work now happens.
        let scopedPresent = presentPath.flatMap { path in work.contains(path) ? present : nil }
        switch scopedPresent {
        case .read(let sha):
            original = Fact(intent: .currentOriginal, status: .known, path: presentPath, sha256: sha,
                            reason: "Observed current bytes at the explicitly selected locator; no working, delivered or accepted claim.")
        case .listed:
            original = Fact(intent: .currentOriginal, status: .bytesUnknown, path: presentPath,
                            reason: "Only metadata was observed; current bytes have not been verified.")
        case .absent:
            original = Fact(intent: .currentOriginal, status: .absent, path: presentPath,
                            reason: "No readable regular file is observed at the selected locator.")
        case nil:
            original = Fact(intent: .currentOriginal, status: .unknown,
                            reason: "Select a member locator and supply its observation; no current locator is inferred from delivery order.")
        }

        let delivered: Fact
        // Kept observations are useful work members, but were never assistant delivery events.
        if let delivery = work.deliveries.first(where: { $0.kept == nil }) {
            delivered = Fact(intent: .lastDelivered, status: delivery.sha256 == nil ? .bytesUnknown : .known,
                             path: delivery.path, sha256: delivery.sha256, captureProvenance: delivery.capture?.provenance.rawValue,
                             deliveryID: delivery.id, deliveryEvidence: delivery.member == nil ? "explicit_delivery" : "folder_member",
                             reason: "Recorded delivery and its observed capture; member evidence and capture provenance retain their separate meanings.")
        } else {
            delivered = Fact(intent: .lastDelivered, status: .unknown, reason: "This work has no explicit delivery event.")
        }
        func reviewFact(_ record: Review?, intent: Intent) -> Fact {
            guard let record else { return Fact(intent: intent, status: .unknown, reason: "No explicit record for this state.") }
            return Fact(intent: intent, status: .known, path: record.path, sha256: record.sha256,
                        reviewID: record.id, reviewKind: record.kind.rawValue,
                        reason: "Historical byte-bound record; current availability is a separate check.")
        }
        let reviewed = reviewFact(reviews.verdicts(of: work).first, intent: .lastReviewed)
        let published = reviewFact(reviews.published(of: work).first, intent: .lastPublished)
        let facts = [working, original, delivered, reviewed, published]
        let selected: Fact? = switch policy {
        case .newestDeliveryControl: delivered
        case .explicitIntent: facts.first { $0.intent == intent }
        case .discloseAllStates: nil
        }
        return Result(workID: work.id, project: work.project, requestedIntent: intent, policy: policy, selected: selected, disclosures: facts,
                      currentVerdictStanding: standing(reviews.verdicts(of: work), now: scopedPresent),
                      currentPublicationStanding: standing(reviews.published(of: work), now: scopedPresent))
    }

    private static func standing(_ records: [Review], now: Present?) -> String {
        guard let now else { return "unknown" }
        return switch Review.standing(records, now: now) {
        case .none: "none"
        case .current: "current"
        case .mayHaveChanged: "may_have_changed"
        case .changed: "changed"
        case .unavailable: "unavailable"
        }
    }
}
