import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Gleaner
@testable import GleanerCore

/// The outline (docs/design/outline.md): a report revised twice in a folder outside git, with notes
/// delivered once, and a plan revised twice in a git repository. Which works open on their
/// revisions, what choosing a row shows, what a revision's row hands over, and the keys.
@MainActor @Suite struct OutlineTests {
    let root: URL
    let board: URL
    let app: URL
    let indexer: Indexer
    let then = Date(timeIntervalSince1970: 1_792_281_600)

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("gleaner-outline-\(UUID().uuidString)")
        board = root.appendingPathComponent("board")
        app = root.appendingPathComponent("app")
        try fm.createDirectory(at: board, withIntermediateDirectories: true)
        try fm.createDirectory(at: app.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try "x".write(to: app.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        for args in [["init", "-q"], ["add", "."], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init"]] {
            #expect(Locator.run(["-C", app.path] + args).status == 0)
        }
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("handoff")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))

        let later = then.addingTimeInterval(3600)
        try write("draft", board.appendingPathComponent("report.md"), at: then)
        try write("notes", board.appendingPathComponent("notes.md"), at: then)
        try turn(board, "write the report and notes", "[report](report.md) and [notes](notes.md)", at: then)
        try write("final", board.appendingPathComponent("report.md"), at: later)
        try turn(board, "revise the report", "[report](report.md)", at: later)
        try write("plan one", app.appendingPathComponent("docs/plan.md"), at: then)
        try turn(app, "plan it", "[plan](docs/plan.md)", at: then)
        try write("plan two", app.appendingPathComponent("docs/plan.md"), at: later)
        try turn(app, "plan it again", "[plan](docs/plan.md)", at: later)
    }

    func write(_ text: String, _ url: URL, at: Date) throws {
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: at], ofItemAtPath: url.path)
    }

    func turn(_ cwd: URL, _ request: String, _ reply: String, at: Date) throws {
        let log = root.appendingPathComponent("claude/\(cwd.lastPathComponent)/s.jsonl")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        func record(_ type: String, _ text: String) throws -> String {
            let content: Any = type == "user" ? text : [["type": "text", "text": text]]
            let object: [String: Any] = ["type": type, "sessionId": cwd.lastPathComponent, "cwd": cwd.path, "origin": ["kind": "human"],
                                         "timestamp": at.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
                                         "message": ["role": type, "content": content]]
            return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
        }
        let existing = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        try (existing + record("user", request) + record("assistant", reply)).write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run(now: { at.addingTimeInterval(1) })
    }

    func work(_ model: LibraryModel, _ name: String) throws -> Work {
        try #require(model.organization.works.first { $0.name == name })
    }

    func project(_ model: LibraryModel, _ origin: Organization.Project.Origin) throws -> Organization.Project {
        try #require(model.projects.first { $0.origin == origin })
    }

    @Test func aProjectOutsideGitOpensEachWorkOnItsRevisionsAndARepositoryDoesNot() throws {
        let model = LibraryModel(indexer: indexer)
        let report = try work(model, "report.md"), notes = try work(model, "notes.md"), plan = try work(model, "plan.md")
        model.place = .project(try project(model, .folder).key)
        #expect(model.isOpen(report))
        // One revision: nothing to open.
        #expect(!model.isOpen(notes))
        model.place = .project(try project(model, .repository).key)
        #expect(!model.isOpen(plan))
        // Lists of what arrived keep works closed, and so does a search in a project.
        model.place = .all
        #expect(!model.isOpen(report))
        model.place = .project(try project(model, .folder).key)
        model.query = "report"
        #expect(!model.isOpen(report))
        model.query = ""
        // What the person opens or closes stays so, wherever the work is listed.
        model.disclosed[plan.id] = true
        model.place = .all
        #expect(model.isOpen(plan))
        model.disclosed[report.id] = false
        model.place = .project(try project(model, .folder).key)
        #expect(!model.isOpen(report))
    }

    @Test func choosingARevisionShowsItAndTheOutlineFollowsTheDetail() throws {
        let model = LibraryModel(indexer: indexer)
        model.place = .project(try project(model, .folder).key)
        let report = try work(model, "report.md"), notes = try work(model, "notes.md")
        let newer = report.deliveries[0], older = report.deliveries[1]

        model.outlineSelection = .revision(report.id, older.id)
        #expect(model.selection == report.id)
        #expect(model.delivery(in: try #require(model.selected)).id == older.id)
        // Choosing under Versions selects that revision's row.
        model.chosenDelivery = newer.id
        #expect(model.outlineSelection == .revision(report.id, newer.id))
        // Closed, the work's row stands for it, and the detail keeps the revision chosen; choosing
        // the row already selected changes nothing.
        model.chosenDelivery = older.id
        model.disclosed[report.id] = false
        #expect(model.outlineSelection == .work(report.id))
        model.outlineSelection = .work(report.id)
        #expect(model.chosenDelivery == older.id)
        // Another work shows what its row shows.
        model.outlineSelection = .work(notes.id)
        #expect(model.selection == notes.id)
        #expect(model.chosenDelivery == nil)
        // Opened again, a work's row shows its newest revision.
        model.disclosed[report.id] = true
        model.outlineSelection = .work(report.id)
        #expect(model.delivery(in: try #require(model.selected)).id == newer.id)
        #expect(model.outlineSelection == .work(report.id))
    }

    @Test func aRevisionsRowHandsOverItsOwnBytes() async throws {
        let model = LibraryModel(indexer: indexer)
        let report = try work(model, "report.md")
        let older = report.deliveries[1]
        #expect(try await dropped(model.dragItem(report.file(of: older), older)) == "draft")
        // The work's row hands over what it shows: the newest.
        let row = try #require(model.result(for: report))
        #expect(try await dropped(model.dragItem(for: row)) == "final")
        // The right-click menu acts on the row's own file and delivery.
        #expect(model.target(.revision(report.id, older.id))?.delivery.id == older.id)
        #expect(model.target(.work(report.id))?.delivery.id == report.deliveries[0].id)
    }

    /// The keys go to the list as a person's would: ↓ moves into a work's revisions, ← closes the
    /// work and → opens it again.
    @Test func theOutlineIsWalkedWithTheArrowKeys() async throws {
        let model = LibraryModel(indexer: indexer)
        let report = try work(model, "report.md"), notes = try work(model, "notes.md")
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1100, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LibraryView().environment(model))
        window.orderBack(nil)
        defer { window.close() }
        try await TourTests.settle(0.3)
        // After the window restored its saved place.
        model.place = .project(try project(model, .folder).key)
        try await TourTests.settle(0.3)

        model.outlineSelection = .work(report.id)
        try await TourTests.settle(0.2)
        // The content column's list: the one whose selected row opens, the report's.
        let content = try #require(window.contentView)
        let outline = try #require(Self.outlines(in: content).first { $0.selectedRow >= 0 && $0.isExpandable($0.item(atRow: $0.selectedRow)) })
        window.makeFirstResponder(outline)
        func press(_ key: UInt16, _ character: Int) async throws {
            let text = String(Character(UnicodeScalar(character)!))
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                                      timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                      characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: key))
            outline.keyDown(with: event)
            try await TourTests.settle(0.15)
        }
        let down = (UInt16(125), NSDownArrowFunctionKey), left = (UInt16(123), NSLeftArrowFunctionKey), right = (UInt16(124), NSRightArrowFunctionKey)

        try await press(down.0, down.1)
        #expect(model.outlineSelection == .revision(report.id, report.deliveries[0].id))
        try await press(down.0, down.1)
        #expect(model.outlineSelection == .revision(report.id, report.deliveries[1].id))
        #expect(model.delivery(in: try #require(model.selected)).id == report.deliveries[1].id)
        try await press(down.0, down.1)
        #expect(model.outlineSelection == .work(notes.id))

        model.outlineSelection = .work(report.id)
        try await TourTests.settle(0.2)
        try await press(left.0, left.1)
        #expect(!model.isOpen(report))
        try await press(down.0, down.1)
        #expect(model.outlineSelection == .work(notes.id))
        model.outlineSelection = .work(report.id)
        try await TourTests.settle(0.2)
        try await press(right.0, right.1)
        #expect(model.isOpen(report))
    }

    static func outlines(in view: NSView) -> [NSOutlineView] {
        (view as? NSOutlineView).map { [$0] } ?? view.subviews.flatMap(outlines)
    }

    func dropped(_ provider: NSItemProvider?) async throws -> String {
        let provider = try #require(provider)
        let type = try #require(provider.registeredTypeIdentifiers.first)
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                continuation.resume(with: Result {
                    guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                    return try String(contentsOf: url, encoding: .utf8)
                })
            }
        }
    }
}
