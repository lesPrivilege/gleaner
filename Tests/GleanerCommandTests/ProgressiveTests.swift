import Foundation
import GleanerCore
import Testing

extension CommandTests {
    @Test func progressiveCommandsAndMCPReturnIdenticalCoreAnswers() throws {
        try index()
        let catalog = try Catalog(home: home)
        let notes = try id("notes.md")
        let projects = try gleaner(["projects", "--limit", "1"])
        #expect(projects.status == 0)
        #expect(projects.output == (try Catalog.encoder.encode(catalog.projects(limit: 1))) + Data("\n".utf8))
        let outline = try gleaner(["outline", notes, "notes", "--limit", "1"])
        #expect(outline.status == 0)
        let expected = try catalog.outline(notes, terms: ["notes"], limit: 1)
        #expect(outline.output == (try Catalog.encoder.encode(expected)) + Data("\n".utf8))
        let section = try #require(expected.sections.first)
        let read = try gleaner(["section", notes, section.id, "--max", "12"])
        #expect(read.status == 0)
        #expect(read.output == (try Catalog.encoder.encode(catalog.readSection(notes, section: section.id, max: 12))) + Data("\n".utf8))

        let host = try Host(home: home)
        try host.initialize()
        let cases: [(String, [String: Any], [String])] = [
            ("gleaner_projects", ["limit": 1], ["projects", "--limit", "1"]),
            ("gleaner_outline", ["delivery": notes, "terms": ["notes"], "limit": 1], ["outline", notes, "notes", "--limit", "1"]),
            ("gleaner_section", ["delivery": notes, "section": section.id, "max": 12], ["section", notes, section.id, "--max", "12"]),
            ("gleaner_find", ["terms": ["release"], "limit": 1, "offset": 1, "generation": 1], ["find", "release", "--limit", "1", "--offset", "1", "--generation", "1"]),
        ]
        for (name, arguments, argv) in cases {
            let result = try call(host, name, arguments)
            let command = try command(argv)
            #expect(result.structured && !result.isError && command.status == 0)
            #expect(same(result.json, command.json))
        }
        try host.close()
    }

    @Test func progressiveRefusalsCarryTheSameEvidenceAcrossAdapters() throws {
        try index()
        let notes = try id("notes.md")
        let host = try Host(home: home)
        try host.initialize()
        let cases: [(String, [String: Any], [String], String)] = [
            ("gleaner_section", ["delivery": notes, "section": "R1"], ["section", notes, "R1"], "section_not_found"),
            ("gleaner_projects", ["generation": 0], ["projects", "--generation", "0"], "stale_index"),
            ("gleaner_outline", ["delivery": notes, "offset": -1], ["outline", notes, "--offset=-1"], "usage"),
            ("gleaner_projects", ["limit": 1001], ["projects", "--limit", "1001"], "usage"),
        ]
        for (name, arguments, argv, kind) in cases {
            let result = try call(host, name, arguments)
            let command = try command(argv)
            #expect(result.isError && command.status != 0)
            #expect(same(result.json, command.json))
            #expect((result.json["error"] as? [String: Any])?["kind"] as? String == kind)
            #expect((result.json["index"] as? [String: Any])?["generation"] as? Int == 1)
        }
        try host.close()
    }
}
