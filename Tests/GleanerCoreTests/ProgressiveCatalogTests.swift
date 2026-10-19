import Foundation
import Testing
@testable import GleanerCore

extension CatalogTests {
    @Test func projectDiscoveryAndPagingUseTheAppsOrganization() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog()
        let organization = try Organization(shown: catalog.registry.artifacts(), registry: catalog.registry)
        let discovered = try catalog.projects(limit: 1)
        #expect(discovered.index.generation == 1)
        #expect(discovered.total == organization.projects.count)
        #expect(discovered.results.map(\.key) == organization.projects.prefix(1).map(\.key))
        let result = try #require(discovered.results.first)
        #expect(result.origin == .folder && result.checkouts.isEmpty)
        #expect(result.works == 3 && result.files == 3 && result.deliveries == 3)
        let core = organization.search([]).map { $0.matched.id }
        let first = try catalog.find([], project: result.key, limit: 1)
        let second = try catalog.find([], project: result.key, limit: 1, offset: 1, generation: first.index.generation)
        #expect((first.results + second.results).map { $0.reference.delivery } == Array(core.prefix(2)))
        #expect(first.truncated && second.truncated)
        #expect(try catalog.find([], offset: Int.max).results.isEmpty)
        #expect(try catalog.projects(offset: Int.max).results.isEmpty)
        #expect(throws: Catalog.Failure.self) { try catalog.projects(limit: Catalog.pageLimit + 1) }
        #expect(throws: Catalog.Failure.self) { try catalog.find([], offset: -1) }
        try index(at: delivered.addingTimeInterval(40))
        #expect(throws: Catalog.Failure.staleIndex(expected: 1, found: 2)) {
            try catalog.projects(offset: 1, generation: 1)
        }
        #expect(throws: Catalog.Failure.staleIndex(expected: 1, found: 2)) {
            try catalog.find([], offset: 1, generation: 1)
        }
    }

    @Test func findingSectionsHaveExactScopedIdentityAndOriginalRanges() throws {
        let report = "# Review\r\nContext.\r\n## R1 — café\r\nEvidence, no ruling.\r\n### Detail\r\nmore\r\n## R3\r\nUnresolved.\r\n"
        try write(Data(report.utf8), to: "out/notes.md", modified: delivered.addingTimeInterval(-30))
        // Same bytes in a different report keep separate logical context.
        try write(Data(report.utf8), to: "out/second.md", modified: delivered.addingTimeInterval(-30))
        try appendLog([
            user("A second review", at: delivered.addingTimeInterval(5)),
            assistant("[Second](out/second.md)", at: delivered.addingTimeInterval(10)),
        ])
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog()
        let notes = try id("notes.md", in: catalog), second = try id("second.md", in: catalog)
        let outline = try catalog.outline(notes, limit: 2)
        #expect(outline.total == 4 && outline.nextOffset == 2)
        let rest = try catalog.outline(notes, offset: 2)
        #expect(rest.sections.map(\.title) == ["Detail", "R3"] && rest.nextOffset == nil)
        let r1 = try #require(try catalog.outline(notes, terms: ["r1"]).sections.first)
        let other = try #require(try catalog.outline(second, terms: ["R1"]).sections.first)
        #expect(r1.id != other.id)
        let exact = try catalog.readSection(notes, section: r1.id)
        #expect(exact.text == "## R1 — café\r\nEvidence, no ruling.\r\n### Detail\r\nmore\r\n")
        #expect(exact.reference == outline.reference && exact.range == r1.range)
        #expect(exact.text == String(decoding: Array(report.utf8)[r1.range], as: UTF8.self))
        #expect(throws: Catalog.Failure.sectionNotFound(r1.id)) { try catalog.readSection(second, section: r1.id) }
        #expect(throws: Catalog.Failure.sectionNotFound("R1")) { try catalog.readSection(notes, section: "R1") }
        let short = try catalog.readSection(notes, section: r1.id, max: 9)
        #expect(short.truncated && short.text == "## R1 —")
        let continuation = try catalog.read(notes, span: .bytes(short.range.upperBound, r1.range.upperBound))
        #expect(short.text + continuation.text == exact.text)
        #expect(try catalog.outline(notes, terms: ["ruling"]).total == 0) // headings only, never inferred decisions
    }

    @Test func sectionsKeepDeliveredBytesWhenOriginalIsChangedOrMissing() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog(), notes = try id("notes.md", in: catalog)
        let before = try catalog.outline(notes)
        let section = try #require(before.sections.first)
        try write(Data("# Replacement\nnot the captured notes\n".utf8), to: "out/notes.md", modified: delivered.addingTimeInterval(30))
        let changed = try catalog.readSection(notes, section: section.id)
        #expect(changed.text.hasPrefix("# Notes\n"))
        #expect(changed.reference.availability.state == .savedCopy)
        #expect(try catalog.outline(notes).sections == before.sections)
        try FileManager.default.removeItem(at: project.appendingPathComponent("out/notes.md"))
        #expect(try catalog.readSection(notes, section: section.id).text == changed.text)
        try FileManager.default.removeItem(at: catalog.store.objectURL(try #require(before.reference.sha256)))
        #expect(throws: Catalog.Failure.unavailable(.savedCopyMissing)) { try catalog.outline(notes) }
    }

    @Test func outlineIsCompleteOrExplicitlyRefusedAndNeverMutatesTheLibrary() throws {
        try index(at: delivered.addingTimeInterval(20))
        let catalog = try catalog(), before = try bytes(library), files = try projectFiles()
        let notes = try id("notes.md", in: catalog)
        _ = try catalog.projects()
        let section = try #require(try catalog.outline(notes).sections.first)
        _ = try catalog.readSection(notes, section: section.id)
        #expect(try bytes(library) == before && projectFiles() == files)
        #expect(throws: Catalog.Failure.notText) { try catalog.outline(id("frame.png", in: catalog)) }
        #expect(throws: Catalog.Failure.self) { try catalog.outline(notes, offset: -1) }
        #expect(throws: Catalog.Failure.self) { try catalog.readSection(notes, section: section.id, max: Int.max) }
        try write(Data(("# Huge\n" + String(repeating: "x", count: Catalog.outlineByteLimit)).utf8), to: "out/huge.md", modified: delivered)
        try appendLog([
            user("Large output", at: delivered.addingTimeInterval(5)),
            assistant("[Huge](out/huge.md)", at: delivered.addingTimeInterval(10)),
        ])
        try index(at: delivered.addingTimeInterval(40))
        #expect(throws: Catalog.Failure.self) { try catalog.outline(id("huge.md", in: catalog)) }
    }
}

@Suite struct DocumentHeadingsTests {
    @Test func sourceStructureIgnoresFencedAndIndentedExamples() {
        let source = "# Report\n```md\n## Fake\n```\n    # Also fake\nReal finding\n------------\ntext\n~~~\n# More fake\n~~~\n## Last ###\nbody"
        let headings = DocumentHeadings.parse(source)
        #expect(headings.map(\.title) == ["Report", "Real finding", "Last"])
        #expect(headings.map(\.level) == [1, 2, 2])
        #expect(headings[0].range == 0..<source.utf8.count)
        #expect(String(decoding: Array(source.utf8)[headings[1].range], as: UTF8.self).hasPrefix("Real finding\n------------\n"))
    }

    @Test func duplicateHeadingsHaveDifferentRangesAndEmptyTextHasNone() {
        let headings = DocumentHeadings.parse("## R1\nfirst\n## R1\nsecond\n")
        #expect(headings.count == 2 && headings[0].range != headings[1].range)
        #expect(DocumentHeadings.parse("").isEmpty)
        #expect(DocumentHeadings.parse("a document without headings").isEmpty)
    }
}
