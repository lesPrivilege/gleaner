import Foundation
import Testing
@testable import GleanerCore
import GleanerRetrievalExperiments

@Suite struct RetrievalPolicyTests {
    let time = Date(timeIntervalSince1970: 1_900_000_000)

    func artifact(_ name: String, request: String = "Write the report", reply: Int? = 2,
                  session: String = "synthetic-session", hash: String = "captured") -> Artifact {
        let path = "/synthetic/Harbor/\(name)"
        let delivery = Delivery(id: path + "#1", number: 1, path: path, deliveredAt: time, replyLine: reply,
                                provider: .claudeCode, sessionID: session, request: request, cwd: "/synthetic/Harbor",
                                evidence: [], logPath: "/synthetic/log.jsonl",
                                capture: Capture(sha256: hash, size: 3, modifiedAt: time, observedAt: time,
                                                 savedAt: nil, provenance: .atDelivery, kind: .file))
        return Artifact(path: path, deliveries: [delivery])
    }

    @Test func firstLayerPoliciesPreserveEverySharedCoreMatchAndExposeSelectionTradeoff() throws {
        let organization = Organization(artifacts: [artifact("report.md"), artifact("appendix.md"), artifact("render.py")])
        let expected = organization.search(["report"]).map { $0.matched.id }
        for policy in FirstLayerPolicies.Policy.allCases {
            let result = try FirstLayerPolicies.evaluate(organization: organization, terms: ["report"], policy: policy, limit: 2)
            #expect(result.allMatches.map(\.deliveryID) == expected)
            let reachable = result.firstLayer.flatMap(\.members) + result.deferred
            #expect(Set(reachable.map(\.deliveryID)) == Set(expected))
            #expect(reachable.count == expected.count)
        }
        let focused = try FirstLayerPolicies.evaluate(organization: organization, terms: ["report"], policy: .namedFocus)
        #expect(focused.usedNamedFocus && focused.firstLayer.flatMap(\.members).map(\.path) == ["/synthetic/Harbor/report.md"])
        // A task wanting the supporting appendix now needs a broadening step. Fewer cards do not
        // establish greater wanted-object recall or lower task effort for every task.
        #expect(focused.deferred.contains { $0.path.hasSuffix("appendix.md") })
        let groups = try FirstLayerPolicies.evaluate(organization: organization, terms: ["report"], policy: .nativeReplyGroups)
        #expect(groups.firstLayer.count == 1 && groups.firstLayer[0].members.count == 3)
        #expect(groups.firstLayer[0].kind == .reply)
    }

    @Test func intermediateNamesStayDiscoverableAndContextOnlyQueriesDoNotCollapseToNothing() throws {
        let organization = Organization(artifacts: [artifact("scratch-analysis.md", request: "Evaluate crosswinds"), artifact("final.pdf", request: "Evaluate crosswinds")])
        let intermediate = try FirstLayerPolicies.evaluate(organization: organization, terms: ["scratch"], policy: .namedFocus)
        #expect(intermediate.firstLayer.flatMap(\.members).map(\.path) == ["/synthetic/Harbor/scratch-analysis.md"])
        let context = try FirstLayerPolicies.evaluate(organization: organization, terms: ["crosswinds"], policy: .namedFocus)
        #expect(!context.usedNamedFocus && context.firstLayer.count == 2 && context.deferred.isEmpty)
    }

    @Test func nativeGroupingDoesNotEquateConcurrentSessionsUnknownAnchorsOrProjects() throws {
        let a = artifact("a.md", session: "one"), b = artifact("b.md", session: "two")
        let c = artifact("c.md", reply: nil), d = artifact("d.md", reply: nil)
        let organization = Organization(artifacts: [a, b, c, d])
        let groups = try FirstLayerPolicies.evaluate(organization: organization, terms: ["report"], policy: .nativeReplyGroups)
        #expect(groups.firstLayer.count == 4)
        #expect(groups.firstLayer.allSatisfy { $0.members.count == 1 })
        #expect(groups.firstLayer.filter { $0.kind == .work }.count == 2)
    }

    @Test func requestedStatesStaySeparateAndNewerBytesInheritNoReviewAuthority() throws {
        let file = artifact("report.md", hash: "delivered-v2")
        let work = try #require(Organization(artifacts: [file]).works.first)
        let metadata = FileStat(size: 3, createdAt: nil, modifiedAt: time, inode: 1)
        let records = Reviews([
            Review(id: 1, kind: .approved, path: file.path, sha256: "published-v0", file: metadata, madeAt: time.addingTimeInterval(-30)),
            Review(id: 2, kind: .published, path: file.path, sha256: "published-v0", file: metadata, madeAt: time.addingTimeInterval(-20)),
            Review(id: 3, kind: .changesRequested, path: file.path, sha256: "reviewed-v1", file: metadata, madeAt: time.addingTimeInterval(-10)),
        ])
        func choice(_ intent: StatePolicies.Intent, _ policy: StatePolicies.Policy = .explicitIntent) -> StatePolicies.Result {
            StatePolicies.evaluate(work: work, reviews: records, present: .read("current-v3"), presentPath: file.path, intent: intent, policy: policy)
        }
        #expect(choice(.currentWorking).selected?.status == .unknown)
        #expect(choice(.currentOriginal).selected?.sha256 == "current-v3")
        #expect(choice(.lastDelivered).selected?.sha256 == "delivered-v2")
        #expect(choice(.lastReviewed).selected?.sha256 == "reviewed-v1")
        #expect(choice(.lastReviewed).selected?.reviewKind == "changes_requested")
        #expect(choice(.lastPublished).selected?.sha256 == "published-v0")
        #expect(choice(.currentOriginal).currentVerdictStanding == "changed")
        #expect(choice(.currentOriginal).currentPublicationStanding == "changed")
        let naive = choice(.currentWorking, .newestDeliveryControl)
        #expect(naive.selected?.intent == .lastDelivered && naive.selected?.sha256 == "delivered-v2")
        let disclose = choice(.currentWorking, .discloseAllStates)
        #expect(disclose.selected == nil && disclose.disclosures.count == 5)
    }

    @Test func currentOriginalNeedsExplicitScopedLocatorAndDoesNotTreatMetadataAsBytes() throws {
        let work = try #require(Organization(artifacts: [artifact("report.md")]).works.first)
        let metadata = FileStat(size: 3, createdAt: nil, modifiedAt: time, inode: 1)
        let unknown = StatePolicies.evaluate(work: work, reviews: Reviews([]), present: .read("hash"),
                                            intent: .currentOriginal, policy: .explicitIntent)
        #expect(unknown.selected?.status == .unknown && unknown.selected?.sha256 == nil)
        let outside = StatePolicies.evaluate(work: work, reviews: Reviews([]), present: .read("hash"), presentPath: "/synthetic/Other/report.md",
                                            intent: .currentOriginal, policy: .explicitIntent)
        #expect(outside.selected?.status == .unknown)
        let listed = StatePolicies.evaluate(work: work, reviews: Reviews([]), present: .listed(metadata), presentPath: work.id,
                                           intent: .currentOriginal, policy: .explicitIntent)
        #expect(listed.selected?.status == .bytesUnknown && listed.selected?.sha256 == nil)
    }

    @Test func lastDeliveryRetainsFolderMembershipAndLaterCaptureProvenance() throws {
        let file = artifact("listed.md")
        var delivery = file.latest
        delivery.member = Membership(folderDelivery: "folder-delivery", folder: "/synthetic/Harbor")
        delivery.capture?.provenance = .firstSeenAfterDelivery
        let work = try #require(Organization(artifacts: [Artifact(path: file.path, deliveries: [delivery])]).works.first)
        let result = StatePolicies.evaluate(work: work, reviews: Reviews([]), intent: .lastDelivered, policy: .explicitIntent)
        #expect(result.selected?.deliveryEvidence == "folder_member")
        #expect(result.selected?.captureProvenance == "first_seen_after_delivery")
        #expect(result.selected?.sha256 == "captured")
    }
}
