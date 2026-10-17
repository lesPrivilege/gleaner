import Foundation
import Testing
@testable import GleanerCore

/// A project is the repository a file belongs to, named by its folder (SPEC §5).
@Suite struct ProjectTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-projects-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A git repository with one commit, so worktrees can be added to it.
    func repository(_ relative: String) throws -> String {
        let path = root.appendingPathComponent(relative).path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try "x".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init"]
        for args in [["init", "-q"], ["add", "."], commit] {
            #expect(Locator.run(["-C", path] + args).status == 0)
        }
        return path
    }

    func artifact(_ path: String, cwd: String) -> Artifact {
        Artifact(path: path, deliveries: [Delivery(
            id: "d", number: 1, path: path, deliveredAt: nil, provider: .claudeCode, sessionTitle: nil,
            request: nil, cwd: cwd, evidence: [], logPath: "", capture: nil)])
    }

    @Test func repositoriesWithTheSameNameStayTwoProjects() throws {
        let a = try repository("client-a/app"), b = try repository("client-b/app")
        let first = artifact(a + "/out/report.md", cwd: a), second = artifact(b + "/out/report.md", cwd: b)
        #expect(first.project == "app" && second.project == "app")
        #expect(first.projectFolder != second.projectFolder)
        #expect(first.inRepository && second.inRepository)
    }

    @Test func projectsWithTheSameNameAreShownWithTheirParentFolder() {
        let names = Projects.names(["/u/client-a/app", "/u/client-b/app", "/u/Praxis", "/u/client-a/app"])
        #expect(names == ["/u/client-a/app": "client-a/app", "/u/client-b/app": "client-b/app", "/u/Praxis": "Praxis"])
    }

    @Test func aDeletedExternalWorktreeKeepsItsProjectAfterARestart() throws {
        let fm = FileManager.default
        let atlas = try repository("Atlas")
        let worktree = root.appendingPathComponent("atlas-feature")
        #expect(Locator.run(["-C", atlas, "worktree", "add", "-q", worktree.path]).status == 0)
        try fm.createDirectory(at: worktree.appendingPathComponent("out"), withIntermediateDirectories: true)
        try "r1".write(to: worktree.appendingPathComponent("out/report.md"), atomically: true, encoding: .utf8)
        let logs = root.appendingPathComponent("claude/-atlas-feature")
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        let reply = #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"text","text":"Report: [report](out/report.md)"}]},"timestamp":"2026-10-17T00:00:00.000Z","cwd":"\#(worktree.path)","sessionId":"s1"}"#
        try (reply + "\n").write(to: logs.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)

        let registryPath = root.appendingPathComponent("registry.sqlite").path
        let sources = LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex"))
        let store = ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging"))
        _ = try Indexer(registry: try Registry(path: registryPath), store: store, sources: sources).run()
        #expect(try Registry(path: registryPath).artifacts().first?.project == "Atlas")

        // The worktree is removed, an unrelated repository now encloses the folder it was in, and
        // Gleaner starts again: nothing on disk leads back to Atlas.
        try fm.removeItem(at: worktree)
        #expect(Locator.run(["-C", atlas, "worktree", "prune"]).status == 0)
        #expect(Locator.run(["-C", root.path, "init", "-q"]).status == 0)
        Projects.forgetRepositories()
        let restarted = try #require(try Registry(path: registryPath).artifacts().first)
        #expect(restarted.project == "Atlas")
        #expect(restarted.inRepository)

        // Rereading the log resolves worse; what was recorded at delivery stands.
        let registry = try Registry(path: registryPath)
        try registry.db.execute("PRAGMA user_version = 1")
        _ = try Indexer(registry: try Registry(path: registryPath), store: store, sources: sources).run()
        Projects.forgetRepositories()
        #expect(try registry.artifacts().first?.project == "Atlas")
    }

    @Test func aFileOutsideGitIsNamedAfterItsFolder() {
        let notes = artifact(root.path + "/notes/plan.md", cwd: root.path + "/notes")
        #expect(notes.project == "notes")
        #expect(notes.projectFolder == root.path + "/notes")
        #expect(!notes.inRepository)
    }
}
