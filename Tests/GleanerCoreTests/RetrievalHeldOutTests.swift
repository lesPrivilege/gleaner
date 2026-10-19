import Foundation
import Testing
@testable import GleanerCore

/// Authored independently before the retrieval implementation was frozen. These are
/// synthetic records in already-supported shapes, not new provider schema fixtures.
@Suite struct RetrievalHeldOutTests {
    let home: URL
    let project: URL
    let indexer: Indexer
    let first = Date(timeIntervalSince1970: 1_920_000_000)

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-heldout-\(UUID().uuidString)")
        project = home.appendingPathComponent("Workspaces/CivicSurvey")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/projects/synthetic"), withIntermediateDirectories: true)
        indexer = try Indexer(folders: LibraryFolders(home: home))
    }

    @discardableResult
    func file(_ path: String, _ text: String) throws -> String {
        let url = project.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: first.addingTimeInterval(-10)], ofItemAtPath: url.path)
        return url.path
    }

    @discardableResult
    func log(_ name: String, request: String, reply: String, at: Date? = nil, append: Bool = false) throws -> URL {
        let url = home.appendingPathComponent(".claude/projects/synthetic/\(name).jsonl")
        let stamp = (at ?? first).formatted(.iso8601)
        let records: [[String: Any]] = [
            ["type": "user", "sessionId": name, "cwd": project.path, "timestamp": stamp,
             "origin": ["kind": "human"], "message": ["role": "user", "content": request]],
            ["type": "assistant", "sessionId": name, "cwd": project.path, "timestamp": stamp,
             "message": ["role": "assistant", "model": "synthetic", "content": [["type": "text", "text": reply]]]],
        ]
        var bytes = append ? ((try? Data(contentsOf: url)) ?? Data()) : Data()
        for record in records {
            bytes.append(try JSONSerialization.data(withJSONObject: record))
            bytes.append(10)
        }
        try bytes.write(to: url)
        return url
    }

    func run(_ date: Date? = nil) throws {
        _ = try indexer.run(now: { date ?? first.addingTimeInterval(20) })
    }

    @Test func correctionsAndByteBoundReviewSurviveRepeatedDerivation() throws {
        let earlier = try file("deliverables/survey-draft.md", "First survey edition\n")
        let final = try file("deliverables/survey-final.md", "Reviewed survey edition\n")
        let log = try log("survey", request: "Supply the surveyed curb heights",
                          reply: "[Draft](deliverables/survey-draft.md), [final](deliverables/survey-final.md)")
        try run()
        let registry = indexer.registry
        let original = try #require(try registry.artifacts().first { $0.path == final }?.latest)
        let project = try registry.addProject(named: "Access review", at: first, moving: [final])
        try registry.correct(.sameWork, subject: earlier, target: final, at: first)
        let review = try indexer.review(final, as: .approved, note: "Correct elevation datum", at: first)
        let corrections = try registry.corrections()

        // Exercise extractor invalidation plus a log's repeated derivation. User-authored
        // state must not be treated as disposable index rows.
        try registry.db.execute("UPDATE log_files SET mtime = -1")
        try run(first.addingTimeInterval(60))
        var source = try Data(contentsOf: log)
        source.append(Data("{malformed synthetic record\n".utf8))
        try source.write(to: log)
        try run(first.addingTimeInterval(120))

        #expect(try registry.corrections() == corrections)
        #expect(try registry.reviews() == [review])
        #expect(try registry.userProjects().map(\.key) == [project.key])
        let captured = try #require(try registry.artifacts().first { $0.path == final }?.latest)
        #expect(captured.id == original.id && captured.capture == original.capture)
        let found = try Catalog(home: home).find(["survey"], project: project.name)
        #expect(found.total == 1)
    }

    @Test func simultaneousSessionsKeepSeparateReplyEvidenceWithoutCombiningRequests() throws {
        let path = try file("inspection/bridge.md", "Shared inspection report\n")
        try log("structural", request: "Assess the rivets", reply: "[Inspection](inspection/bridge.md)")
        try log("accessibility", request: "Assess the ramp", reply: "[Inspection](inspection/bridge.md)")
        try run()
        let artifact = try #require(try indexer.registry.artifacts().first { $0.path == path })
        #expect(artifact.deliveries.count == 2)
        #expect(Set(artifact.deliveries.map(\.sessionID)).count == 2)
        #expect(Set(artifact.deliveries.map(\.logPath)).count == 2)
        // A shared path/hash/time does not establish one combined conversation or claim.
        #expect(try Catalog(home: home).find(["rivets", "ramp"]).total == 0)
        #expect(try Catalog(home: home).find(["rivets"]).results.first?.request == "Assess the rivets")
        #expect(try Catalog(home: home).find(["ramp"]).results.first?.request == "Assess the ramp")
    }

    @Test func deliveredDirectoryDoesNotAuthorizeFollowingAnExternalSymlink() throws {
        let safe = try file("deliverables/final-layout.svg", "<svg>final layout</svg>\n")
        let outside = home.appendingPathComponent("unrelated-client")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("Unrelated synthetic contract\n".utf8).write(to: outside.appendingPathComponent("contract.md"))
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("deliverables/shortcut"), withDestinationURL: outside)
        try log("layout", request: "Hand over the layout", reply: "[Delivery folder](deliverables/)")
        try run()
        let artifacts = try indexer.registry.artifacts()
        #expect(artifacts.contains { $0.path == safe })
        #expect(!artifacts.contains { $0.name == "contract.md" })
    }

    @Test func duplicateMentionsDoNotMakeDuplicateReviewObjectsOrChangeEvidenceAnchors() throws {
        let path = try file("appendices/tidal-window.txt", "Low water at noon\n")
        try log("tides", request: "Prepare the tidal window appendix",
                reply: "[Appendix](appendices/tidal-window.txt), repeated [appendix](appendices/tidal-window.txt).")
        try run()
        let artifact = try #require(try indexer.registry.artifacts().first { $0.path == path })
        #expect(artifact.deliveries.count == 1)
        #expect(artifact.latest.evidence.count == 2)
        #expect(Set(artifact.latest.evidence.map(\.line)) == [2])
        let catalog = try Catalog(home: home)
        #expect(try catalog.find(["tidal"]).total == 1)
        #expect(try catalog.resolve(artifact.latest.id).reference.evidence.line == 2)
    }
}
