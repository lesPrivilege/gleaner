import Foundation
import Testing
import GleanerCore
import GleanerRetrievalExperiments

@Suite struct ExperimentalSectionLookupTests {
    @Test func exactIdentifierDistinguishesR1FromR10ButDoesNotClaimGlobalIdentity() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-section-policy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("work/Estuary")
        let logs = home.appendingPathComponent(".claude/projects/synthetic")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let content = "# Review\n## R1: Boundary\nUnresolved.\n## R10: Timing\nUnresolved.\n## R1: Another occurrence\nAlso unresolved.\n"
        for name in ["survey.md", "independent.md"] { try Data(content.utf8).write(to: project.appendingPathComponent(name)) }
        let records: [[String: Any]] = [
            ["type": "user", "sessionId": "synthetic", "cwd": project.path, "timestamp": "2030-03-17T12:00:00Z",
             "origin": ["kind": "human"], "message": ["role": "user", "content": "Review the survey"]],
            ["type": "assistant", "sessionId": "synthetic", "cwd": project.path, "timestamp": "2030-03-17T12:01:00Z",
             "message": ["role": "assistant", "model": "synthetic", "content": [["type": "text", "text": "[Survey](survey.md), [independent](independent.md)"]]]],
        ]
        var log = Data()
        for record in records { log.append(try JSONSerialization.data(withJSONObject: record)); log.append(10) }
        try log.write(to: logs.appendingPathComponent("session.jsonl"))
        let indexer = try Indexer(folders: LibraryFolders(home: home))
        _ = try indexer.run()
        let catalog = try Catalog(home: home)
        let artifacts = try catalog.registry.artifacts()
        let report = try #require(artifacts.first { $0.name == "survey.md" }?.latest.id)
        let independent = try #require(artifacts.first { $0.name == "independent.md" }?.latest.id)
        let substring = try SectionLookup.evaluate(catalog: catalog, delivery: report, query: "R1", policy: .titleSubstring)
        let exact = try SectionLookup.evaluate(catalog: catalog, delivery: report, query: "R1", policy: .exactIdentifier)
        #expect(substring.sections.count == 3 && exact.sections.count == 2)
        #expect(exact.sections.allSatisfy { $0.title.hasPrefix("R1:") })
        #expect(Set(exact.sections.map(\.id)).count == 2) // ambiguity remains explicit within one report
        let other = try SectionLookup.evaluate(catalog: catalog, delivery: independent, query: "R1", policy: .exactIdentifier)
        #expect(Set(exact.sections.map(\.id)).isDisjoint(with: other.sections.map(\.id)))
        #expect(try catalog.readSection(report, section: exact.sections[0].id).text == "## R1: Boundary\nUnresolved.\n")
        #expect(try catalog.find(["R1"]).total == 0) // no silent global content index
        #expect(throws: Catalog.Failure.self) {
            try SectionLookup.evaluate(catalog: catalog, delivery: report, query: "R1; run", policy: .exactIdentifier)
        }
    }
}
