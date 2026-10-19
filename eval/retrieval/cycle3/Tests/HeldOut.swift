import Foundation
import Testing
@testable import GleanerCore
@testable import GleanerRetrievalExperiments

/// This evaluator scores real shared-core results. Labels were sealed before policy inspection.
/// Candidate generation, matching, ranking and state filtering remain in the shared experiment.
@Suite struct Cycle3HeldOutTests {
    private static let labelsSHA256 = "c8848fcd422cf114e20211daa5cf95797075714b79636ad2c60fcec5377b9d38"
    private static let sourceFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func encoded<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: Catalog.encoder.encode(value))
    }

    private func sanitized(_ value: Any, home: String) -> Any {
        if let value = value as? String {
            return value.replacingOccurrences(of: home, with: "$SYNTHETIC_HOME")
                .replacingOccurrences(of: Paths.standard(home), with: "$SYNTHETIC_HOME")
        }
        if let value = value as? [Any] { return value.map { sanitized($0, home: home) } }
        if let value = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: value.map { key, item in
                (sanitized(key, home: home) as! String, sanitized(item, home: home))
            })
        }
        return value
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Any {
        denominator == 0 ? NSNull() : Double(numerator) / Double(denominator)
    }

    private func rowArrays(_ response: [String: Any], _ key: String) throws -> [[String: Any]] {
        try #require(response[key] as? [[String: Any]])
    }

    /// Ground-truth-assisted shortest scripted navigation, common to every arm. It is an effort
    /// lower bound, not a measured person or a product interface. All byte opens actually occur.
    private func navigation(catalog: Catalog, response: [String: Any], wanted: Set<String>,
                            expectedText: [String: String]) throws -> [String: Any] {
        let selected = try rowArrays(response, "selected")
        let deferred = try rowArrays(response, "deferred")
        let unmatched = try rowArrays(response, "unmatched")
        var opens = 0, verified = 0, representationChoices = 0, returnedBytes = 0, remainder = false, outsideTask = false
        var trace: [[String: Any]] = []
        for path in wanted.sorted() {
            var found: (candidate: [String: Any], layer: String, reference: String, representation: Bool)?
            for (layer, candidates) in [("selected", selected), ("deferred", deferred), ("unmatched", unmatched)] {
                for candidate in candidates {
                    if candidate["path"] as? String == path, let id = candidate["delivery_id"] as? String {
                        found = (candidate, layer, id, false)
                        break
                    }
                    let representations = candidate["representations"] as? [[String: Any]] ?? []
                    if let representation = representations.first(where: { $0["path"] as? String == path }),
                       let id = representation["latest_delivery_id"] as? String {
                        found = (candidate, layer, id, true)
                        break
                    }
                }
                if found != nil { break }
            }
            guard let found else {
                trace.append(["path": path, "state": "unreachable"])
                continue
            }
            remainder = remainder || found.layer == "deferred"
            outsideTask = outsideTask || found.layer == "unmatched"
            representationChoices += found.representation ? 1 : 0
            opens += 1
            let text = try catalog.read(found.reference, max: 4 << 10)
            returnedBytes += text.text.utf8.count
            let correct = text.text == expectedText[path]
            verified += correct ? 1 : 0
            trace.append(["path": path, "layer": found.layer, "representation_choice": found.representation,
                          "delivery_id": found.reference, "bytes_correct": correct])
        }
        return ["label_assisted_lower_bound_only": true, "artifact_reads_executed": opens, "content_bytes_returned": returnedBytes,
                "verified_reads": verified, "all_wanted_bytes_obtained": verified == wanted.count,
                "remainder_expansions": remainder ? 1 : 0,
                "outside_declared_task_expansions": outsideTask ? 1 : 0,
                "representation_choices": representationChoices,
                "trace": trace]
    }

    private func evaluate(_ task: [String: Any], fixture: Cycle3Corpus, organization: Organization) throws -> [[String: Any]] {
        let query = try #require(task["query"] as? String)
        let wanted = Set(try #require(task["useful_paths"] as? [String]).map(fixture.path))
        let wantedWorks = Set(wanted.compactMap { organization.work(containing: $0)?.id })
        #expect(!wantedWorks.isEmpty)
        let limit = try #require(task["limit"] as? Int)
        let scopeLabel = task["scope"] as? [String: Any]
        let scope: Cycle3Selection.TaskScope? = try scopeLabel.map {
            Cycle3Selection.TaskScope(additionalTerms: $0["additional_terms"] as? [String] ?? [],
                byteState: try #require(Cycle3Selection.ByteState(rawValue: $0["byte_state"] as? String ?? "any")))
        }
        let reviews = Reviews(try fixture.indexer.registry.reviews())
        let catalog = Catalog(registry: fixture.indexer.registry, store: fixture.indexer.store)
        var rows: [[String: Any]] = []
        for policy in Cycle3Selection.Policy.allCases {
            let start = Date()
            let result = try Cycle3Selection.evaluate(organization: organization, terms: Search.tokens(query),
                policy: policy, task: scope, reviews: reviews, limit: limit)
            let elapsed = Date().timeIntervalSince(start) * 1_000
            let response = try #require(try encoded(result) as? [String: Any])
            let raw = try rowArrays(response, "raw_candidates")
            let eligible = try rowArrays(response, "eligible_candidates")
            let selected = try rowArrays(response, "selected")
            let deferred = try rowArrays(response, "deferred")
            let unmatched = try rowArrays(response, "unmatched")
            func ids(_ candidates: [[String: Any]]) -> Set<String> { Set(candidates.compactMap { $0["work_id"] as? String }) }
            func paths(_ candidates: [[String: Any]]) -> Set<String> { Set(candidates.compactMap { $0["path"] as? String }) }
            let rawIDs = ids(raw), selectedIDs = ids(selected), eligibleIDs = ids(eligible)
            let partition = selected + deferred + unmatched
            let partitionIDs = ids(partition)
            let rawRepresentations = Set(raw.flatMap { ($0["representations"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String } })
            let relevantSelected = paths(selected).intersection(wanted).count
            let selectedPaths = paths(selected)
            let scopeNeeded = response["mode"] as? String == "scope_needed"
            let allRequired = task["relevance_mode"] as? String == "required_set"
            let navigation = try navigation(catalog: catalog, response: response, wanted: wanted, expectedText: fixture.expectedText)
            let row: [String: Any] = [
                "case": task["id"]!, "policy": policy.rawValue, "query": query,
                "relevance_mode": task["relevance_mode"]!, "single_correct_object_assumed": false,
                "raw_works": raw.count, "raw_representations": rawRepresentations.count,
                "eligible_works": eligible.count, "selected_works": selected.count,
                "deferred_works": deferred.count, "unmatched_works": unmatched.count,
                "raw_work_recall": ratio(rawIDs.intersection(wantedWorks).count, wantedWorks.count),
                "raw_representation_reachability": ratio(rawRepresentations.intersection(wanted).count, wanted.count),
                "eligible_work_recall": ratio(eligibleIDs.intersection(wantedWorks).count, wantedWorks.count),
                "first_layer_work_coverage": ratio(selectedIDs.intersection(wantedWorks).count, wantedWorks.count),
                "first_layer_representation_precision": ratio(relevantSelected, selected.count),
                "first_layer_representation_coverage": ratio(relevantSelected, wanted.count),
                "first_layer_unwanted_representations": selected.count - relevantSelected,
                "all_required_representations_selected": allRequired ? wanted.isSubset(of: selectedPaths) as Any : NSNull(),
                "admissible_first_choice_exists": !selectedPaths.isDisjoint(with: wanted),
                "raw_partition_preserved": partitionIDs == rawIDs && partition.count == rawIDs.count,
                "work_identity_preserved": rawIDs.isSubset(of: Set(organization.works.map(\.id))),
                "scope_needed": scopeNeeded,
                "supplied_clarification_turns": task["clarification_turns"]!,
                "additional_clarification_requested": scopeNeeded ? 1 : 0,
                "scripted_query_requests": 1,
                "navigation": navigation, "latency_ms": elapsed,
                "serialized_response_bytes": try Catalog.encoder.encode(result).count, "response": response
            ]
            #expect(partitionIDs == rawIDs && partition.count == rawIDs.count)
            #expect(navigation["all_wanted_bytes_obtained"] as? Bool == true)
            rows.append(row)
        }
        return rows
    }

    /// These comparators execute actual bounded operations over the same corpus. Their prior
    /// knowledge is stronger than a broad query and is recorded instead of hidden in an oracle.
    private func comparators(_ task: [String: Any], fixture: Cycle3Corpus, organization: Organization) throws -> [[String: Any]] {
        let wanted = Set(try #require(task["useful_paths"] as? [String]).map(fixture.path))
        let catalog = Catalog(registry: fixture.indexer.registry, store: fixture.indexer.store)
        let queries = try #require(task["known_direct_queries"] as? [String])
        let baseQuery = try #require(task["query"] as? String)
        let baseLimit = try #require(task["limit"] as? Int)
        let coreStart = Date()
        let coreMatches = organization.search(Search.tokens(baseQuery))
        let coreFirst = Array(coreMatches.prefix(baseLimit))
        let corePaths = Set(coreFirst.map { $0.matched.path })
        let coreWantedWorks = Set(wanted.compactMap { organization.work(containing: $0)?.id })
        let coreSelectedWorks = Set(coreFirst.map { $0.work.id })
        let unconditioned: [String: Any] = [
            "case": task["id"]!, "comparator": "unconditioned_shared_core",
            "assumption": "Original base query only, with no experimental task/state constraints. Calls Organization.search directly.",
            "query_requests": 1, "artifact_reads_executed": 0,
            "raw_work_ids": coreMatches.map { $0.work.id }, "selected_paths": coreFirst.map { $0.matched.path },
            "first_layer_representation_precision": ratio(corePaths.intersection(wanted).count, coreFirst.count),
            "first_layer_representation_coverage": ratio(corePaths.intersection(wanted).count, wanted.count),
            "first_layer_work_coverage": ratio(coreSelectedWorks.intersection(coreWantedWorks).count, coreWantedWorks.count),
            "latency_ms": Date().timeIntervalSince(coreStart) * 1_000
        ]
        var directFound: Set<String> = [], directOpened: Set<String> = [], directCorrect: Set<String> = []
        var directReads = 0, directBytes = 0
        var directTrace: [[String: Any]] = []
        let directStart = Date()
        for query in queries {
            let results = organization.search(Search.tokens(query))
            directFound.formUnion(results.map { $0.matched.path })
            // A competent known-name query opens its top match, not every library file.
            if let first = results.first {
                directOpened.insert(first.matched.path)
                let text = try catalog.read(first.matched.id, max: 4 << 10)
                directReads += 1
                directBytes += text.text.utf8.count
                if text.text == fixture.expectedText[first.matched.path] { directCorrect.insert(first.matched.path) }
            }
            directTrace.append(["query": query, "result_paths": results.map { $0.matched.path },
                                "opened_path": results.first?.matched.path as Any? ?? NSNull()])
        }
        let direct: [String: Any] = [
            "case": task["id"]!, "comparator": "known_basename_shared_query",
            "assumption": "User already knows a discriminative basename for each desired representation; this knowledge is not charged as a retrieval step.",
            "query_requests": queries.count, "directory_listings": 0, "artifact_reads_executed": directReads,
            "content_bytes_returned": directBytes,
            "candidate_paths": directFound.sorted(), "candidate_precision": ratio(directFound.intersection(wanted).count, directFound.count),
            "representation_recall": ratio(directFound.intersection(wanted).count, wanted.count),
            "all_wanted_bytes_obtained": wanted.isSubset(of: directCorrect),
            "opened_paths": directOpened.sorted(), "latency_ms": Date().timeIntervalSince(directStart) * 1_000,
            "trace": directTrace
        ]
        let directories = try #require(task["known_directories"] as? [String])
        var listed: Set<String> = [], opened: Set<String> = [], correct: Set<String> = [], entries = 0, directoryBytes = 0
        let directoryStart = Date()
        for relative in directories {
            let folder = fixture.project.appendingPathComponent(relative)
            let contained = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [])
            #expect(contained.count <= 32)
            entries += contained.count
            for file in contained where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let path = Paths.standard(file.path)
                listed.insert(path)
                // Same label-assisted selection lower bound as policy navigation, explicitly not
                // a measured human name-recognition score. Reads are bounded and actually run.
                if wanted.contains(path) {
                    let handle = try FileHandle(forReadingFrom: file)
                    defer { try? handle.close() }
                    let bytes = try handle.read(upToCount: 4 << 10) ?? Data()
                    directoryBytes += bytes.count
                    opened.insert(path)
                    if String(data: bytes, encoding: .utf8) == fixture.expectedText[path] { correct.insert(path) }
                }
            }
        }
        let directory: [String: Any] = [
            "case": task["id"]!, "comparator": "known_immediate_directory",
            "assumption": "User knows each authorized immediate parent folder. Selection among names is label-assisted, as in policy navigation; no recursive scan, filesystem search or Finder interaction occurs.",
            "query_requests": 0, "directory_listings": directories.count, "entries_inspected": entries,
            "artifact_reads_executed": opened.count, "label_assisted_lower_bound_only": true,
            "content_bytes_returned": directoryBytes,
            "candidate_paths": listed.sorted(), "candidate_precision": ratio(listed.intersection(wanted).count, listed.count),
            "representation_recall": ratio(listed.intersection(wanted).count, wanted.count),
            "all_wanted_bytes_obtained": wanted.isSubset(of: correct),
            "opened_paths": opened.sorted(), "latency_ms": Date().timeIntervalSince(directoryStart) * 1_000
        ]
        return [unconditioned, direct, directory]
    }

    @Test func evaluateSealedTasks() throws {
        let labelsURL = Self.sourceFolder.appendingPathComponent("heldout-labels.json")
        #expect(Locator.sha256(labelsURL.path) == Self.labelsSHA256)
        let labels = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: labelsURL)) as? [String: Any])
        var policyRows: [[String: Any]] = [], comparatorRows: [[String: Any]] = [], correctionRows: [[String: Any]] = []
        for corpus in try #require(labels["corpora"] as? [[String: Any]]) {
            let fixture = try Cycle3Corpus(label: corpus)
            let organization = try fixture.organization()
            if let row = fixture.rereadReport {
                correctionRows.append(sanitized(row, home: fixture.home.path) as! [String: Any])
            }
            let before = try fixture.userState()
            for task in try #require(corpus["tasks"] as? [[String: Any]]) {
                policyRows += try evaluate(task, fixture: fixture, organization: organization).map {
                    sanitized($0, home: fixture.home.path) as! [String: Any]
                }
                comparatorRows += try comparators(task, fixture: fixture, organization: organization).map {
                    sanitized($0, home: fixture.home.path) as! [String: Any]
                }
            }
            #expect(try fixture.userState() == before)
        }
        let result: [String: Any] = [
            "schema": 1, "labels_sha256": Self.labelsSHA256, "labels_sealed_no_later_than_utc": "2026-10-19T15:26:00Z",
            "harness_sha256": Locator.sha256(#filePath) as Any? ?? NSNull(),
            "policy_cases": policyRows, "comparators": comparatorRows, "corrections": correctionRows,
            "limits": labels["limitations"]!, "normal_tests_export_nothing": true
        ]
        if let path = ProcessInfo.processInfo.environment["GLEANER_CYCLE3_RESULTS"] {
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                .write(to: URL(fileURLWithPath: path))
        }
    }
}

private final class Cycle3Corpus {
    let home: URL
    let project: URL
    let indexer: Indexer
    let base = Date(timeIntervalSince1970: 1_920_100_000)
    var expectedText: [String: String] = [:]
    var rereadReport: [String: Any]?
    private var logURLs: [URL] = []

    init(label: [String: Any]) throws {
        home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("gleaner-cycle3-independent-\(UUID().uuidString)")
        project = home.appendingPathComponent("Workspaces/\(label["project"] as! String)")
        let logFolder = home.appendingPathComponent(".claude/projects/synthetic")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logFolder, withIntermediateDirectories: true)
        indexer = try Indexer(folders: LibraryFolders(home: home))
        for delivery in label["deliveries"] as! [[String: Any]] {
            let step = delivery["step"] as! Int
            var links: [String] = []
            for file in delivery["files"] as! [[String: Any]] {
                let relative = file["path"] as! String, text = file["text"] as! String
                let url = project.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
                try FileManager.default.setAttributes([.modificationDate: time(step).addingTimeInterval(-10)], ofItemAtPath: url.path)
                expectedText[Paths.standard(url.path)] = text
                links.append("[\(url.lastPathComponent)](\(relative))")
            }
            let session = delivery["session"] as! String
            let records: [[String: Any]] = [
                ["type": "user", "sessionId": session, "cwd": project.path, "timestamp": time(step).formatted(.iso8601),
                 "origin": ["kind": "human"], "message": ["role": "user", "content": delivery["request"]!]],
                ["type": "assistant", "sessionId": session, "cwd": project.path, "timestamp": time(step).formatted(.iso8601),
                 "message": ["role": "assistant", "model": "synthetic", "content": [["type": "text", "text": links.joined(separator: "\n")]]]]
            ]
            var bytes = Data()
            for record in records { bytes.append(try JSONSerialization.data(withJSONObject: record)); bytes.append(10) }
            let log = logFolder.appendingPathComponent("\(session).jsonl")
            try bytes.write(to: log)
            logURLs.append(log)
        }
        _ = try indexer.run(now: { time(10) })
        for pair in label["joins"] as? [[String]] ?? [] {
            try indexer.registry.correct(.sameWork, subject: path(pair[0]), target: path(pair[1]), at: time(11))
        }
        for pair in label["not_same"] as? [[String]] ?? [] {
            try indexer.registry.correct(.notSameWork, subject: path(pair[0]), target: path(pair[1]), at: time(12))
        }
        if let correction = label["user_project"] as? [String: Any] {
            let made = try indexer.registry.addProject(named: correction["initial_name"] as! String, at: time(13),
                moving: (correction["move_paths"] as! [String]).map(path))
            try indexer.registry.renameProject(made.key, to: correction["renamed_to"] as! String)
        }
        for review in label["reviews"] as? [[String: Any]] ?? [] {
            _ = try indexer.review(path(review["path"] as! String), as: try #require(Review.Kind(rawValue: review["kind"] as! String)),
                                   at: time(review["step"] as! Int))
        }
        if label["rederive_all_logs"] as? Bool == true {
            let before = try userState()
            let old = try organization()
            let oldWorks = old.works.map { "\($0.id)|\($0.project)|\($0.files.map(\.path).sorted().joined(separator: ","))" }.sorted()
            let oldDeliveries = old.works.flatMap(\.deliveries).map { "\($0.id)|\($0.sha256 ?? "nil")|\($0.capture?.provenance.rawValue ?? "nil")" }.sorted()
            for log in logURLs { try FileManager.default.setAttributes([.modificationDate: time(20)], ofItemAtPath: log.path) }
            let report = try indexer.run(now: { time(21) })
            let after = try organization()
            let afterWorks = after.works.map { "\($0.id)|\($0.project)|\($0.files.map(\.path).sorted().joined(separator: ","))" }.sorted()
            let afterDeliveries = after.works.flatMap(\.deliveries).map { "\($0.id)|\($0.sha256 ?? "nil")|\($0.capture?.provenance.rawValue ?? "nil")" }.sorted()
            let durable = try userState() == before
            let sameWorks = oldWorks == afterWorks, sameDeliveries = oldDeliveries == afterDeliveries
            #expect(report.logsRead == logURLs.count && durable && sameWorks && sameDeliveries)
            rereadReport = ["case": label["id"]!, "operation": "actual_complete_reread_of_every_fixture_log",
                "public_full_reset_claimed": false, "logs_expected": logURLs.count, "logs_read": report.logsRead,
                "user_state_unchanged": durable, "work_identity_and_membership_unchanged": sameWorks,
                "delivery_ids_capture_hashes_provenance_unchanged": sameDeliveries,
                "derived_tables_deleted": false]
        }
    }

    deinit { try? FileManager.default.removeItem(at: home) }
    func time(_ step: Int) -> Date { base.addingTimeInterval(Double(step) * 120) }
    func path(_ relative: String) -> String { Paths.standard(project.appendingPathComponent(relative).path) }
    func organization() throws -> Organization { try Organization(shown: indexer.registry.artifacts(), registry: indexer.registry) }
    func userState() throws -> [String] {
        let corrections = try indexer.registry.corrections().map { "correction|\($0.id)|\($0.kind.rawValue)|\($0.subject)|\($0.target)|\($0.madeAt)" }
        let projects = try indexer.registry.userProjects().map { "project|\($0.key)|\($0.name)|\($0.createdAt)" }
        let reviews = try indexer.registry.reviews().map { "review|\($0.id)|\($0.path)|\($0.sha256)|\($0.kind.rawValue)" }
        return (corrections + projects + reviews).sorted()
    }
}
