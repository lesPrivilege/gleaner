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
        #expect(restarted.place == "worktree atlas-feature")

        // Rereading the log resolves worse; what was recorded at delivery stands.
        let registry = try Registry(path: registryPath)
        try registry.db.execute("PRAGMA user_version = 1")
        _ = try Indexer(registry: try Registry(path: registryPath), store: store, sources: sources).run()
        Projects.forgetRepositories()
        #expect(try registry.artifacts().first?.project == "Atlas")
    }

    // MARK: The checkout recorded while a worktree was there (SPEC §5)

    /// Atlas with `out/report.md` committed on branch ch3 in its worktree `.claude/worktrees/ch3`.
    func atlasWithAReportInWorktreeCh3() throws -> (atlas: String, worktree: String) {
        let atlas = try repository("Atlas"), worktree = atlas + "/.claude/worktrees/ch3"
        #expect(Locator.run(["-C", atlas, "worktree", "add", "-q", "-b", "ch3", worktree]).status == 0)
        try FileManager.default.createDirectory(atPath: worktree + "/out", withIntermediateDirectories: true)
        try "r1".write(toFile: worktree + "/out/report.md", atomically: true, encoding: .utf8)
        let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "report"]
        for args in [["add", "."], commit] { #expect(Locator.run(["-C", worktree] + args).status == 0) }
        return (atlas, worktree)
    }

    /// A request and its reply from `cwd`, as lines of session s1's log.
    func turn(_ reply: String, cwd: String, at time: String) -> [String] {
        [#"{"type":"user","message":{"role":"user","content":"Write the report"},"origin":{"kind":"human"},"timestamp":"2026-10-17T\#(time).000Z","cwd":"\#(cwd)","sessionId":"s1"}"#,
         #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"text","text":"\#(reply)"}]},"timestamp":"2026-10-17T\#(time).500Z","cwd":"\#(cwd)","sessionId":"s1"}"#]
    }

    /// Writes session s1's log, then reads the logs as a fresh launch of Gleaner would.
    func index(_ lines: [String]) throws -> Registry {
        let logs = root.appendingPathComponent("claude/-ch3")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: logs.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)
        let registry = try Registry(path: root.appendingPathComponent("registry.sqlite").path)
        _ = try Indexer(
            registry: registry,
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex"))).run()
        return registry
    }

    @Test func aDeliveryReadAfterItsWorktreeIsGoneLeavesTheRecordedCheckoutStanding() throws {
        let (atlas, worktree) = try atlasWithAReportInWorktreeCh3()
        let first = turn("Report: [report](out/report.md)", cwd: worktree, at: "00:00:00")
        _ = try index(first)

        // Delivered again while Gleaner is closed, and the worktree removed before it starts again.
        #expect(Locator.run(["-C", atlas, "worktree", "remove", worktree]).status == 0)
        Projects.forgetRepositories()
        let report = try #require(try index(first + turn("Again: [report](out/report.md)", cwd: worktree, at: "01:00:00"))
            .artifacts().first)
        #expect(report.deliveries.count == 2)
        #expect(report.checkout == Checkout(folder: worktree, repository: atlas))
        #expect(report.place == "worktree ch3")
        #expect(Locator.observe(report.path, checkout: report.checkout).git == .recoverableFromHistory)
    }

    @Test func aDeliveryAdmittedAgainAfterItsWorktreeIsGoneGetsItsRecordedCheckoutBack() throws {
        let (atlas, worktree) = try atlasWithAReportInWorktreeCh3()
        let delivery = turn("Report: [report](out/report.md)", cwd: worktree, at: "00:00:00")
        _ = try index(delivery)
        // Reread under a rule that no longer admits it (a link written inside inline code).
        #expect(try index(turn("Report: `[report](out/report.md)`", cwd: worktree, at: "00:00:00")).artifacts().isEmpty)

        // The worktree is removed, Gleaner starts again, and the log admits the delivery again.
        #expect(Locator.run(["-C", atlas, "worktree", "remove", worktree]).status == 0)
        Projects.forgetRepositories()
        let report = try #require(try index(delivery + turn("Anything else?", cwd: worktree, at: "00:10:00")).artifacts().first)
        #expect(report.checkout == Checkout(folder: worktree, repository: atlas))
        #expect(Locator.observe(report.path, checkout: report.checkout).git == .recoverableFromHistory)
    }

    @Test func aWorktreeIsNamedAsOneWhereverItIsKept() throws {
        let atlas = try repository("Atlas")
        let external = root.appendingPathComponent("atlas-feature").path, inside = atlas + "/.claude/worktrees/ch3"
        for worktree in [external, inside] {
            #expect(Locator.run(["-C", atlas, "worktree", "add", "-q", "--detach", worktree]).status == 0)
        }
        #expect(artifact(external + "/out/report.md", cwd: external).place == "worktree atlas-feature")
        #expect(artifact(inside + "/out/report.md", cwd: inside).place == "worktree ch3")
        #expect(!artifact(atlas + "/out/report.md", cwd: atlas).inWorktree)
        // Outside git there is no worktree, whatever the folders are called.
        #expect(!artifact(root.path + "/notes/.claude/worktrees/x/plan.md", cwd: root.path + "/notes").inWorktree)
    }

    @Test func worktreesOfABareRepositoryFoldIntoIt() throws {
        let source = try repository("source")
        let bare = root.appendingPathComponent("app.git").path
        #expect(Locator.run(["clone", "-q", "--bare", source, bare]).status == 0)
        let main = root.appendingPathComponent("app-main").path, feature = root.appendingPathComponent("app-feature").path
        #expect(Locator.run(["-C", bare, "worktree", "add", "-q", main]).status == 0)
        #expect(Locator.run(["-C", bare, "worktree", "add", "-q", "--detach", feature]).status == 0)
        let a = artifact(main + "/out/report.md", cwd: main), b = artifact(feature + "/out/report.md", cwd: feature)
        #expect(a.projectFolder == bare && b.projectFolder == bare)
        #expect(a.project == "app" && Projects.names([bare]) == [bare: "app"])

        // The same layout kept in one folder: the bare repository in `.bare`, its worktrees beside it.
        let folder = root.appendingPathComponent("tool").path
        #expect(Locator.run(["clone", "-q", "--bare", source, folder + "/.bare"]).status == 0)
        try "gitdir: ./.bare\n".write(toFile: folder + "/.git", atomically: true, encoding: .utf8)
        #expect(Locator.run(["-C", folder, "worktree", "add", "-q", folder + "/main"]).status == 0)
        let c = artifact(folder + "/main/out/report.md", cwd: folder + "/main")
        #expect(c.projectFolder == folder && c.project == "tool")
    }

    @Test func aFolderUnderPrivateIsOneProjectWithWhatItsAgentDelivered() throws {
        // An agent records the folder it works in as the system resolves it, /private/var/folders/…
        // for what Foundation calls /var/folders/…. Its reply links a file there, one not yet
        // written, and one outside git.
        let atlas = try repository("Atlas")
        let cwd = LogWatcher.resolved(atlas)
        try #require(cwd.hasPrefix("/private/") && !atlas.hasPrefix("/private/"))
        try FileManager.default.createDirectory(atPath: atlas + "/out", withIntermediateDirectories: true)
        try "r1".write(toFile: atlas + "/out/report.md", atomically: true, encoding: .utf8)
        let reply = "Report: [report](out/report.md). Notes: [notes](out/notes.md). Plan: [plan](../plan.md)"
        let artifacts = try index(turn(reply, cwd: cwd, at: "00:00:00")).artifacts().sorted { $0.path < $1.path }

        // The files, the folder the agent worked in and the project take one form.
        #expect(artifacts.map(\.path) == [atlas + "/out/notes.md", atlas + "/out/report.md", root.path + "/plan.md"])
        #expect(artifacts.map(\.latest.cwd) == [atlas, atlas, atlas])
        #expect(artifacts.map(\.projectFolder) == [atlas, atlas, atlas])
        #expect(artifacts.map(\.project) == ["Atlas", "Atlas", "Atlas"])
        #expect(artifacts.map(\.folder) == ["out", "out", (root.path as NSString).abbreviatingWithTildeInPath])
    }

    @Test func aFileOutsideGitIsNamedAfterItsFolder() {
        let notes = artifact(root.path + "/notes/plan.md", cwd: root.path + "/notes")
        #expect(notes.project == "notes")
        #expect(notes.projectFolder == root.path + "/notes")
        #expect(!notes.inRepository)
    }

    /// A path keeps one spelling whether or not it exists: `/private/var` and `/private/tmp` read
    /// as `/var` and `/tmp`, for a delivered file that is gone and for the folder the agent worked in.
    @Test func aFolderUnderPrivateVarIsOneProjectWithItsFilesThereOrGone() throws {
        let board = "/private" + FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-board-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: board + "/charts", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: board) }
        try Data("chart".utf8).write(to: URL(fileURLWithPath: board + "/charts/revenue.png"))
        let there = Paths.standard(board + "/charts/revenue.png"), gone = Paths.standard(board + "/charts/gone.png")
        #expect(there.hasPrefix("/var/") && gone.hasPrefix("/var/"))
        #expect(Projects.folder(path: there, cwd: board) == Paths.standard(board))
        #expect(Projects.folder(path: gone, cwd: board) == Paths.standard(board))
        #expect(Paths.standard("/private/tmp/a/../b.md") == "/tmp/b.md")
        // The repository an agent worked in, reached through its cwd, is the one its own files are in.
        let repo = board + "/app"
        try FileManager.default.createDirectory(atPath: repo + "/.git", withIntermediateDirectories: true)
        Projects.forgetRepositories()
        #expect(Projects.repository(path: there, cwd: repo) == Projects.repository(path: Paths.standard(repo + "/report.md"), cwd: nil))
        #expect(Projects.repository(path: there, cwd: repo) == Paths.standard(repo))
        #expect(Paths.standard("/private/varnish/x") == "/private/varnish/x")
    }
}
