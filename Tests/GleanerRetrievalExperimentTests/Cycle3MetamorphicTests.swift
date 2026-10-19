import Foundation
import Testing
@testable import GleanerCore
import GleanerRetrievalExperiments

/// Constructed native records test selection invariance. Actual provider/index/rebuild behavior
/// is exercised separately by the independent corpus and correction fixtures.
@Suite struct Cycle3MetamorphicTests {
    private func corpus(root: String, textExtension: String = "md", duplicatedEvidence: Bool = false) -> [Artifact] {
        let when = Date(timeIntervalSince1970: 1_940_000_000)
        return (0..<8).map { index in
            let path = "\(root)/notes/marsh-\(index).\(textExtension)"
            let session = "field-\(index / 3)"
            let evidence = Evidence(line: 2, syntax: "link", rawTarget: path, anchor: nil, excerpt: "Marsh permit evidence \(index)")
            let delivery = Delivery(id: "\(path)#delivery", number: 1, path: path, deliveredAt: when,
                                    replyLine: 2, provider: .claudeCode, sessionID: session,
                                    request: "Prepare marsh permit notes", cwd: root,
                                    evidence: duplicatedEvidence ? [evidence, evidence] : [evidence],
                                    logPath: "\(root)/logs/\(session).jsonl",
                                    capture: Capture(sha256: "synthetic-byte-identity-\(index)", size: 32,
                                                     modifiedAt: when, observedAt: when, savedAt: nil,
                                                     provenance: .atDelivery, kind: .file))
            return Artifact(path: path, deliveries: [delivery])
        }
    }

    private func signature(_ result: Cycle3Selection.Result, root: String, textExtension: String = "md") -> [String] {
        func normalized(_ string: String) -> String {
            string.replacingOccurrences(of: root, with: "$PROJECT")
                .replacingOccurrences(of: ".\(textExtension)", with: ".text")
        }
        func append(_ candidates: [Cycle3Selection.Candidate], to output: inout [String]) {
            for candidate in candidates {
                output.append(normalized(candidate.workID))
                output.append(normalized(candidate.deliveryID))
                output.append(candidate.captureProvenance ?? "unknown")
                output.append(candidate.deliveryEvidence)
                output.append(normalized(candidate.project))
                output.append(normalized(candidate.nativeReply?.logPath ?? "none"))
                output.append(contentsOf: candidate.representations.map { normalized($0.path) })
            }
        }
        var output = [result.mode.rawValue, String(result.clarificationNeeded)]
        output.append("raw"); append(result.rawCandidates, to: &output)
        output.append("eligible"); append(result.eligibleCandidates, to: &output)
        output.append("selected"); append(result.selected, to: &output)
        output.append("deferred"); append(result.deferred, to: &output)
        output.append("unmatched"); append(result.unmatched, to: &output)
        for context in result.overview {
            output.append("context:" + context.context.kind.rawValue)
            output.append(contentsOf: context.workIDs.map(normalized))
        }
        return output
    }

    @Test func relocatingProjectReversingImportsAndDuplicatingEvidencePreserveSelections() throws {
        let firstRoot = "/synthetic/Willow", secondRoot = "/synthetic/Cypress"
        let first = Organization(artifacts: corpus(root: firstRoot))
        var changed = Array(corpus(root: secondRoot, duplicatedEvidence: true).reversed())
        let unrelatedPath = secondRoot + "/other/meeting.txt"
        let unrelated = Delivery(id: "unrelated", number: 1, path: unrelatedPath,
                                 deliveredAt: Date(timeIntervalSince1970: 1_950_000_000), provider: .codex,
                                 request: "Schedule a winter meeting", cwd: secondRoot, evidence: [],
                                 logPath: secondRoot + "/logs/meeting.jsonl", capture: nil)
        changed.append(Artifact(path: unrelatedPath, deliveries: [unrelated]))
        let second = Organization(artifacts: changed)
        for policy in Cycle3Selection.Policy.allCases {
            for task in [nil, Cycle3Selection.TaskScope(additionalTerms: ["notes"])] {
                let a = try Cycle3Selection.evaluate(organization: first, terms: ["marsh"], policy: policy, task: task, limit: 4)
                let b = try Cycle3Selection.evaluate(organization: second, terms: ["marsh"], policy: policy, task: task, limit: 4)
                #expect(signature(a, root: firstRoot) == signature(b, root: secondRoot))
                let direct = first.search(Search.tokens("marsh")).map { $0.work.id }
                #expect(a.rawCandidates.map(\.workID) == direct)
                let reachable = a.selected + a.deferred + a.unmatched
                #expect(reachable.map(\.workID).sorted() == direct.sorted())
            }
        }
    }

    @Test func plainTextExtensionVariationDoesNotChangeTaskNeutralSelection() throws {
        // Both fixtures represent ordinary text notes. This makes no invariant claim for
        // changing a native editable format into a rendered representation.
        let root = "/synthetic/Estuary"
        let markdown = Organization(artifacts: corpus(root: root, textExtension: "md"))
        let plain = Organization(artifacts: corpus(root: root, textExtension: "txt"))
        for policy in Cycle3Selection.Policy.allCases {
            let a = try Cycle3Selection.evaluate(organization: markdown, terms: ["marsh"], policy: policy, limit: 4)
            let b = try Cycle3Selection.evaluate(organization: plain, terms: ["marsh"], policy: policy, limit: 4)
            #expect(signature(a, root: root, textExtension: "md") == signature(b, root: root, textExtension: "txt"))
        }
    }
}
