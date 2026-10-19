import Foundation
import Testing
@testable import GleanerCore
@testable import GleanerRetrievalExperiments

/// Independent labels were sealed before policy inspection. This harness supplies real
/// synthetic index/review records, invokes shared-core policies and scores their responses.
/// It contains no search, ranking, state-selection or source-resolution implementation.
@Suite struct Cycle2HeldOutTests {
    private static let labelsSHA256 = "d11c155fdcb3a42e7d8e7c20c681e4ccb7f0b93466dfe0ea0ab61f71d645aab9"
    private static let sourceFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    private func encoded<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: Catalog.encoder.encode(value))
    }

    private func sanitized(_ value: Any, home: String) -> Any {
        if let text = value as? String { return text.replacingOccurrences(of: home, with: "$SYNTHETIC_HOME").replacingOccurrences(of: Paths.standard(home), with: "$SYNTHETIC_HOME") }
        if let values = value as? [Any] { return values.map { sanitized($0, home: home) } }
        if let values = value as? [String: Any] { return values.mapValues { sanitized($0, home: home) } }
        return value
    }

    private func stateCases(_ labels: [[String: Any]]) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for label in labels {
            let fixture = try HeldOutCorpus(project: "TideStation")
            let path = label["path"] as! String
            let versions = label["versions"] as! [[String: Any]]
            let wanted = label["wanted"] as! [String: Any]
            var hashes: [String] = []
            for (number, version) in versions.enumerated() {
                let file = try fixture.file(path, version["text"] as! String, step: number)
                hashes.append(try #require(Locator.sha256(file.path)))
                if version["delivered"] as? Bool == true {
                    try fixture.log(session: "history", request: "Deliver the operating document",
                                    reply: "[Document](\(path))", step: number, append: true)
                    try fixture.index(step: number)
                }
                if let kind = version["review"] as? String {
                    _ = try fixture.indexer.review(file.path, as: try #require(Review.Kind(rawValue: kind)),
                                                   at: fixture.time(number).addingTimeInterval(10))
                }
                if version["published"] as? Bool == true {
                    _ = try fixture.indexer.review(file.path, as: .published, at: fixture.time(number).addingTimeInterval(20))
                }
            }
            let file = fixture.project.appendingPathComponent(path)
            if label["remove_current"] as? Bool == true { try FileManager.default.removeItem(at: file) }
            let organization = try fixture.organization()
            let work = try #require(organization.work(containing: Paths.standard(file.path)))
            let reviews = Reviews(try fixture.indexer.registry.reviews())
            let observed = Locator.sha256(file.path)
            let present: Present = observed.map(Present.read) ?? .absent(work)
            for intent in StatePolicies.Intent.allCases {
                let labelKey = intent == .currentOriginal ? "current_observation" : intent.rawValue
                let expectedVersion = wanted[labelKey] as? Int
                let expectedSHA = expectedVersion.map { hashes[$0] }
                let expectedStatus: StatePolicies.Fact.Status = expectedSHA != nil ? .known
                    : intent == .currentOriginal ? .absent : .unknown
                let expectedKind: String? = if intent == .lastReviewed, let index = expectedVersion {
                    versions[index]["review"] as? String
                } else if intent == .lastPublished, expectedVersion != nil { "published" } else { nil }
                for policy in StatePolicies.Policy.allCases {
                    let start = Date()
                    let result = StatePolicies.evaluate(work: work, reviews: reviews, present: present,
                        presentPath: Paths.standard(file.path), intent: intent, policy: policy)
                    func correct(_ fact: StatePolicies.Fact?) -> Bool {
                        guard let fact else { return false }
                        return fact.intent == intent && fact.status == expectedStatus
                            && fact.sha256 == expectedSHA && fact.reviewKind == expectedKind
                    }
                    let requested = result.disclosures.first { $0.intent == intent }
                    let row: [String: Any] = [
                        "case": label["id"]!, "intent": intent.rawValue, "policy": policy.rawValue,
                        "expected_status": expectedStatus.rawValue, "expected_sha256": expectedSHA as Any? ?? NSNull(),
                        "expected_review_kind": expectedKind as Any? ?? NSNull(),
                        "selected_fact_correct": correct(result.selected), "requested_disclosure_correct": correct(requested),
                        "selection_actions_after_response": policy == .discloseAllStates ? 1 : 0,
                        "negative_control_only": policy == .newestDeliveryControl,
                        "latency_ms": Date().timeIntervalSince(start) * 1_000,
                        "response": try encoded(result)
                    ]
                    rows.append(sanitized(row, home: fixture.home.path) as! [String: Any])
                }
            }
        }
        return rows
    }

    private func selectionCases(_ labels: [[String: Any]]) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for label in labels {
            let fixture = try HeldOutCorpus(project: label["project"] as! String)
            let files = label["files"] as! [[String: Any]]
            var wanted = Set<String>()
            let projects = [fixture.project] + ((label["second_project"] as? String)
                .map { [fixture.home.appendingPathComponent("Workspaces/\($0)")] } ?? [])
            for (index, project) in projects.enumerated() {
                var reply: [String] = []
                for file in files {
                    let path = file["path"] as! String
                    let url = try fixture.file(path, file["text"] as! String, project: project)
                    if file["wanted"] as? Bool == true { wanted.insert(Paths.standard(url.path)) }
                    reply.append("[\(url.lastPathComponent)](\(path))")
                }
                try fixture.log(session: "delivery-\(index)", request: label["request"] as! String,
                    reply: reply.joined(separator: "\n"), project: project, step: index)
            }
            try fixture.index(step: projects.count)
            let organization = try fixture.organization()
            let terms = label["query"] as! [String]
            for policy in FirstLayerPolicies.Policy.allCases {
                let start = Date()
                let result = try FirstLayerPolicies.evaluate(organization: organization, terms: terms, policy: policy, limit: 5)
                // A group with several members is a navigation choice. Do not count all its
                // hidden members as visible actionable objects merely to improve precision.
                let actionable = result.firstLayer.filter { $0.members.count == 1 }.flatMap(\.members)
                let visibleIDs = Set(actionable.map(\.path))
                let visibleRelevant = visibleIDs.intersection(wanted)
                let grouped = result.firstLayer.filter { $0.members.count > 1 }
                let firstReachable = Set(result.firstLayer.flatMap(\.members).map(\.path))
                let allReachable = firstReachable.union(result.deferred.map(\.path))
                var actions = grouped.filter { !Set($0.members.map(\.path)).isDisjoint(with: wanted) }.count
                if !wanted.intersection(Set(result.deferred.map(\.path))).isEmpty { actions += 1 }
                let row: [String: Any] = [
                    "case": label["id"]!, "policy": policy.rawValue, "query": terms,
                    "ambiguous": label["ambiguous"]!, "wanted_objects": wanted.count,
                    "first_rows": result.firstLayer.count, "actionable_objects": actionable.count,
                    "first_object_precision": actionable.isEmpty ? NSNull() : Double(visibleRelevant.count) / Double(actionable.count),
                    "first_object_recall": Double(visibleRelevant.count) / Double(wanted.count),
                    "first_object_noise": actionable.count - visibleRelevant.count,
                    "reachable_recall": Double(allReachable.intersection(wanted).count) / Double(wanted.count),
                    "wanted_reachable_without_expanding_deferred": Double(firstReachable.intersection(wanted).count) / Double(wanted.count),
                    "group_or_deferred_expansions_for_all_wanted": actions,
                    "expanded_member_noise": firstReachable.subtracting(wanted).count,
                    "duplicate_work_id_count": result.allMatches.count - Set(result.allMatches.map(\.workID)).count,
                    "matching_projects": Set(result.allMatches.map(\.project)).count,
                    "latency_ms": Date().timeIntervalSince(start) * 1_000,
                    "response": try encoded(result)
                ]
                rows.append(sanitized(row, home: fixture.home.path) as! [String: Any])
            }
        }
        return rows
    }

    private func sectionCases(_ labels: [[String: Any]]) throws -> [[String: Any]] {
        let fixture = try HeldOutCorpus(project: "CoastalArchive")
        for (index, label) in labels.enumerated() {
            let path = "reports/audit-\(index).md"
            try fixture.file(path, label["document"] as! String)
            try fixture.log(session: "report-\(index)", request: "Deliver the independent inspection",
                            reply: "[Inspection](\(path))", step: index)
        }
        try fixture.index(step: labels.count)
        let catalog = try Catalog(home: fixture.home)
        let artifacts = try fixture.indexer.registry.artifacts()
        var rows: [[String: Any]] = []
        var identities: [String: Set<String>] = [:]
        for (index, label) in labels.enumerated() {
            let delivery = try #require(artifacts.first { $0.name == "audit-\(index).md" }?.latest.id)
            let query = label["query"] as! String
            let expected = Set(label["wanted_titles"] as! [String])
            let global = try catalog.find([query])
            for policy in SectionLookup.Policy.allCases {
                let start = Date()
                let result = try SectionLookup.evaluate(catalog: catalog, delivery: delivery, query: query, policy: policy)
                let titles = result.sections.map(\.title)
                let matched = Set(titles).intersection(expected)
                let ownIDs = Set(result.sections.map(\.id))
                let otherIDs = Set(identities.filter { $0.key != delivery }.values.flatMap { $0 })
                let separateIDs = ownIDs.isDisjoint(with: otherIDs)
                identities[delivery, default: []].formUnion(ownIDs)
                var otherReportRefused: Bool? = nil
                if let otherID = otherIDs.sorted().first {
                    do {
                        _ = try catalog.readSection(delivery, section: otherID)
                        otherReportRefused = false
                    } catch Catalog.Failure.sectionNotFound {
                        otherReportRefused = true
                    }
                }
                var exactBytes = true
                for section in result.sections {
                    let text = try catalog.readSection(delivery, section: section.id)
                    exactBytes = exactBytes && text.reference.sha256 == result.reference.sha256
                        && text.section.id == section.id && !text.text.isEmpty
                }
                let row: [String: Any] = [
                    "case": label["id"]!, "policy": policy.rawValue, "expected_titles": expected.sorted(),
                    "actual_titles": titles, "exact_set_correct": Set(titles) == expected,
                    "precision": titles.isEmpty ? NSNull() : Double(matched.count) / Double(titles.count),
                    "recall": expected.isEmpty ? NSNull() : Double(matched.count) / Double(expected.count),
                    "global_search_hits": global.total, "outline_requests": result.outlineRequests,
                    "expansions_from_selected_report_to_exact_text": result.sections.isEmpty ? NSNull() : 2,
                    "exact_bytes_verified": exactBytes,
                    "cross_report_section_ids_disjoint": separateIDs,
                    "other_report_section_refused": otherReportRefused as Any? ?? NSNull(),
                    "logical_finding_task_unmet": label["limitation"] != nil,
                    "limitation": label["limitation"] as Any? ?? NSNull(),
                    "latency_ms": Date().timeIntervalSince(start) * 1_000,
                    "response": try encoded(result)
                ]
                rows.append(sanitized(row, home: fixture.home.path) as! [String: Any])
                #expect(separateIDs && otherReportRefused != false)
            }
        }
        return rows
    }

    @Test func evaluateFrozenPolicies() throws {
        let source = Self.sourceFolder.appendingPathComponent("heldout-labels.json")
        #expect(Locator.sha256(source.path) == Self.labelsSHA256)
        let labels = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any])
        let states = try stateCases(labels["state_cases"] as! [[String: Any]])
        let selection = try selectionCases(labels["selection_cases"] as! [[String: Any]])
        let sections = try sectionCases(labels["section_cases"] as! [[String: Any]])
        let current = try currentCases(labels["current_cases"] as! [[String: Any]])
        let report: [String: Any] = [
            "schema": 1, "checkpoint": "7e004a7 plus explicitly provisional cycle2 policies",
            "labels_sha256": Self.labelsSHA256, "labels_sealed_no_later_than_utc": "2026-10-19T15:04:31Z",
            "harness_sha256": Locator.sha256(Self.sourceFolder.appendingPathComponent("heldout.swift").path) as Any? ?? NSNull(),
            "state_cases": states, "selection_cases": selection, "section_cases": sections, "current_cases": current,
            "limits": ["synthetic purposive corpus; no population or Finder-superiority claim",
                "state newest-delivery control is intentionally naive and is not current Catalog baseline",
                "first-layer grouping keeps all candidates in its response; expansion counts are interaction proxies, not measured API calls or payload reduction",
                "latency single-run in-process observations; no scale conclusion",
                "native Mac filesystem/UI not executed"]
        ]
        // Normal test/CI runs evaluate the invariants without rewriting checked-in evidence.
        // An evaluator must explicitly choose an export path to retain a new measurement.
        if let path = ProcessInfo.processInfo.environment["GLEANER_CYCLE2_RESULTS"] {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                .write(to: URL(fileURLWithPath: path))
        }
        #expect(states.count == 60 && selection.count == 12 && sections.count == 8)
    }

    private func currentCases(_ labels: [[String: Any]]) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for label in labels {
            let fixture = try HeldOutCorpus(project: "CivicArchive")
            let relative = "packet/inventory.md"
            let file = try fixture.file(relative, "Original catalog entry\n")
            let isListed = label["state"] as? String == "listed"
            try fixture.log(session: "packet", request: "Deliver the archive packet",
                            reply: isListed ? "[Packet](packet/)" : "[Inventory](\(relative))")
            try fixture.index()
            let delivery = try #require(try fixture.indexer.registry.artifacts().first { $0.path == Paths.standard(file.path) }?.latest)
            #expect(isListed ? delivery.capture?.provenance == .listed : delivery.sha256 != nil)
            // Canonical fixture spellings avoid the system's /tmp or /var aliases on Mac.
            // Resolve before deliberately replacing the leaf with a symlink; those test links
            // must remain visible to the checked-mode policy.
            var checkedDelivery = delivery
            checkedDelivery.path = file.resolvingSymlinksInPath().path
            let authorizedRoot = fixture.project.resolvingSymlinksInPath()
            let arrangement = label["original"] as! String
            switch arrangement {
            case "mutated":
                try fixture.file(relative, "Uncaptured replacement catalog entry\n", step: 1)
            case "missing":
                try FileManager.default.removeItem(at: file)
            case "outside_symlink", "inside_symlink":
                try FileManager.default.removeItem(at: file)
                let target = arrangement == "inside_symlink" ? fixture.project : fixture.home.appendingPathComponent("OtherWorkspace")
                let linked = try fixture.file("linked/real.md", "Linked source bytes\n", project: target)
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: linked)
            case "directory":
                try FileManager.default.removeItem(at: file)
                try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
            default: break
            }
            for mode in OriginalResolutionExperiment.Mode.allCases {
                let sourceBefore = try fixture.sourceFiles()
                let reviewsBefore = try fixture.indexer.registry.reviews()
                let captureBefore = try fixture.indexer.registry.artifacts().first { $0.path == Paths.standard(file.path) }?.latest.capture
                let registryBefore = try fixture.libraryFiles()
                var mutated = false
                let result: OriginalResolutionExperiment.Result
                if arrangement == "concurrent_mutation", mode == .hashCurrent {
                    var mutationError: (any Error)?
                    result = OriginalResolutionExperiment.resolve(delivery: checkedDelivery, mode: mode,
                        authorizedRoots: [authorizedRoot], hashByteLimit: 1 << 20, afterChunk: { _ in
                            guard !mutated else { return }
                            mutated = true
                            do { try Data("Mutation made by the evaluation hook\n".utf8).write(to: file) }
                            catch { mutationError = error }
                        })
                    if let mutationError { throw mutationError }
                } else {
                    result = OriginalResolutionExperiment.resolve(delivery: checkedDelivery, mode: mode,
                        authorizedRoots: [authorizedRoot], hashByteLimit: 1 << 20)
                }
                let registryAfter = try fixture.libraryFiles()
                let sourceAfter = try fixture.sourceFiles()
                let reviewsAfter = try fixture.indexer.registry.reviews()
                let captureAfter = try fixture.indexer.registry.artifacts().first { $0.path == Paths.standard(file.path) }?.latest.capture
                let noWrites = registryBefore == registryAfter && reviewsBefore == reviewsAfter && captureBefore == captureAfter
                    && (mutated || sourceBefore == sourceAfter)
                let currentHash = result.current.observedCurrentSha256
                let correctVerifiedHash = result.current.state == .hashedCurrent
                    ? currentHash != nil && currentHash == Locator.sha256(file.path) : currentHash == nil
                let noHistoricalInvention = result.capturedSha256 == delivery.sha256
                    && (delivery.sha256 != nil || result.current.matchesCapturedBytes == nil)
                let expectedHashState: OriginalResolutionExperiment.State = switch arrangement {
                case "present", "mutated", "inside_symlink": .hashedCurrent
                case "missing": .missing
                case "outside_symlink": .deniedScope
                case "directory": .notRegular
                case "concurrent_mutation": .changedDuringObservation
                default: .unreadable
                }
                // The sealed expected current observation allows in-root links. A policy may
                // reject them safely; record this usability cost separately from truthfulness.
                let exactObservationTask = mode == .hashCurrent && result.current.state == expectedHashState
                let row: [String: Any] = [
                    "case": label["id"]!, "mode": mode.rawValue, "executed": true,
                    "expected_hash_mode_state": expectedHashState.rawValue,
                    "hash_mode_task_met": mode == .hashCurrent ? exactObservationTask as Any : NSNull(),
                    "verified_hash_claim_correct": correctVerifiedHash,
                    "historical_capture_not_invented": noHistoricalInvention,
                    "no_registry_capture_review_or_source_writes": noWrites,
                    "source_mutation_by_test_hook": mutated,
                    "path_only_makes_no_observation": mode == .pathOnly
                        ? result.bytesRead == 0 && result.current.observedAt == nil && currentHash == nil : true,
                    "metadata_does_not_claim_hash": mode == .metadata ? result.bytesRead == 0 && currentHash == nil : true,
                    "response": try encoded(result)
                ]
                rows.append(sanitized(row, home: fixture.home.path) as! [String: Any])
                #expect(noWrites && correctVerifiedHash && noHistoricalInvention)
            }
        }
        return rows
    }
}

private final class HeldOutCorpus {
    let home: URL
    let project: URL
    let indexer: Indexer
    let base = Date(timeIntervalSince1970: 1_920_000_000)

    init(project name: String) throws {
        home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("gleaner-cycle2-independent-\(UUID().uuidString)")
        project = home.appendingPathComponent("Workspaces/\(name)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/projects/synthetic"), withIntermediateDirectories: true)
        indexer = try Indexer(folders: LibraryFolders(home: home))
    }

    deinit { try? FileManager.default.removeItem(at: home) }

    func time(_ step: Int) -> Date { base.addingTimeInterval(Double(step) * 120) }

    @discardableResult
    func file(_ path: String, _ text: String, project target: URL? = nil, step: Int = 0) throws -> URL {
        let url = (target ?? project).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: time(step).addingTimeInterval(-10)], ofItemAtPath: url.path)
        return url
    }

    func log(session: String, request: String, reply: String, project target: URL? = nil, step: Int = 0, append: Bool = false) throws {
        let url = home.appendingPathComponent(".claude/projects/synthetic/\(session).jsonl")
        let stamp = time(step).formatted(.iso8601), cwd = (target ?? project).path
        let records: [[String: Any]] = [
            ["type": "user", "sessionId": session, "cwd": cwd, "timestamp": stamp,
             "origin": ["kind": "human"], "message": ["role": "user", "content": request]],
            ["type": "assistant", "sessionId": session, "cwd": cwd, "timestamp": stamp,
             "message": ["role": "assistant", "model": "synthetic", "content": [["type": "text", "text": reply]]]],
        ]
        var bytes = append ? ((try? Data(contentsOf: url)) ?? Data()) : Data()
        for record in records { bytes.append(try JSONSerialization.data(withJSONObject: record)); bytes.append(10) }
        try bytes.write(to: url)
    }

    func index(step: Int = 0) throws { _ = try indexer.run(now: { time(step).addingTimeInterval(5) }) }

    func organization() throws -> Organization {
        try Organization(shown: indexer.registry.artifacts(), registry: indexer.registry)
    }

    func sourceFiles() throws -> [String: Data] { try contents(project) }

    func libraryFiles() throws -> [String: Data] {
        try contents(LibraryFolders(home: home).support)
    }

    private func contents(_ root: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        func collect(_ folder: URL) throws {
            for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                let relative = String(url.path.dropFirst(root.path.count + 1))
                if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
                    files[relative] = Data(("SYMLINK:" + target).utf8)
                } else if (try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory {
                    try collect(url)
                } else {
                    files[relative] = try Data(contentsOf: url)
                }
            }
        }
        try collect(root)
        return files
    }
}
