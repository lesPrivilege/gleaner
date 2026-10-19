import AppKit
import Foundation
import Testing
@testable import Gleaner
@testable import GleanerCore

/// A person organizing a non-code project: a report renamed between revisions, a deck, two client
/// projects with the same name. Every decision survives reading the logs again and a relaunch.
@MainActor @Suite struct OrganizingTests {
    let root: URL
    let board: URL
    let indexer: Indexer
    let then = Date(timeIntervalSince1970: 1_792_281_600)
    var log: URL { root.appendingPathComponent("claude/board/s.jsonl") }

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("gleaner-organizing-\(UUID().uuidString)")
        board = root.appendingPathComponent("board")
        for dir in [board.appendingPathComponent("slides"), root.appendingPathComponent("claude/board")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("handoff")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
    }

    func turn(_ request: String, _ reply: String, at: Date) throws {
        func record(_ type: String, _ text: String) throws -> String {
            let content: Any = type == "user" ? text : [["type": "text", "text": text]]
            let object: [String: Any] = ["type": type, "sessionId": "board-session", "cwd": board.path, "origin": ["kind": "human"],
                                         "timestamp": at.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
                                         "message": ["role": type, "content": content]]
            return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
        }
        let existing = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        try (existing + record("user", request) + record("assistant", reply)).write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { at.addingTimeInterval(1) })
    }

    func write(_ text: String, _ name: String, at: Date) throws {
        let url = board.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: at], ofItemAtPath: url.path)
    }

    /// The board report delivered as a draft, then renamed and delivered as final, with a deck.
    func renamedReport() throws {
        try write("# Board report\nDraft.", "board-draft.md", at: then)
        try write("deck", "slides/deck.key", at: then)
        try turn("write the board report and a deck", "[report](board-draft.md) and [deck](slides/deck.key)", at: then)
        let later = then.addingTimeInterval(3600)
        try FileManager.default.moveItem(at: board.appendingPathComponent("board-draft.md"), to: board.appendingPathComponent("board-final.md"))
        try turn("rename it final", "[final](board-final.md)", at: later)
    }

    /// The app as it opens on this library, after its first read.
    func relaunch() -> LibraryModel {
        let model = LibraryModel(indexer: indexer)
        _ = model.organization
        return model
    }

    @Test func aRenamedReportIsSuggestedJoinedAndStaysOneWork() async throws {
        try renamedReport()
        let model = relaunch()
        let draft = board.appendingPathComponent("board-draft.md").path, final = board.appendingPathComponent("board-final.md").path
        // Two files, equal bytes: two works until the person says otherwise, with Gleaner's reason.
        #expect(model.organization.works.count == 3)
        #expect(model.organization.suggestions == [.init(earlier: draft, later: final, reason: .moved)])

        await model.join(draft, final)
        let work = try #require(model.organization.work(containing: final))
        #expect(work.files.map(\.path) == [draft, final])
        #expect(model.organization.suggestions.isEmpty)

        // Read the logs again from scratch, then relaunch: the join stands.
        try indexer.registry.db.execute("PRAGMA user_version = 1")
        let reread = Indexer(registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path), store: indexer.store, sources: indexer.sources)
        _ = try reread.run(now: { then.addingTimeInterval(9999) })
        let again = LibraryModel(indexer: reread)
        let joined = try #require(again.organization.work(containing: draft))
        #expect(joined.files.count == 2)

        // A search for the first request lands on the draft's delivery, inside the one work, and
        // hands over the draft's bytes under the draft's name.
        again.query = "board report"
        let result = try #require(again.results.first { $0.work.id == joined.id })
        #expect(again.file(in: result).path == draft)
        again.selection = result.id
        let delivery = again.delivery(in: result)
        await again.observe(again.file(in: result))
        await again.stage(sha: try #require(delivery.sha256), artifact: again.file(in: result))
        let url = try #require(again.selectedHandoffURL)
        #expect(url.lastPathComponent == "board-draft.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == "# Board report\nDraft.")
    }

    @Test func aDeclinedSuggestionIsNotMadeAgainAfterARelaunch() async throws {
        try renamedReport()
        let model = relaunch()
        let suggestion = try #require(model.organization.suggestions.first)
        await model.keepApart(suggestion.earlier, suggestion.later)
        #expect(model.organization.suggestions.isEmpty)
        _ = try indexer.run(now: { then.addingTimeInterval(9999) })
        #expect(relaunch().organization.suggestions.isEmpty)
        #expect(relaunch().corrections.map(\.kind) == [.notSameWork])
    }

    @Test func workMovedToANewProjectStaysThereAndCanBePutBack() async throws {
        try renamedReport()
        let model = relaunch()
        let deck = try #require(model.organization.work(containing: board.appendingPathComponent("slides/deck.key").path))
        await model.move(deck, toNewProject: "Board meeting")
        let moved = try #require(relaunch().organization.work(containing: deck.id))
        let project = try #require(relaunch().organization.project(moved.project))
        #expect(project.name == "Board meeting")
        #expect(project.origin == .yours)
        // Its later delivery stays in the project too.
        try write("deck v2", "slides/deck.key", at: then.addingTimeInterval(7200))
        try turn("update the deck", "[deck](slides/deck.key)", at: then.addingTimeInterval(7200))
        let after = relaunch()
        #expect(after.organization.work(containing: deck.id)?.project == project.key)
        #expect(after.organization.work(containing: deck.id)?.deliveries.count == 2)

        await after.undoMove(try #require(after.organization.work(containing: deck.id)))
        #expect(relaunch().organization.work(containing: deck.id)?.project == board.path)
        #expect(relaunch().organization.project(project.key)?.works.isEmpty == true)
    }

    @Test func aSiblingInAnotherProjectIsShownInItsProject() async throws {
        try renamedReport()
        let model = relaunch()
        let deck = try #require(model.organization.work(containing: board.appendingPathComponent("slides/deck.key").path))
        await model.move(deck, toNewProject: "Slides")
        let report = try #require(model.organization.work(containing: board.appendingPathComponent("board-draft.md").path))
        model.place = .project(report.project)
        let sibling = try #require(model.siblings[report.files[0].deliveries.last!.id]?.first)
        model.select(sibling)
        #expect(model.place == .project(model.organization.work(containing: sibling.path)!.project))
        #expect(model.selected?.work.id == deck.id)
        #expect(model.delivery(in: try #require(model.selected)).id == sibling.id)
    }

    @Test func theConversationIsResumableOnlyWhileItsLogAndFolderAreThere() async throws {
        try renamedReport()
        let model = relaunch()
        let delivery = try #require(model.organization.works.first?.deliveries.first)
        let expected = "cd " + Locator.quoted(board.path) + " && claude --resume 'board-session'"
        #expect(model.resume(delivery) == .command(expected))
        var moved = delivery
        moved.sessionCwd = board.appendingPathComponent("gone").path
        #expect(model.resume(moved) == .folderGone(moved.sessionCwd!))
        moved.logPath = root.appendingPathComponent("pruned.jsonl").path
        #expect(model.resume(moved) == .logGone)
    }

    @Test func undoingEveryCorrectionShowsTheLibraryAsGleanerFoundIt() async throws {
        try renamedReport()
        let model = relaunch()
        let suggestion = try #require(model.organization.suggestions.first)
        await model.join(suggestion.earlier, suggestion.later)
        await model.move(try #require(model.organization.works.first), toNewProject: "Mine")
        model.place = .project(try #require(model.organization.works.first).project)
        await model.undoAllCorrections()
        #expect(model.place == .all)
        #expect(model.organization.works.count == 3)
        #expect(model.userProjects.isEmpty)
        #expect(relaunch().corrections.isEmpty)
    }

    /// A decision made while Gleaner reads a log waits for that read, and is kept whatever the
    /// read does with its own transaction.
    @Test func aCorrectionMadeDuringAReadIsKept() async throws {
        try renamedReport()
        let model = relaunch()
        let suggestion = try #require(model.organization.suggestions.first)
        // A log is read as the indexer reads one: in a transaction on its own connection, through
        // the library's write gate. The decision is made while that transaction is open, and the
        // read gives it up.
        let registry = indexer.registry
        await withCheckedContinuation { (open: CheckedContinuation<Void, Never>) in
            Thread.detachNewThread {
                try? registry.transaction {
                    open.resume()
                    Thread.sleep(forTimeInterval: 0.3)
                    throw CancellationError()
                }
            }
        }
        await model.join(suggestion.earlier, suggestion.later)
        #expect(model.correctionFailure == nil)
        #expect(relaunch().corrections.map(\.kind) == [.sameWork])
    }

    @Test func undoingAMoveOfSeveralFilesIsOneDecision() async throws {
        try renamedReport()
        let model = relaunch()
        let suggestion = try #require(model.organization.suggestions.first)
        await model.join(suggestion.earlier, suggestion.later)
        let report = try #require(model.organization.work(containing: suggestion.later))
        await model.move(report, toNewProject: "Board meeting")
        let mine = try #require(model.userProjects.first).key
        #expect(model.place == .all || model.place == .project(mine))
        let group = try #require(model.correctionGroups.first)
        #expect(group.count == 2)
        #expect(model.describe(group) == "Moved board-draft.md, board-final.md to Board meeting")
        model.place = .project(mine)
        await model.undo(group)
        let back = try #require(model.organization.work(containing: suggestion.later))
        #expect(back.project == board.path)
        // The window follows the work back to its project.
        #expect(model.place == .project(board.path))
        #expect(model.selected?.work.id == back.id)
    }

    @Test func theSourcesPageHidesTheSelection() throws {
        try renamedReport()
        let model = relaunch()
        model.selection = try #require(model.organization.works.first).id
        #expect(model.selected != nil)
        model.place = .sources
        #expect(model.selected == nil)
        // A search goes back to the deliveries.
        model.query = "deck"
        #expect(model.place == .all)
    }

    /// Decisions made while logs are read one after another, and two made together, are all kept.
    @Test func correctionsDuringBackToBackReadsAndTogetherAreAllKept() async throws {
        try renamedReport()
        let model = relaunch()
        let suggestion = try #require(model.organization.suggestions.first)
        let deck = try #require(model.organization.work(containing: board.appendingPathComponent("slides/deck.key").path))
        let registry = indexer.registry
        let reading = Task.detached {
            let end = Date().addingTimeInterval(1.5)
            while Date() < end { try? registry.transaction { Thread.sleep(forTimeInterval: 0.02) } }
        }
        async let joined: Void = model.join(suggestion.earlier, suggestion.later)
        async let moved: Void = model.move(deck, toNewProject: "Slides")
        _ = await (joined, moved)
        await reading.value
        #expect(model.correctionFailure == nil)
        #expect(Set(relaunch().corrections.map(\.kind)) == [.sameWork, .project])
    }
}
