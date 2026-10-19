import Foundation
import Testing
@testable import GleanerCore
import GleanerRetrievalExperiments

@Suite struct Cycle3SelectionTests {
    private let date = Date(timeIntervalSince1970: 1_940_000_000)

    private func file(_ name: String, project: String = "Harbor", session: String = "one", at: Int = 0,
                      request: String = "Prepare the plan", sha: String? = "captured") -> Artifact {
        let root = "/synthetic/\(project)", path = root + "/" + name
        let delivery = Delivery(id: path + "#\(at)", number: 1, path: path, deliveredAt: date.addingTimeInterval(Double(at)),
                                replyLine: 2, provider: .claudeCode, sessionID: session, request: request, cwd: root,
                                evidence: [], logPath: "/synthetic/logs/\(session).jsonl",
                                capture: Capture(sha256: sha, size: 4, modifiedAt: date, observedAt: date, savedAt: nil,
                                                 provenance: sha == nil ? .listed : .firstSeenAfterDelivery, kind: .file))
        return Artifact(path: path, deliveries: [delivery], repository: root)
    }

    private func review(_ id: Int64, _ artifact: Artifact, _ kind: Review.Kind, sha: String) -> Review {
        Review(id: id, kind: kind, path: artifact.path, sha256: sha,
               file: FileStat(size: 4, createdAt: nil, modifiedAt: date, inode: id), madeAt: date.addingTimeInterval(Double(id)))
    }

    @Test func baselineIsTheActualCoreOrderAndEachWorkRemainsReachableExactlyOnce() throws {
        let organization = Organization(artifacts: [file("report.md", session: "a", at: 3), file("scratch.txt", session: "a", at: 2), file("chart.svg", session: "b", at: 1)])
        let core = organization.search(["plan"])
        for policy in Cycle3Selection.Policy.allCases {
            let result = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: policy, limit: 2)
            #expect(result.rawCandidates.map(\.workID) == core.map { $0.work.id })
            #expect(result.rawCandidates.map(\.deliveryID) == core.map { $0.matched.id })
            #expect(result.eligibleCandidates == result.rawCandidates)
            let partition = result.selected + result.deferred + result.unmatched
            #expect(partition.count == core.count)
            #expect(Set(partition.map(\.workID)) == Set(core.map { $0.work.id }))
            #expect(result.operationCounts.sharedSearchCalls == 1)
        }
        let baseline = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: .baseline, limit: 2)
        #expect(baseline.selected == Array(baseline.rawCandidates.prefix(2)))
        #expect(throws: Catalog.Failure.self) {
            try Cycle3Selection.evaluate(organization: organization, terms: [], policy: .baseline, limit: 0)
        }
    }

    @Test func diversityTradesSimilarRequiredWorksForContextCoverageWithoutMergingThem() throws {
        let series = [file("episode-1.mov", session: "series", at: 10), file("episode-2.mov", session: "series", at: 9),
                      file("episode-3.mov", session: "series", at: 8)]
        let unrelated = [file("notes.md", session: "meeting", at: 7), file("chart.svg", session: "chart", at: 6)]
        let organization = Organization(artifacts: series + unrelated)
        let baseline = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: .baseline, limit: 3)
        let diverse = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: .diversified, limit: 3)
        #expect(baseline.selected.map(\.path) == series.map(\.path))
        #expect(diverse.selected.map(\.path) == [series[0].path, unrelated[0].path, unrelated[1].path])
        #expect(diverse.deferred.map(\.path) == [series[1].path, series[2].path])
        #expect(diverse.rawCandidates == baseline.rawCandidates)
        #expect(diverse.selected.allSatisfy { $0.representations.count == 1 })
        #expect(diverse.operationCounts.candidateComparisons > 0)
    }

    @Test func absentTaskIsAnExplicitOverviewAndAddedTermsUseTheSameCoreInEveryArm() throws {
        let organization = Organization(artifacts: [file("editable-deck.md", session: "a", at: 2), file("presentation-guide.md", session: "b", at: 1)])
        let overview = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: .taskConditioned)
        #expect(overview.mode == .scopeNeeded && overview.clarificationNeeded)
        #expect(overview.selected.isEmpty && overview.deferred == overview.rawCandidates)
        #expect(Set(overview.overview.flatMap(\.workIDs)) == Set(overview.rawCandidates.map(\.workID)))
        let task = Cycle3Selection.TaskScope(additionalTerms: ["editable"])
        let core = organization.search(["plan", "editable"])
        for policy in Cycle3Selection.Policy.allCases {
            let result = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: policy, task: task)
            #expect(result.mode == .results && !result.clarificationNeeded)
            #expect(result.eligibleCandidates.map(\.deliveryID) == core.map { $0.matched.id })
            #expect(result.selected.map(\.path) == ["/synthetic/Harbor/editable-deck.md"])
            #expect(result.unmatched.map(\.path) == ["/synthetic/Harbor/presentation-guide.md"])
            #expect(result.operationCounts.sharedSearchCalls == 2)
        }
        // The neutral arm can ask an unnecessary clarification even for a unique exact query.
        // This is recorded as an experiment tradeoff, not silently optimized after evaluation.
        let exact = try Cycle3Selection.evaluate(organization: organization, terms: ["editable-deck"], policy: .taskConditioned)
        #expect(exact.rawCandidates.count == 1 && exact.clarificationNeeded)
    }

    @Test func humanJoinedRepresentationsKeepOneWorkAndCoreChoosesTheRequestedFile() throws {
        let editable = file("editable-plan.md", session: "author", at: 1)
        let exported = file("plan.pdf", session: "export", at: 2)
        let separate = Organization(artifacts: [editable, exported])
        #expect(separate.works.count == 2)
        let joined = Organization(artifacts: [editable, exported], corrections: [
            Correction(id: 1, kind: .sameWork, subject: editable.path, target: exported.path, madeAt: date),
        ])
        #expect(joined.works.count == 1)
        let raw = joined.search(["plan"])
        let narrowed = joined.search(["plan", "editable"])
        for policy in Cycle3Selection.Policy.allCases {
            let result = try Cycle3Selection.evaluate(organization: joined, terms: ["plan"], policy: policy,
                                                    task: .init(additionalTerms: ["editable"]))
            let item = try #require(result.selected.first)
            #expect(result.selected.count == 1 && result.rawCandidates.count == 1)
            #expect(item.workID == raw[0].work.id && item.rawDeliveryID == raw[0].matched.id)
            #expect(item.deliveryID == narrowed[0].matched.id && item.path == editable.path)
            #expect(Set(item.representations.map(\.path)) == [editable.path, exported.path])
            #expect(item.captureProvenance == "first_seen_after_delivery")
        }
    }

    @Test func byteStateIsMatchedVersionEvidenceAndDoesNotSubstituteAnOlderApprovedRevision() throws {
        let original = file("report.md", at: 1, request: "Prepare the original plan", sha: "old")
        let revised = file("report.md", at: 2, request: "Prepare the revised plan", sha: "new")
        let work = Artifact(path: original.path, deliveries: [revised.latest, original.latest], repository: "/synthetic/Harbor")
        let organization = Organization(artifacts: [work])
        let records = Reviews([review(1, original, .approved, sha: "old"), review(2, revised, .changesRequested, sha: "new")])
        let approved = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: .baseline,
                                                  task: .init(byteState: .approved), reviews: records)
        #expect(approved.selected.isEmpty)
        #expect(approved.unmatched.first?.deliveryID == revised.latest.id)
        #expect(approved.unmatchedReasons[work.path] == "matched_capture_not_approved")
        let older = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: .baseline,
                                               task: .init(additionalTerms: ["original"], byteState: .approved), reviews: records)
        #expect(older.selected.first?.deliveryID == original.latest.id)
        #expect(older.selected.first?.stateEvidence?.verdictID == 1)
        let reviewed = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: .baseline,
                                                  task: .init(byteState: .reviewed), reviews: records)
        #expect(reviewed.selected.first?.stateEvidence?.verdictKind == "changes_requested")
    }

    @Test func latestSameHashVerdictPublicationAndUnknownCapturesRemainIndependent() throws {
        let known = file("report.md", sha: "same")
        let listed = file("listed.md", sha: nil)
        let other = file("report.md", project: "Other", sha: "same")
        let organization = Organization(artifacts: [known, listed, other])
        let records = Reviews([review(1, known, .approved, sha: "same"), review(2, known, .rejected, sha: "same"),
                               review(3, known, .published, sha: "same")])
        let approved = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: .baseline,
                                                  task: .init(byteState: .approved), reviews: records)
        #expect(approved.selected.isEmpty)
        #expect(approved.unmatchedReasons[listed.path] == "matched_capture_bytes_unknown")
        let published = try Cycle3Selection.evaluate(organization: organization, terms: ["plan"], policy: .baseline,
                                                   task: .init(byteState: .published), reviews: records)
        #expect(published.selected.map(\.path) == [known.path])
        #expect(published.selected.first?.stateEvidence?.verdictKind == "rejected")
        #expect(published.selected.first?.stateEvidence?.publicationID == 3)
        #expect(published.unmatched.contains { $0.workID == other.path })
    }
}
