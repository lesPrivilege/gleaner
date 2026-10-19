import Foundation
import Testing
@testable import GleanerCore
import GleanerRetrievalExperiments

/// Durability through real indexing, with a separate, explicitly unsupported evidence-loss arm.
/// No production reset API, policy, adapter shape, or persistence contract is added here.
@Suite struct Cycle3CorrectionTests {
    private final class Fixture {
        let home: URL
        let indexer: Indexer
        let first = Date(timeIntervalSince1970: 1_930_000_000)
        var logs: [URL] = []
        var paths: [String] = []

        init() throws {
            home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("gleaner-cycle3-corrections-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/projects/synthetic"), withIntermediateDirectories: true)
            indexer = try Indexer(folders: LibraryFolders(home: home))
            let outputs = [
                ("Cedar", "estuary-notes.md", "Independent synthetic notes\n"),
                ("Cedar", "estuary-report.html", "<p>Synthetic report representation</p>\n"),
                ("Marsh", "estuary-notes.md", "Independent synthetic notes\n"),
                ("Cedar", "estuary-appendix.txt", "Synthetic appendix\n"),
            ]
            for (offset, output) in outputs.enumerated() {
                let workspace = home.appendingPathComponent("Workspaces/\(output.0)")
                paths.append(try file("out/\(output.1)", in: workspace, text: output.2))
                let session = "synthetic-\(offset)"
                let records: [[String: Any]] = [
                    ["type": "user", "sessionId": session, "cwd": workspace.path,
                     "timestamp": first.addingTimeInterval(-60).formatted(.iso8601),
                     "origin": ["kind": "human"], "message": ["role": "user", "content": "Prepare estuary material"]],
                    ["type": "assistant", "sessionId": session, "cwd": workspace.path,
                     "timestamp": first.addingTimeInterval(Double(offset)).formatted(.iso8601),
                     "message": ["role": "assistant", "model": "synthetic",
                                 "content": [["type": "text", "text": "[Output](out/\(output.1))"]]]],
                ]
                let log = home.appendingPathComponent(".claude/projects/synthetic/\(session).jsonl")
                var data = Data()
                for record in records { data.append(try JSONSerialization.data(withJSONObject: record)); data.append(10) }
                try data.write(to: log)
                logs.append(log)
            }
        }
        deinit { try? FileManager.default.removeItem(at: home) }

        @discardableResult
        func file(_ name: String, in workspace: URL, text: String) throws -> String {
            let url = workspace.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: first.addingTimeInterval(-10)], ofItemAtPath: url.path)
            return Paths.standard(url.path)
        }

        func organization() throws -> Organization {
            try Organization(shown: indexer.registry.artifacts(), registry: indexer.registry)
        }

        @discardableResult
        func run(_ seconds: Double = 120) throws -> Indexer.Report {
            try indexer.run(now: { self.first.addingTimeInterval(seconds) })
        }

        /// Exercise the normal changed-log path; the native reply lines and timestamps stay put.
        func appendTitles() throws {
            for (offset, log) in logs.enumerated() {
                let handle = try FileHandle(forWritingTo: log)
                defer { try? handle.close() }
                try handle.seekToEnd()
                let record: [String: Any] = ["type": "custom-title", "sessionId": "synthetic-\(offset)", "customTitle": "Synthetic assessment"]
                var data = try JSONSerialization.data(withJSONObject: record)
                data.append(10)
                try handle.write(contentsOf: data)
            }
        }

        /// Test harness only. Captures and native file observations are deliberately retained.
        func clearLogProjection() throws {
            try indexer.registry.transaction {
                try indexer.registry.db.execute("""
                    DELETE FROM log_files;
                    DELETE FROM sessions;
                    DELETE FROM deliveries;
                    DELETE FROM meta WHERE key IN ('generation', 'scanned_at', 'sources');
                    """)
            }
        }
    }

    private struct Selection: Codable, Equatable {
        var policy: String
        var task: String
        var raw: Int
        var eligible: Int
        var selected: Int
        var selectedWorkIDs: [String]
        var selectedDeliveryIDs: [String]
        var representationCounts: [Int]
    }

    private struct Stage: Codable {
        var name: String
        var logsRead: Int
        var works: Int
        var broadQueryMatches: Int
        var projectNameMatches: Int
        var collectionNameMatches: Int
        var selections: [Selection]
    }

    private struct Report: Codable {
        var schema = 1
        var basis: String
        var stages: [Stage]
        var checks: [String: Bool]
        var retainedTableCounts: [String: Int]
        var limitations: [String]
    }

    private let retainedTables = ["captures", "spans", "observations", "listings", "members", "kept", "corrections", "projects", "units", "reviews", "sources_off"]

    /// Stable table comparison includes all values, including hashes, provenance and timestamps.
    private func table(_ name: String, registry: Registry) throws -> [String] {
        try registry.db.rows("SELECT * FROM \(name)").map {
            String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self)
        }.sorted()
    }

    private func snapshot(_ registry: Registry) throws -> [String: [String]] {
        try Dictionary(uniqueKeysWithValues: retainedTables.map { ($0, try table($0, registry: registry)) })
    }

    private func stage(_ name: String, logsRead: Int, fixture: Fixture, project: String, unit: String) throws -> Stage {
        let organization = try fixture.organization()
        let reviews = Reviews(try fixture.indexer.registry.reviews())
        var selections: [Selection] = []
        let tasks: [(String, Cycle3Selection.TaskScope)] = [
            ("corrected_project", .init(projectKey: project)),
            ("corrected_collection", .init(unitKey: unit)),
            ("approved_collection", .init(unitKey: unit, byteState: .approved)),
        ]
        for policy in Cycle3Selection.Policy.allCases {
            for (taskName, scope) in tasks {
                let result = try Cycle3Selection.evaluate(organization: organization, terms: ["estuary"],
                    policy: policy, task: scope, reviews: reviews, limit: 10)
                selections.append(Selection(policy: policy.rawValue, task: taskName,
                    raw: result.rawCandidates.count, eligible: result.eligibleCandidates.count, selected: result.selected.count,
                    selectedWorkIDs: result.selected.map(\.workID), selectedDeliveryIDs: result.selected.map(\.deliveryID),
                    representationCounts: result.selected.map { $0.representations.count }))
            }
        }
        return Stage(name: name, logsRead: logsRead, works: organization.works.count,
            broadQueryMatches: organization.search(["estuary"]).count,
            projectNameMatches: organization.search(["harbor"]).count,
            collectionNameMatches: organization.search(["signoff"]).count, selections: selections)
    }

    /// Export only public synthetic counts and fixture-relative Work IDs; random delivery IDs are
    /// replaced by stable fixture labels. No machine paths, actual library IDs or logs leave tests.
    private func export(_ report: Report, named filename: String, fixture: Fixture) throws {
        guard let directory = ProcessInfo.processInfo.environment["GLEANER_CYCLE3_RESULTS_DIR"] else { return }
        var publicReport = report
        let artifacts = try fixture.indexer.registry.artifacts()
        var deliveries: [String: String] = [:]
        for artifact in artifacts {
            for delivery in artifact.deliveries {
                deliveries[delivery.id] = artifact.path.replacingOccurrences(of: Paths.standard(fixture.home.path) + "/", with: "") + "#\(delivery.number)"
            }
        }
        for index in publicReport.stages.indices {
            for selection in publicReport.stages[index].selections.indices {
                publicReport.stages[index].selections[selection].selectedWorkIDs = publicReport.stages[index].selections[selection].selectedWorkIDs.map {
                    $0.replacingOccurrences(of: Paths.standard(fixture.home.path) + "/", with: "")
                }
                publicReport.stages[index].selections[selection].selectedDeliveryIDs = publicReport.stages[index].selections[selection].selectedDeliveryIDs.map { deliveries[$0] ?? "unavailable" }
            }
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(publicReport).write(to: folder.appendingPathComponent(filename))
    }

    @Test func correctionsChangeRetrievalAndSurviveAllLogRereadAndProjectionReconstruction() throws {
        let fixture = try Fixture()
        let initialRun = try fixture.run()
        let registry = fixture.indexer.registry
        let original = try fixture.organization()
        #expect(initialRun.logsRead == 4 && original.works.count == 4)
        let initialNotes = try #require(original.work(containing: fixture.paths[0]))
        let independentNotes = try #require(original.work(containing: fixture.paths[2]))
        #expect(initialNotes.latest.latest.sha256 != nil && initialNotes.latest.latest.sha256 == independentNotes.latest.latest.sha256)
        #expect(initialNotes.id != independentNotes.id && initialNotes.project != independentNotes.project)

        let project = try registry.addProject(named: "Harbor assessment", at: fixture.first.addingTimeInterval(130))
        let unit = try registry.addUnit(named: "Draft packet", in: project.key, at: fixture.first.addingTimeInterval(131))
        _ = try fixture.indexer.review(fixture.paths[1], as: .approved, note: "Synthetic human verdict", at: fixture.first.addingTimeInterval(132))
        let reviews = try registry.reviews()
        var stages = [try stage("before_corrections", logsRead: initialRun.logsRead, fixture: fixture, project: project.key, unit: unit.key)]
        let originalCaptures = try table("captures", registry: registry)
        try registry.correct([
            (.sameWork, fixture.paths[0], fixture.paths[1]),
            (.project, fixture.paths[1], project.key),
            (.combine, independentNotes.project, project.key),
            (.unit, fixture.paths[0], unit.key),
            (.unitName, unit.key, "Signoff packet"),
        ], at: fixture.first.addingTimeInterval(135))
        try registry.renameProject(project.key, to: "Harbor Review")
        let corrected = try fixture.organization()
        let joined = try #require(corrected.work(containing: fixture.paths[1]))
        #expect(joined.id == initialNotes.id)
        #expect(Set(joined.files.map(\.path)) == Set(fixture.paths.prefix(2)))
        #expect(joined.project == project.key && joined.unit == unit.key)
        #expect(corrected.unitName(unit.key) == "Signoff packet")
        #expect(corrected.work(containing: fixture.paths[2])?.id == independentNotes.id)
        #expect(corrected.work(containing: fixture.paths[2])?.files.count == 1)
        #expect(try registry.reviews() == reviews)
        #expect(try table("captures", registry: registry) == originalCaptures)
        stages.append(try stage("after_corrections", logsRead: 0, fixture: fixture, project: project.key, unit: unit.key))
        #expect(stages[0].broadQueryMatches == 4 && stages[1].broadQueryMatches == 3)
        #expect(stages[0].projectNameMatches == 0 && stages[1].projectNameMatches == 2)
        #expect(stages[0].collectionNameMatches == 0 && stages[1].collectionNameMatches == 1)
        #expect(stages[0].selections.allSatisfy { $0.selected == 0 })
        #expect(stages[1].selections.allSatisfy { $0.selected == ($0.task == "corrected_project" ? 2 : 1) })
        #expect(stages[1].selections.filter { $0.task != "corrected_project" }.allSatisfy { $0.representationCounts == [2] })

        let retained = try snapshot(registry)
        let library = try registry.index().library
        try fixture.appendTitles()
        let reread = try fixture.run(150)
        #expect(reread.logsRead == fixture.logs.count && reread.newDeliveries == 0)
        #expect(try snapshot(registry) == retained)
        stages.append(try stage("all_changed_logs_reread", logsRead: reread.logsRead, fixture: fixture, project: project.key, unit: unit.key))
        #expect(stages[2].selections == stages[1].selections)

        // Force every unchanged log through the existing reader. This is cursor invalidation,
        // not evidence reconstruction, and is explicitly distinguished in exported results.
        try registry.db.execute("UPDATE log_files SET mtime = -1")
        let forced = try fixture.run(160)
        #expect(forced.logsRead == fixture.logs.count)
        #expect(try snapshot(registry) == retained)
        stages.append(try stage("forced_cursor_reread", logsRead: forced.logsRead, fixture: fixture, project: project.key, unit: unit.key))
        #expect(stages[3].selections == stages[1].selections)

        try fixture.clearLogProjection()
        #expect(try registry.db.rows("SELECT * FROM deliveries").isEmpty)
        #expect(try registry.db.rows("SELECT * FROM log_files").isEmpty)
        #expect(try snapshot(registry) == retained)
        #expect(try registry.index().library == library)
        let rebuilt = try fixture.run(170)
        #expect(rebuilt.logsRead == fixture.logs.count && rebuilt.newDeliveries == 0)
        #expect(try registry.db.rows("SELECT * FROM deliveries").count == 4)
        #expect(try snapshot(registry) == retained)
        #expect(try registry.index().library == library)
        stages.append(try stage("test_only_log_projection_reconstructed", logsRead: rebuilt.logsRead, fixture: fixture, project: project.key, unit: unit.key))
        #expect(stages[4].selections == stages[1].selections)
        let reopened = try Registry(path: registry.path)
        #expect(try snapshot(reopened) == retained && reopened.index().library == library)
        let reloaded = try Organization(shown: reopened.artifacts(), registry: reopened)
        #expect(reloaded.work(containing: fixture.paths[1])?.id == initialNotes.id)
        #expect(reloaded.unitName(unit.key) == "Signoff packet")
        #expect(try reopened.reviews() == reviews)

        let equalBytesSeparate = initialNotes.latest.latest.sha256 == independentNotes.latest.latest.sha256
            && initialNotes.id != independentNotes.id && initialNotes.project != independentNotes.project
            && reloaded.work(containing: fixture.paths[2])?.files.count == 1
        let checks = ["equal_bytes_separate_contexts_not_joined": equalBytesSeparate,
            "human_join_retains_two_representations": Set(joined.files.map(\.path)) == Set(fixture.paths.prefix(2)),
            "authored_rows_and_historical_evidence_unchanged": try snapshot(registry) == retained,
            "capture_hashes_and_review_rows_unchanged": try table("captures", registry: registry) == originalCaptures && registry.reviews() == reviews,
            "post_correction_selection_and_ids_stable": stages.dropFirst().allSatisfy { $0.selections == stages[1].selections },
            "library_namespace_preserved": try reopened.index().library == library,
            "reopen_preserves_corrections": try snapshot(reopened) == retained,
        ]
        try #require(checks.values.allSatisfy { $0 })
        try export(Report(basis: "Actual Indexer.run, durable Registry corrections and shared Organization.search through frozen Cycle3Selection; no production reset API.",
            stages: stages, checks: checks,
            retainedTableCounts: retained.mapValues(\.count), limitations: [
                "Work.id is the earliest delivered member path; an explicit join can change a former member's Work ID.",
                "Projection reconstruction is a test-only SQL operation, not a supported full library reset or migration.",
                "Observations, spans, captures, folder membership and kept completion are retained evidence, not recovered from current files.",
                "Five explicit correction kinds plus project renaming are tested; no inference of current-working authority.",
            ]), named: "correction-results.json", fixture: fixture)
    }

    @Test func missingKeptOriginalSurvivesProjectionReconstructionButNotEvidenceDeletion() throws {
        let fixture = try Fixture()
        let path = try fixture.file("out/field-observation.md", in: fixture.home.appendingPathComponent("Workspaces/Cedar"), text: "Synthetic observation kept by a person\n")
        _ = try fixture.run()
        let registry = fixture.indexer.registry
        let observed = try #require(fixture.organization().candidate(path)?.latest)
        try registry.correct(.kept, subject: path, target: observed.logPath, at: fixture.first.addingTimeInterval(130))
        _ = try fixture.indexer.review(path, as: .approved, at: fixture.first.addingTimeInterval(131))
        let original = try #require(fixture.organization().work(containing: path))
        #expect(original.latest.latest.kept != nil && original.latest.latest.sha256 != nil)
        let retained = try snapshot(registry)
        let destination = fixture.home.appendingPathComponent("Detached/field-observation.md")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(atPath: path, toPath: destination.path)
        #expect(Locator.stat(path).kind == .missing)
        try fixture.clearLogProjection()
        let safe = try fixture.run(160)
        let preserved = try #require(fixture.organization().work(containing: path))
        #expect(safe.logsRead == 4 && preserved.id == original.id && preserved.latest.latest.id == original.latest.latest.id)
        #expect(preserved.latest.latest.sha256 == original.latest.latest.sha256 && preserved.latest.latest.kept != nil)
        #expect(try snapshot(registry) == retained)
        let safeRetained = try snapshot(registry) == retained
        let safeIdentity = preserved.id == original.id && preserved.latest.latest.id == original.latest.latest.id
            && preserved.latest.latest.sha256 == original.latest.latest.sha256 && preserved.latest.latest.kept != nil

        // Deliberately unsafe counterexample in this disposable synthetic DB only. Observations
        // cannot be recreated from a missing original: this operation is NOT a rebuild contract.
        try fixture.clearLogProjection()
        try registry.transaction {
            try registry.db.execute("DELETE FROM observations; DELETE FROM spans;")
        }
        let unsafe = try fixture.run(180)
        #expect(unsafe.logsRead == 4)
        #expect(try fixture.organization().work(containing: path) == nil)
        for name in retainedTables where name != "observations" && name != "spans" {
            #expect(try table(name, registry: registry) == retained[name])
        }
        let stillRetained = try retainedTables.filter { $0 != "observations" && $0 != "spans" }.allSatisfy {
            try table($0, registry: registry) == retained[$0]
        }
        let checks = ["original_missing_at_recorded_path": Locator.stat(path).kind == .missing,
            "safe_projection_reconstruction_preserves_kept_work": safeRetained,
            "safe_projection_reconstruction_preserves_kept_id_and_hash": safeIdentity,
            "unsafe_evidence_deletion_loses_kept_work_visibility": try fixture.organization().work(containing: path) == nil,
            "unsafe_evidence_deletion_retains_correction_review_and_kept_completion_rows": stillRetained,
        ]
        try #require(checks.values.allSatisfy { $0 })
        try export(Report(basis: "Synthetic negative control: delete native observations after moving a kept original outside its recorded workspace; this is not a supported reset.",
            stages: [], checks: checks,
            retainedTableCounts: retained.mapValues(\.count), limitations: [
                "Safe reconstruction reread 4 logs; unsafe evidence deletion reread 4 logs but could not recover the missing observation.",
                "A retained correction and saved hash alone do not replace the native observation used by Registry.kept.",
                "No public evidence-deletion/reset behavior, recovery API or source mutation is proposed.",
            ]), named: "correction-evidence-loss-results.json", fixture: fixture)
    }
}
