import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Gleaner
@testable import GleanerCore

/// The library window's decisions on a synthetic machine: which delivery a click lands on, which
/// bytes Quick Look and Compare show, and what stays shown when a read fails.
@MainActor @Suite struct LibraryModelTests {
    let root: URL
    let project: URL
    let indexer: Indexer
    let delivered = Date(timeIntervalSince1970: 1_790_000_000)

    /// A video delivered three times (1 and 2 the same bytes, 1 first seen later, 3 new bytes), and
    /// notes delivered with the first.
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-model-\(UUID().uuidString)")
        project = root.appendingPathComponent("Praxis")
        let fm = FileManager.default
        try fm.createDirectory(at: project.appendingPathComponent("out"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("claude/-Praxis"), withIntermediateDirectories: true)
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))

        let second = delivered.addingTimeInterval(3600), third = delivered.addingTimeInterval(7200)
        try write("video v1", to: "out/demo.mp4", modified: delivered.addingTimeInterval(-30))
        try write("notes n1", to: "out/notes.md", modified: delivered.addingTimeInterval(-30))
        try appendLog([
            user("Make the demo video", at: delivered.addingTimeInterval(-600)),
            assistant("Video: [demo](out/demo.mp4). Notes: [notes](out/notes.md)", at: delivered),
            user("Render it again", at: second.addingTimeInterval(-300)),
            assistant("Rendered again: [demo](out/demo.mp4)", at: second),
        ])
        _ = try indexer.run(now: { second.addingTimeInterval(20) })
        try write("video v2", to: "out/demo.mp4", modified: third.addingTimeInterval(-30))
        try appendLog([
            user("Make it shorter", at: third.addingTimeInterval(-300)),
            assistant("Shorter: [demo](out/demo.mp4)", at: third),
        ])
        _ = try indexer.run(now: { third.addingTimeInterval(20) })
    }

    // MARK: helpers

    func write(_ text: String, to relative: String, modified: Date) throws {
        let url = project.appendingPathComponent(relative)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    func appendLog(_ lines: [String]) throws {
        let url = root.appendingPathComponent("claude/-Praxis/session-1.jsonl")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try (existing + lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func stamp(_ date: Date) -> String { date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }

    func user(_ text: String, at date: Date) -> String {
        #"{"type":"user","message":{"role":"user","content":"\#(text)"},"origin":{"kind":"human"},"timestamp":"\#(stamp(date))","cwd":"\#(project.path)","sessionId":"s1"}"#
    }

    func assistant(_ text: String, at date: Date) -> String {
        #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"text","text":"\#(text)"}]},"timestamp":"\#(stamp(date))","cwd":"\#(project.path)","sessionId":"s1"}"#
    }

    func artifact(_ model: LibraryModel, _ name: String) throws -> Artifact {
        try #require(model.artifacts.first { $0.name == name })
    }

    /// The video selected and checked, as the detail view does.
    func selectVideo(_ model: LibraryModel) async throws -> Artifact {
        let video = try artifact(model, "demo.mp4")
        model.selection = video.path
        await model.observe(video)
        return video
    }

    func text(_ url: URL?) throws -> String {
        try String(contentsOf: try #require(url), encoding: .utf8)
    }

    /// Rereads the logs and waits until `done` holds.
    func reindex(_ model: LibraryModel, until done: () -> Bool) async throws {
        model.reindex()
        for _ in 0..<300 where !done() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(done())
    }

    // MARK: Reading the logs (N3)

    @Test func aFailedReadKeepsShowingTheLibrary() async throws {
        let model = LibraryModel(indexer: indexer)
        try await reindex(model) { model.sources != nil }
        let shown = model.artifacts.map(\.path)
        #expect(shown.count == 2)
        // Neither the logs' read markers nor the library can be read now.
        try indexer.registry.db.execute("DROP TABLE log_files; DROP TABLE captures;")
        try await reindex(model) { model.indexFailure != nil }
        #expect(model.artifacts.map(\.path) == shown)
    }

    @Test func aFailedRunNeverClaimsTheLogsWereRead() async throws {
        let model = LibraryModel(indexer: indexer)
        try await reindex(model) { model.sources != nil }
        try indexer.registry.db.execute("DROP TABLE log_files;")
        try await reindex(model) { model.indexFailure != nil }
        #expect(model.sources == nil)
        #expect(model.logTrouble?.hasPrefix("Indexing failed") == true)
    }

    @Test func unknownRecordTypesAreReportedButNotOfferedForAnotherRead() async throws {
        try appendLog([#"{"type":"brand-new-record","sessionId":"s1"}"#])
        let model = LibraryModel(indexer: indexer)
        try await reindex(model) { model.sources != nil }
        #expect(model.logTrouble == "Claude Code: read with problems (1 unknown record type)")
        // Reading again can't change which record types Gleaner knows.
        #expect(!model.canReadAgain)

        // A log with malformed lines can read whole next time.
        try appendLog(["{not json"])
        try await reindex(model) { model.sources?[.claudeCode]?.partialLogs.isEmpty == false }
        #expect(model.canReadAgain)
    }

    // MARK: Files Gleaner couldn't read (A2)

    /// A file delivered after the others, by itself, then indexed.
    func deliver(_ relative: String) throws {
        let fourth = delivered.addingTimeInterval(9000)
        try appendLog([
            user("One more file", at: fourth.addingTimeInterval(-60)),
            assistant("Here: [file](\(relative))", at: fourth),
        ])
        _ = try indexer.run(now: { fourth.addingTimeInterval(20) })
    }

    @Test func checkingAFileGleanerNeverReadCompletesItsCapture() async throws {
        let chart = project.appendingPathComponent("out/chart.png").path
        try write("chart c1", to: "out/chart.png", modified: delivered)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: chart)
        try deliver("out/chart.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: chart)

        let model = LibraryModel(indexer: indexer)
        let unread = try artifact(model, "chart.png")
        #expect(unread.latest.sha256 == nil)
        model.selection = unread.path
        await model.observe(unread)
        // The check was Gleaner's first read of it: the library now holds those bytes, first seen later.
        let read = try artifact(model, "chart.png")
        #expect(read.latest.capture?.provenance == .firstSeenAfterDelivery)
        #expect(read.latest.sha256 != nil)
        #expect(read.latest.sha256 == model.observations[chart]?.state.sha256)
    }

    @Test func aFileGleanerCannotReachIsNeverListedAsMissing() throws {
        let locked = project.appendingPathComponent("out/locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try write("table t1", to: "out/locked/table.csv", modified: delivered)
        try deliver("out/locked/table.csv")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let model = LibraryModel(indexer: indexer)
        #expect(!model.missing.contains(try artifact(model, "table.csv").path))
    }

    @Test func showFolderSaysWhenTheFolderIsGoneToo() throws {
        let folder = project.appendingPathComponent("out/charts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write("chart c1", to: "out/charts/chart.png", modified: delivered)
        try deliver("out/charts/chart.png")
        try FileManager.default.removeItem(at: folder)

        // Pressed on a row that isn't selected: the file's panel opens and says why nothing showed.
        let model = LibraryModel(indexer: indexer)
        let chart = try artifact(model, "chart.png")
        model.reveal(chart)
        #expect(model.selection == chart.path)
        #expect(model.actionFailure(chart, chart.latest) == "Its folder isn’t on disk either: \(folder.path)")
    }

    // MARK: Delivered with (D6)

    @Test func aFileDeliveredWithAnotherOpensOnItsDeliveryFromThatReply() throws {
        let model = LibraryModel(indexer: indexer)
        let video = try artifact(model, "demo.mp4"), notes = try artifact(model, "notes.md")
        // The notes came with the first render, not the latest.
        let sibling = try #require(model.siblings[notes.latest.id]?.first)
        #expect(sibling.id == video.deliveries[2].id)

        // A filter hides the video: following the link clears it and lands on that delivery.
        model.kind = .document
        model.selection = notes.path
        model.select(sibling)
        #expect(model.kind == nil)
        #expect(model.selected?.artifact.path == video.path)
        #expect(model.selected.map(model.delivery(in:))?.id == sibling.id)
    }

    // MARK: Row drags (A4)

    /// What the app a drag is dropped on receives: the path of its own copy, and the file's text or
    /// the folder's contents, read before the copy is cleaned up.
    func dropped(_ provider: NSItemProvider?) async throws -> (path: String, contents: String) {
        let provider = try #require(provider)
        let type = try #require(provider.registeredTypeIdentifiers.first)
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                continuation.resume(with: Result {
                    guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                    let contents = try (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.sorted().joined(separator: ",")
                        ?? String(contentsOf: url, encoding: .utf8)
                    return (url.path, contents)
                })
            }
        }
    }

    @Test func aRowDragHandsOverTheVersionTheDetailWould() async throws {
        let model = LibraryModel(indexer: indexer)
        let video = try await selectVideo(model)
        // The selected row: the delivery chosen in the detail, not the one the search matched.
        model.chosenDelivery = video.deliveries[1].id
        #expect(try await dropped(model.dragItem(for: try #require(model.selected))).contents == "video v1")
        // Any other row: the delivery it shows.
        let notes = try #require(model.results.first { $0.artifact.name == "notes.md" })
        #expect(try await dropped(model.dragItem(for: notes)).contents == "notes n1")
    }

    @Test func aFolderRowDragsACopyOfTheFolderAsItIsNow() async throws {
        let site = project.appendingPathComponent("out/site")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        try "home".write(to: site.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try deliver("out/site")
        try "about".write(to: site.appendingPathComponent("about.html"), atomically: true, encoding: .utf8)

        let model = LibraryModel(indexer: indexer)
        let row = try #require(model.results.first { $0.artifact.name == "site" })
        let drop = try await dropped(model.dragItem(for: row))
        #expect(drop.contents == "about.html,index.html")
        // The receiver gets its own copy: a drop never moves the project's folder.
        #expect(drop.path != site.path)
        #expect(FileManager.default.fileExists(atPath: site.appendingPathComponent("index.html").path))
    }

    @Test func aRowWithNothingToHandOverStartsNoDrag() async throws {
        // Gone before Gleaner first looked: it never read the bytes.
        try deliver("out/never.mp4")
        // Too large to have been saved, then rebuilt in place, as a check this session found.
        indexer.saveLimit = 0
        try write("build b1", to: "out/app.dmg", modified: delivered.addingTimeInterval(9000))
        try deliver("out/app.dmg")
        try write("build b2", to: "out/app.dmg", modified: Date())
        // Too large to have been saved, then removed.
        try write("clip c1", to: "out/clip.mov", modified: delivered.addingTimeInterval(9000))
        try deliver("out/clip.mov")
        try FileManager.default.removeItem(at: project.appendingPathComponent("out/clip.mov"))

        let model = LibraryModel(indexer: indexer)
        await model.observe(try artifact(model, "app.dmg"))
        for name in ["never.mp4", "app.dmg", "clip.mov"] {
            let row = try #require(model.results.first { $0.artifact.name == name })
            #expect(model.dragItem(for: row) == nil, "\(name)")
        }
    }

    // MARK: Quick Look (N1)

    @Test func quickLookShowsOnlyTheSelectedDeliverysPreparedBytes() async throws {
        let model = LibraryModel(indexer: indexer)
        let video = try await selectVideo(model)
        let (third, first) = (video.deliveries[0], video.deliveries[2])
        await model.stage(sha: try #require(third.sha256), artifact: video)
        model.toggleQuickLook()
        #expect(try text(model.quickLookURL) == "video v2")

        // Another version is picked: until its bytes are prepared, Quick Look has nothing to show.
        model.chosenDelivery = first.id
        #expect(model.quickLookURL == nil)
        await model.stage(sha: try #require(first.sha256), artifact: video)
        #expect(try text(model.quickLookURL) == "video v1")
    }

    @Test func quickLookStaysOnTheSameBytesWhileTheyArePreparedAgain() async throws {
        let model = LibraryModel(indexer: indexer)
        let video = try await selectVideo(model)
        let (second, first) = (video.deliveries[1], video.deliveries[2])
        model.chosenDelivery = second.id
        let sha = try #require(second.sha256)
        await model.stage(sha: sha, artifact: video)
        model.toggleQuickLook()
        let shown = try #require(model.quickLookURL)

        // Delivery 1 is the same bytes: the detail view prepares them again (as it does after a
        // check or Save a Copy), and Quick Look stays on them throughout.
        model.chosenDelivery = first.id
        let preparing = Task { await model.stage(sha: sha, artifact: video) }
        await Task.yield()
        #expect(model.quickLookURL == shown)
        await preparing.value
        #expect(model.quickLookURL == shown)
    }

    // MARK: Compare (D3)

    @Test func aComparisonIsShownOnlyForThePairItWasAskedFor() {
        func end(_ title: String, _ sha: String) -> Comparison.End {
            Comparison.End(title: title, source: "saved copy", sha: sha, url: URL(fileURLWithPath: "/objects/\(sha)"))
        }
        let asked = ComparePane.Request(from: end("Delivery 1", "a"), to: end("Delivery 3", "c"), kind: .media)
        let loaded = (request: asked, content: Comparison.Content.failed("loaded for 1 → 3"))
        #expect(ComparePane.content(loaded, for: asked) == loaded.content)
        #expect(ComparePane.content(loaded, for: ComparePane.Request(from: end("Delivery 2", "a"), to: end("Delivery 3", "c"), kind: .media)) == nil)
        #expect(ComparePane.content(loaded, for: ComparePane.Request(from: end("Delivery 1", "b"), to: end("Delivery 3", "c"), kind: .media)) == nil)
        #expect(ComparePane.content(nil, for: asked) == nil)
    }

    @Test func compareEndsSayWhenBytesWereFirstSeenLater() throws {
        let model = LibraryModel(indexer: indexer)
        let video = try artifact(model, "demo.mp4")
        #expect(video.deliveries[2].capture?.provenance == .firstSeenAfterDelivery)
        #expect(model.compareEnd(video.deliveries[2], artifact: video)?.title == "Delivery 1 (first seen later)")
        #expect(model.compareEnd(video.deliveries[1], artifact: video)?.title == "Delivery 2")
    }

    // MARK: Hand-off copies (N2)

    @Test func clearingHandOffCopiesPreparesTheSelectionAgain() async throws {
        let model = LibraryModel(indexer: indexer)
        let video = try await selectVideo(model)
        let sha = try #require(video.latest.sha256)
        await model.stage(sha: sha, artifact: video)
        let cleared = try #require(model.selectedHandoffURL)
        let generation = model.stagingGeneration
        model.clearHandoffCopies(keeping: pasteboard())
        // The removed copy is never offered again; the new generation makes the detail view
        // prepare the selection again.
        #expect(!FileManager.default.fileExists(atPath: cleared.path))
        #expect(model.selectedHandoffURL == nil)
        #expect(model.stagingGeneration == generation + 1)
        await model.stage(sha: sha, artifact: video)
        #expect(try text(model.selectedHandoffURL) == "video v2")
    }

    /// A clipboard of the test's own, so a test never touches the person's.
    func pasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("gleaner-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    @Test func clearingHandOffCopiesKeepsTheOneOnTheClipboard() async throws {
        let model = LibraryModel(indexer: indexer)
        let video = try await selectVideo(model)
        model.chosenDelivery = video.deliveries[2].id
        await model.stage(sha: try #require(video.deliveries[2].sha256), artifact: video)
        let older = try #require(model.selectedHandoffURL)
        model.chosenDelivery = nil
        await model.stage(sha: try #require(video.latest.sha256), artifact: video)
        let copied = try #require(model.selectedHandoffURL)

        // ⌘C put the latest copy on the clipboard as a file; it is pasted after Clear.
        let clipboard = pasteboard()
        defer { clipboard.releaseGlobally() }
        #expect(clipboard.writeObjects([copied as NSURL]))
        model.clearHandoffCopies(keeping: clipboard)
        #expect(try text(copied) == "video v2")
        #expect(!FileManager.default.fileExists(atPath: older.path))
    }

    // MARK: A deleted worktree

    @Test func aFileCommittedInADeletedWorktreeIsOfferedFromGitAfterARestart() async throws {
        let repo = root.appendingPathComponent("Atlas").path, worktree = repo + "/.claude/worktrees/ch3"
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        try "x".write(toFile: repo + "/README.md", atomically: true, encoding: .utf8)
        let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm"]
        for args in [["init", "-q"], ["add", "."], commit + ["init"], ["worktree", "add", "-q", "-b", "ch3", worktree]] {
            #expect(Locator.run(["-C", repo] + args).status == 0)
        }
        try FileManager.default.createDirectory(atPath: worktree + "/out", withIntermediateDirectories: true)
        try "report r1".write(toFile: worktree + "/out/report.md", atomically: true, encoding: .utf8)
        for args in [["add", "."], commit + ["report"]] { #expect(Locator.run(["-C", worktree] + args).status == 0) }
        let logs = root.appendingPathComponent("claude/-Atlas")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let reply = #"{"type":"assistant","message":{"model":"m","role":"assistant","content":[{"type":"text","text":"Report: [report](out/report.md)"}]},"timestamp":"\#(stamp(Date()))","cwd":"\#(worktree)","sessionId":"s2"}"#
        try (reply + "\n").write(to: logs.appendingPathComponent("s2.jsonl"), atomically: true, encoding: .utf8)
        indexer.saveLimit = 0 // too large to have been saved: only git can bring it back
        _ = try indexer.run()

        // The worktree is removed with its branch kept, and Gleaner starts again.
        #expect(Locator.run(["-C", repo, "worktree", "remove", worktree]).status == 0)
        Projects.forgetRepositories()
        let model = LibraryModel(indexer: indexer)
        let report = try artifact(model, "report.md")
        await model.observe(report)
        let observation = try #require(model.observations[report.path])
        #expect(observation.state.git == .recoverableFromHistory)
        #expect(report.handoff(report.latest, now: observation, hasSaved: indexer.store.has) == .restoreFromGit)
        #expect(observation.state.restoreCommand != nil)
    }
}
