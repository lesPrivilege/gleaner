import Foundation
import Testing
@testable import GleanerCore
import GleanerRetrievalExperiments

/// Development tasks, authored separately from the independently sealed held-out cases.
/// Matching always executes Organization.search through the experimental presentation policy.
@Suite struct DevelopmentMeasurements {
    private struct Layer: Codable, Equatable {
        var policy: String
        var matchedObjects: Int
        var visibleGroups: Int
        var visibleObjects: Int
        var relevantVisibleObjects: Int
        var relevantObjects: Int
        var directlySelectableRelevantObjects: Int
        var deferredObjects: Int
        var expandedMemberPrecision: Double
        var expandedMemberRecall: Double
        var noMatchLost: Bool
    }
    private struct TaskResult: Codable {
        var task: String
        var query: [String]
        var label: String
        var layers: [Layer]
    }
    private struct Scale: Codable {
        var documents: Int
        var sessions: Int
        var inputBytes: Int
        var newlyRecordedObservations: Int
        var uniqueCapturedHashes: Int
        var workloadShape: String
        var indexSeconds: Double
        var organizationLoadSeconds: Double
        var queriesPerPolicy: Int
        var measurements: [Timing]
    }
    private struct Timing: Codable {
        var policy: String
        var query: [String]
        var matches: Int
        var p50Milliseconds: Double
        var p95Milliseconds: Double
        var maximumMilliseconds: Double
    }
    private struct Report: Codable {
        var schema = 1
        var basis = "Actual Indexer and Organization.search; experiment changes presentation only. No production behavior change."
        var measurementBoundary = "Query timing includes in-memory shared search and full experimental response construction, excludes process launch/index/DB load. Group member counts are fully expanded objects, not group-title precision."
        var tasks: [TaskResult]
        var metamorphicChecks: [String: Bool]
        var scale: Scale
    }

    private final class Fixture {
        let home: URL
        let project: URL
        let indexer: Indexer
        var inputBytes = 0
        var newlyRecordedObservations = 0
        let first = Date(timeIntervalSince1970: 1_930_000_000)

        init(projectName: String) throws {
            home = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-cycle2-dev-\(UUID().uuidString)")
            project = home.appendingPathComponent("Workspaces/\(projectName)")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/projects/synthetic"), withIntermediateDirectories: true)
            indexer = try Indexer(folders: LibraryFolders(home: home))
        }
        deinit { try? FileManager.default.removeItem(at: home) }

        func file(_ name: String, text: String = "Synthetic output\n") throws {
            let url = project.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            inputBytes += text.utf8.count
            try FileManager.default.setAttributes([.modificationDate: first.addingTimeInterval(-10)], ofItemAtPath: url.path)
        }

        func session(_ name: String, request: String, paths: [String], duplicate: Bool = false) throws {
            let stamp = first.formatted(.iso8601)
            let links = paths.map { "[Output](\($0))" }.joined(separator: ", ")
            let records: [[String: Any]] = [
                ["type": "user", "sessionId": name, "cwd": project.path, "timestamp": stamp,
                 "origin": ["kind": "human"], "message": ["role": "user", "content": request]],
                ["type": "assistant", "sessionId": name, "cwd": project.path, "timestamp": stamp,
                 "message": ["role": "assistant", "model": "synthetic", "content": [["type": "text", "text": duplicate ? links + ", " + links : links]]]],
            ]
            var bytes = Data()
            for record in records { bytes.append(try JSONSerialization.data(withJSONObject: record)); bytes.append(10) }
            inputBytes += bytes.count
            try bytes.write(to: home.appendingPathComponent(".claude/projects/synthetic/\(name).jsonl"))
        }

        func index() throws -> (Organization, Double, Double) {
            let before = DispatchTime.now().uptimeNanoseconds
            let report = try indexer.run(now: { self.first.addingTimeInterval(20) })
            newlyRecordedObservations = report.newObservations
            let indexed = DispatchTime.now().uptimeNanoseconds
            let organization = try Organization(shown: indexer.registry.artifacts(), registry: indexer.registry)
            let loaded = DispatchTime.now().uptimeNanoseconds
            return (organization, Double(indexed - before) / 1e9, Double(loaded - indexed) / 1e9)
        }
    }

    private func measure(_ organization: Organization, terms: [String], relevantNames: Set<String>) throws -> [Layer] {
        let baseline = organization.search(Search.tokens(terms.joined(separator: " "))).map { $0.work.id + "\n" + $0.matched.id }
        return try FirstLayerPolicies.Policy.allCases.map { policy in
            let result = try FirstLayerPolicies.evaluate(organization: organization, terms: terms, policy: policy)
            let visible = result.firstLayer.flatMap(\.members)
            func relevant(_ candidate: FirstLayerPolicies.Candidate) -> Bool {
                relevantNames.contains(URL(fileURLWithPath: candidate.path).lastPathComponent)
            }
            let count = visible.filter(relevant).count
            let all = result.allMatches.map { $0.workID + "\n" + $0.deliveryID }
            let reachable = (visible + result.deferred).map { $0.workID + "\n" + $0.deliveryID }
            return Layer(policy: policy.rawValue, matchedObjects: result.allMatches.count,
                         visibleGroups: result.firstLayer.count, visibleObjects: visible.count,
                         relevantVisibleObjects: count, relevantObjects: relevantNames.count,
                         directlySelectableRelevantObjects: result.firstLayer.filter { $0.members.count == 1 && relevant($0.members[0]) }.count,
                         deferredObjects: result.deferred.count,
                         expandedMemberPrecision: visible.isEmpty ? 0 : Double(count) / Double(visible.count),
                         expandedMemberRecall: Double(count) / Double(relevantNames.count),
                         noMatchLost: all == baseline && reachable.sorted() == baseline.sorted())
        }
    }

    private func identitySignature(_ organization: Organization, terms: [String], project: URL) throws -> [[String]] {
        var signatures: [[String]] = []
        for policy in FirstLayerPolicies.Policy.allCases {
            let result = try FirstLayerPolicies.evaluate(organization: organization, terms: terms, policy: policy)
            func identity(_ candidate: FirstLayerPolicies.Candidate) -> String {
                // Native delivery IDs change with relocated synthetic log paths; compare the
                // normalized selected member and named tier, retaining order and multiplicity.
                String(candidate.path.dropFirst(project.path.count)) + ":" + String(candidate.namedMatch)
            }
            var signature: [String] = []
            for group in result.firstLayer {
                signature.append("group:" + group.kind.rawValue)
                signature.append(contentsOf: group.members.map(identity))
            }
            signature.append("deferred")
            signature.append(contentsOf: result.deferred.map(identity))
            signature.append("all")
            signature.append(contentsOf: result.allMatches.map(identity))
            signatures.append(signature)
        }
        return signatures
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLEANER_CYCLE2_MEASURE"] == "1"))
    func developmentTasksAndScale() throws {
        let fixture = try Fixture(projectName: "LaunchWorkshop")
        let paths = ["outputs/release-spec.md"] + (0..<8).map { "construction/helper-\($0).txt" }
        for path in paths { try fixture.file(path) }
        try fixture.session("release", request: "Prepare the release package and verify the trajectory", paths: paths)
        let (organization, _, _) = try fixture.index()
        var tasks: [TaskResult] = []
        for (name, query, label) in [
            ("name_distinguishes_deliverable", ["release"], "Only release-spec.md is relevant; eight explicitly delivered helpers are useful secondary evidence."),
            ("project_context_names_every_object", ["LaunchWorkshop"], "Same wanted specification; project-name matching cannot identify its task role."),
            ("request_only_query", ["trajectory"], "Same wanted specification; relevance comes from the task label, not a lexical filename distinction."),
        ] {
            tasks.append(TaskResult(task: name, query: query, label: label,
                                    layers: try measure(organization, terms: query, relevantNames: ["release-spec.md"])))
        }

        let bundle = try Fixture(projectName: "FieldJournal")
        let bundlePaths = ["outputs/flow-map.svg", "outputs/observer-notes.md"] + (0..<8).map { "build/probe-\($0).txt" }
        for path in bundlePaths { try bundle.file(path) }
        try bundle.session("journey", request: "Provide the journey map and observer notes with supporting checks", paths: bundlePaths)
        let (bundleOrganization, _, _) = try bundle.index()
        tasks.append(TaskResult(task: "one_reply_is_not_one_relevant_object", query: ["journey"],
                                label: "Two wanted complementary outputs and eight construction files share one native reply. A compact group still requires member selection.",
                                layers: try measure(bundleOrganization, terms: ["journey"], relevantNames: ["flow-map.svg", "observer-notes.md"])))

        let transformed = try Fixture(projectName: "OrchardWorkshop")
        for path in paths.reversed() { try transformed.file(path) }
        try transformed.session("reordered", request: "Prepare the release package and verify the trajectory", paths: Array(paths.reversed()), duplicate: true)
        try transformed.file("unrelated/meeting.txt")
        try transformed.session("unrelated", request: "Record next month's meeting", paths: ["unrelated/meeting.txt"])
        let (changed, _, _) = try transformed.index()
        let stable = try identitySignature(changed, terms: ["release"], project: transformed.project)
            == identitySignature(organization, terms: ["release"], project: fixture.project)
        #expect(stable)
        #expect(tasks.allSatisfy { $0.layers.allSatisfy(\.noMatchLost) })

        let large = try Fixture(projectName: "Atlas")
        let count = 1_000
        for group in 0..<100 {
            let names = (0..<10).map { "reports/record-\(String(format: "%04d", group * 10 + $0)).md" }
            for name in names { try large.file(name, text: "# Synthetic observation \(name)\nA bounded portable scale fixture.\n") }
            try large.session("batch-\(group)", request: "Prepare the survey results for batch \(group)", paths: names)
        }
        let (largeOrganization, indexSeconds, loadSeconds) = try large.index()
        #expect(largeOrganization.works.count == count)
        let repeats = 30
        var timings: [Timing] = []
        for query in [["Atlas"], ["record-0500"]] {
            for policy in FirstLayerPolicies.Policy.allCases {
                _ = try FirstLayerPolicies.evaluate(organization: largeOrganization, terms: query, policy: policy)
                var values: [Double] = []
                var matches = 0
                for _ in 0..<repeats {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let result = try FirstLayerPolicies.evaluate(organization: largeOrganization, terms: query, policy: policy)
                    values.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                    matches = result.allMatches.count
                }
                values.sort()
                timings.append(Timing(policy: policy.rawValue, query: query, matches: matches,
                                      p50Milliseconds: values[repeats / 2], p95Milliseconds: values[Int(Double(repeats) * 0.95)], maximumMilliseconds: values.last!))
            }
        }
        let report = Report(tasks: tasks,
                            metamorphicChecks: ["combined_project_rename_reordered_mentions_duplicate_evidence_irrelevant_session": stable,
                                                "all_policies_preserve_shared_core_candidates": tasks.allSatisfy { $0.layers.allSatisfy(\.noMatchLost) }],
                            scale: Scale(documents: count, sessions: 100, inputBytes: large.inputBytes,
                                         newlyRecordedObservations: large.newlyRecordedObservations,
                                         uniqueCapturedHashes: Set(largeOrganization.works.flatMap(\.deliveries).compactMap(\.sha256)).count,
                                         workloadShape: "100 overlapping sessions in one workspace; 10 named outputs each. All documents have distinct content. This is a concurrent-work stress shape, not a typical-library estimate.",
                                         indexSeconds: indexSeconds, organizationLoadSeconds: loadSeconds,
                                         queriesPerPolicy: repeats, measurements: timings))
        if let output = ProcessInfo.processInfo.environment["GLEANER_CYCLE2_RESULTS_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: directory.appendingPathComponent("development-results.json"))
        }
    }
}
