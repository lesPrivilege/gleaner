import AppKit
import AVFoundation
import Foundation
import SwiftUI
import Testing
@testable import Gleaner
@testable import GleanerCore

/// A walk through the window on the synthetic home (`scripts/acceptance-home.py`), as a person
/// returning to the board project would take it, with a picture of the real window at each step.
/// The window is drawn off screen from the app's own views and model; the steps act through the
/// model, as the buttons do. Runs only when `GLEANER_TOUR` names a folder for the pictures:
///
///     GLEANER_TOUR=<folder> swift test --filter TourTests
@MainActor @Suite struct TourTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["GLEANER_TOUR"].map { URL(fileURLWithPath: $0, isDirectory: true) }

    @Test(.enabled(if: folder != nil)) func walkTheBoardProject() async throws {
        let out = try #require(Self.folder)
        let fm = FileManager.default
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let home = fm.temporaryDirectory.appendingPathComponent("gleaner-tour-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/acceptance-home.py")
        func phase(_ name: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script.path, home.path, name]
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        try phase("initial")
        let library = home.appendingPathComponent("Library")
        let registryPath = try library.appendingPathComponent("Application Support/Gleaner").creating()
            .appendingPathComponent("registry.sqlite").path
        let indexer = Indexer(
            registry: try Registry(path: registryPath),
            store: ContentStore(objects: library.appendingPathComponent("Application Support/Gleaner/objects"),
                                staging: library.appendingPathComponent("Caches/Gleaner/handoff")),
            sources: LogSources(claudeProjects: home.appendingPathComponent(".claude/projects"), codexHome: home.appendingPathComponent(".codex")))
        // Each phase is read before the next, as the open app would through its watcher.
        _ = try indexer.run()
        for name in ["board", "board-revise", "board-final"] {
            try phase(name)
            _ = try indexer.run()
        }

        var model = LibraryModel(indexer: indexer)
        var window = Self.window(model)
        var step = 0
        func shot(_ name: String) async throws {
            step += 1
            try await Self.snapshot(window, to: out.appendingPathComponent(String(format: "%02d-%@.png", step, name)))
        }
        /// The whole detail, as a person scrolling it would see it.
        func tall(_ name: String) async throws {
            // A titled window is kept within the screen; a borderless one holding the detail alone isn't.
            let detail = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 980, height: 2400),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            detail.isReleasedWhenClosed = false
            detail.contentView = NSHostingView(rootView: DetailColumn().environment(model))
            detail.orderBack(nil)
            step += 1
            try await Self.snapshot(detail, to: out.appendingPathComponent(String(format: "%02d-%@.png", step, name)))
            detail.close()
        }
        func work(_ name: String) throws -> Work { try #require(model.organization.works.first { $0.files.contains { $0.name == name } }) }
        func show(_ work: Work, delivery: Delivery? = nil) async throws {
            model.selection = work.id
            if let delivery { model.chosenDelivery = delivery.id }
            let result = try #require(model.selected)
            await model.observe(model.file(in: result))
            if let sha = model.delivery(in: result).sha256 { await model.stage(sha: sha, artifact: model.file(in: result)) }
        }
        model.reindex()
        try await Self.until { model.indexed }

        // Each phase was read before the next: every board file's deliveries kept their own bytes.
        let boardFiles = model.organization.works.flatMap(\.files).filter { $0.path.contains("/work/board/") }
        #expect(boardFiles.count == 7)
        #expect(boardFiles.allSatisfy { $0.deliveries.allSatisfy { $0.sha256 != nil && $0.capture?.provenance == .atDelivery } })
        #expect(Set(try #require(boardFiles.first { $0.name == "revenue.png" }).deliveries.map(\.sha256)).count == 2)
        try await shot("all-deliveries")
        let board = try #require(model.projects.first { $0.name == "board" })
        model.place = .project(board.key)
        try await shot("board-outline")
        // The detail with nothing selected offers the newest work here.
        try await tall("no-selection-next-step")
        // A revision chosen in the outline is the one the detail shows.
        let chart = try work("revenue.png")
        model.outlineSelection = .revision(chart.id, try #require(chart.deliveries.last).id)
        #expect(model.delivery(in: try #require(model.selected)).number == 1)
        try await show(chart, delivery: chart.deliveries.last)
        try await shot("outline-chart-first-revision")
        // Closed, its row stands for it, still showing that revision.
        model.disclosed[chart.id] = false
        #expect(model.outlineSelection == .work(chart.id))
        try await shot("outline-chart-closed")
        model.disclosed[chart.id] = nil

        let final = try work("board-report-final.md")
        try await show(final)
        try await shot("final-report-with-suggestion")

        let suggestion = try #require(model.organization.suggestions(for: final).first)
        await model.join(suggestion.earlier, suggestion.later)
        let joined = try work("board-report-final.md")
        try await show(joined)
        try await tall("report-joined-whole-detail")
        try await show(joined, delivery: joined.deliveries.last)
        try await shot("report-first-draft")

        let first = try work("revenue.png")
        try await show(first, delivery: first.deliveries.last)
        try await shot("chart-first-delivery-siblings")
        // The conversation it came from, reply by reply, opened from its name.
        model.openThread(try #require(first.deliveries.last))
        try await tall("chart-first-delivery-thread")
        // The board's replies, newest first and by day, and every project's.
        model.select(try #require(first.deliveries.last))
        model.arrangement = .timeline
        try await shot("board-timeline")
        model.place = .all
        try await shot("all-deliveries-timeline")
        model.arrangement = .works
        model.place = .project(board.key)

        let fixtures = try #require(model.projects.first { $0.name == "fixtures" })
        model.place = .project(fixtures.key)
        let guide = try work("guide.md")
        try await show(guide, delivery: guide.deliveries.last)
        try await tall("guide-first-delivery-with-eight-others")
        model.place = .project(board.key)

        let brief = try work("brief.pdf")
        try await show(brief)
        try await shot("brief-original-gone")

        let clientA = try #require(model.projects.first { $0.name == "client-a/app" })
        model.place = .project(clientA.key)
        let appendix = try work("appendix.md")
        try await show(appendix)
        try await tall("appendix-misfiled-whole-detail")
        await model.move(appendix, to: board.key)
        try await show(try work("appendix.md"))
        try await shot("appendix-moved")

        // Read every log again, then open the library as a relaunch would: the decisions stand.
        try indexer.registry.db.execute("PRAGMA user_version = 1")
        let reread = Indexer(registry: try Registry(path: registryPath), store: indexer.store, sources: indexer.sources)
        _ = try reread.run()
        window.close()
        model = LibraryModel(indexer: reread)
        window = Self.window(model)
        model.reindex()
        try await Self.until { model.indexed }
        model.place = .project(board.key)
        try await shot("board-after-reread-and-relaunch")

        model.place = .sources
        model.sourcePage = .agent(.claudeCode)
        try await shot("sources-claude-code")
        // Codex through a gateway, then turned off: its line dashed, its deliveries hidden.
        model.sourcePage = .agent(.codex)
        try await shot("sources-codex-through-a-gateway")
        await model.setSource(.codex, on: false)
        try await shot("sources-codex-off")
        // The toolbar's popover, on its own: the window's toolbar isn't drawn off screen.
        let panel = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 320, height: 220),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ConnectionsPanel().environment(model)
            .background(Color(nsColor: .windowBackgroundColor)))
        panel.orderBack(nil)
        step += 1
        try await Self.snapshot(panel, to: out.appendingPathComponent(String(format: "%02d-connections-popover.png", step)))
        panel.close()
        await model.setSource(.codex, on: true)
        model.sourcePage = .corrections
        try await shot("sources-corrections")

        // A project of your own left empty offers to bring work in.
        await model.move(try work("board-deck.pptx"), toNewProject: "Annual review")
        let yours = try #require(model.projects.first { $0.name == "Annual review" })
        await model.undoMove(try work("board-deck.pptx"))
        model.place = .project(yours.key)
        try await shot("empty-project-next-step")
        let moveHere = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 460, height: 440),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        moveHere.isReleasedWhenClosed = false
        moveHere.contentView = NSHostingView(rootView: MoveHereSheet(project: try #require(model.organization.project(yours.key)))
            .environment(model).background(Color(nsColor: .windowBackgroundColor)))
        moveHere.orderBack(nil)
        step += 1
        try await Self.snapshot(moveHere, to: out.appendingPathComponent(String(format: "%02d-move-here-sheet.png", step)))
        moveHere.close()
        await model.remove(try #require(model.organization.project(yours.key)))

        model.place = .project(board.key)
        try await show(try work("board-report-final.md"))
        // Dark from the start, as with the system set to dark, and after switching while open.
        window.close()
        window = Self.window(model, appearance: NSAppearance(named: .darkAqua))
        try await Self.settle(0.2)
        model.place = .project(board.key)
        try await show(try work("board-report-final.md"))
        try await shot("dark-report")
        window.appearance = NSAppearance(named: .aqua)
        try await shot("dark-switched-to-light")
        window.close()
    }

    /// Folders handed over (`acceptance-home.py <home> bundle`, SPEC §5.4): the launch project's
    /// outline with its renders folded, a file of the site in its folder, the site as its first
    /// reply handed it over, before its files were written, and as the second did, the app folder
    /// that isn't unpacked, and Sources saying why.
    @Test(.enabled(if: folder != nil)) func walkTheFoldersHandedOver() async throws {
        let out = try #require(Self.folder)
        let fm = FileManager.default
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let home = fm.temporaryDirectory.appendingPathComponent("gleaner-tour-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/acceptance-home.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, home.path, "bundle"]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let library = home.appendingPathComponent("Library")
        let indexer = Indexer(
            registry: try Registry(path: try library.appendingPathComponent("Application Support/Gleaner").creating()
                .appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: library.appendingPathComponent("Application Support/Gleaner/objects"),
                                staging: library.appendingPathComponent("Caches/Gleaner/handoff")),
            sources: LogSources(claudeProjects: home.appendingPathComponent(".claude/projects"), codexHome: home.appendingPathComponent(".codex")))
        indexer.home = home.path

        let model = LibraryModel(indexer: indexer)
        let window = Self.window(model)
        defer { window.close() }
        model.reindex()
        try await Self.until { model.indexed }
        var step = 0
        func shot(_ name: String) async throws {
            step += 1
            try await Self.snapshot(window, to: out.appendingPathComponent(String(format: "bundle-%02d-%@.png", step, name)))
        }
        func work(_ name: String) throws -> Work { try #require(model.organization.works.first { $0.name == name }) }
        func show(_ work: Work, delivery: Delivery? = nil) async throws {
            model.selection = work.id
            if let delivery { model.chosenDelivery = delivery.id }
            let result = try #require(model.selected)
            await model.observe(model.file(in: result))
            if let sha = model.delivery(in: result).sha256 { await model.stage(sha: sha, artifact: model.file(in: result)) }
        }

        let launch = try #require(model.projects.first { $0.name == "launch" })
        model.place = .project(launch.key)
        try await shot("launch-outline")
        let page = try work("index.html")
        try await show(page)
        try await shot("site-page-handed-over-in-site")
        try await show(try work("site"), delivery: try work("site").deliveries.last)
        try await shot("site-folder-first-reply-before-its-files-were-written")
        try await show(try work("site"))
        try await shot("site-folder-files")
        try await show(try work("app"))
        try await shot("app-folder-not-unpacked")
        let frame = try work("frame-007.png")
        model.selection = frame.id
        try await shot("renders-unfolded-for-the-selection")
        model.place = .sources
        model.sourcePage = .agent(.claudeCode)
        try await shot("sources-folders-not-unpacked")
    }

    /// Reviewing a series (`acceptance-home.py <home> review`, docs/design/review.md): the project's
    /// outline with what sessions were observed doing; a series of three episodes and its
    /// compilation made into collections, some of it kept from what was observed; the series and an
    /// episode on their review pages, before and after a verdict; a recut that leaves the verdict on
    /// the old bytes; To Review; a work's Review section; the note sheet; Corrections; and dark.
    @Test(.enabled(if: folder != nil)) func walkTheReviewOfASeries() async throws {
        let out = try #require(Self.folder)
        let fm = FileManager.default
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let home = fm.temporaryDirectory.appendingPathComponent("gleaner-tour-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let series = home.appendingPathComponent("work/reading-list")
        // Real videos, which the script keeps: 16:9 episodes and a 1:1 compilation.
        for (n, color) in [(1, NSColor.systemBlue), (2, .systemOrange), (3, .systemGreen)] {
            try await Self.writeVideo(to: series.appendingPathComponent(String(format: "ep%02d/ep%02d.mp4", n, n)),
                                      size: CGSize(width: 640, height: 360), color: color)
        }
        try await Self.writeVideo(to: series.appendingPathComponent("compilation/reading-list.mp4"),
                                  size: CGSize(width: 480, height: 480), color: .systemPurple)
        try Self.phase("review", home: home)
        let library = home.appendingPathComponent("Library")
        let indexer = Indexer(
            registry: try Registry(path: try library.appendingPathComponent("Application Support/Gleaner").creating()
                .appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: library.appendingPathComponent("Application Support/Gleaner/objects"),
                                staging: library.appendingPathComponent("Caches/Gleaner/handoff")),
            sources: LogSources(claudeProjects: home.appendingPathComponent(".claude/projects"), codexHome: home.appendingPathComponent(".codex")))
        indexer.home = home.path

        let model = LibraryModel(indexer: indexer)
        var window = Self.window(model)
        defer { window.close() }
        model.reindex()
        try await Self.until { model.indexed }
        var step = 0
        func shot(_ name: String) async throws {
            step += 1
            try await Self.snapshot(window, to: out.appendingPathComponent(String(format: "review-%02d-%@.png", step, name)))
        }
        func tall(_ name: String) async throws {
            step += 1
            try await Self.detail(model, to: out.appendingPathComponent(String(format: "review-%02d-%@.png", step, name)))
        }
        func path(_ relative: String) -> String { series.appendingPathComponent(relative).path }
        func work(_ relative: String) throws -> Work { try #require(model.organization.work(containing: path(relative))) }
        func candidate(_ relative: String) throws -> Candidate { try #require(model.organization.candidate(path(relative))) }

        let project = try #require(model.projects.first { $0.name == "reading-list" })
        model.place = .project(project.key)
        #expect(model.observedSessions(in: project).map(\.title) == ["Series covers", "Reading list series"])
        try await shot("outline")
        step += 1
        try await Self.content(model, to: out.appendingPathComponent(String(format: "review-%02d-outline-whole-with-observed.png", step)))

        // The series and its episodes, made and filled as the person would.
        let made = try #require(await model.newUnit(named: "Reading List", in: project.key))
        var episodes: [WorkUnit] = []
        for n in 1...3 {
            episodes.append(try #require(await model.newUnit(named: "Episode \(n)", in: project.key, inside: made.key)))
        }
        func unit(_ key: String) throws -> WorkUnit { try #require(model.organization.unit(key)) }
        for (n, episode) in episodes.enumerated().map({ ($0.offset + 1, $0.element) }) {
            let ep = String(format: "ep%02d", n)
            let works = model.organization.works.filter { $0.latest.path.hasPrefix(path(ep) + "/") }
            await model.add(works, to: try unit(episode.key))
            let observed = model.organization.candidates(in: project.key).filter { $0.path.hasPrefix(path(ep) + "/") }
            await model.add(observed, to: try unit(episode.key))
        }
        await model.add([try work("compilation/reading-list.mp4")], to: try unit(made.key))
        await model.add([try candidate("logo.png"), try candidate("compilation/chapters.md")], to: try unit(made.key))
        #expect(model.organization.works(in: episodes[0].key).count == 7)
        #expect(model.organization.works(in: episodes[1].key).count == 7)
        #expect(model.toReviewCount == 24)

        // The project's outline leads with its collections, each with what waits on the person.
        model.place = .project(project.key)
        try await shot("outline-with-collections")
        // A search finds works by their collection's name: Episode 2's covers, by "episode 2 cover".
        model.query = "episode 2 cover"
        #expect(Set(model.results.map(\.work.name)) == ["cover-4x3.png", "cover-4x3.svg", "cover-16x9.png"])
        try await shot("search-by-collection-name")
        // New Collection from These, from what the search found: named in place, holding exactly
        // those three, then taken back as Edit › Undo takes it back.
        let found = model.results.map(\.work)
        model.newCollection(from: found)
        try await shot("new-collection-from-these")
        let before = Set(model.corrections.map(\.id))
        await model.commitNaming("Wide Covers")
        let wide = try #require(model.organization.units.first { $0.name == "Wide Covers" })
        #expect(Set(model.organization.works(in: wide.key).map(\.id)) == Set(found.map(\.id)))
        model.query = ""
        model.place = .unit(wide.key)
        try await shot("new-collection-made")
        await model.unmake(wide, with: model.corrections.filter { !before.contains($0.id) })
        #expect(model.organization.works(in: episodes[1].key).count == 7 && model.toReviewCount == 24)

        model.place = .unit(made.key)
        try await shot("series-review-page")
        // A collection is named in place, in the sidebar.
        model.startNewUnit(in: project.key, inside: made.key)
        try await shot("naming-a-new-collection")
        model.naming = nil
        // Several chosen: what all of them can be given.
        model.selectedRows = [.work(try work("compilation/reading-list.mp4").id), .work(try work("logo.png").id)]
        #expect(model.selectedWorks.count == 2)
        try await shot("two-works-chosen")
        model.outlineSelection = .unit(made.key)
        #expect(model.alsoSelected.isEmpty)
        model.outlineSelection = .unit(episodes[0].key)
        try await shot("episode-1-review-page")
        try await tall("episode-1-whole-page")
        // Review All's menu as the page offers it once every item is drawn: the images and the
        // script, with the video and the narration left to their own verdicts. Drawn from the
        // same `ReviewAll` the menu reads: a menu doesn't open off screen.
        let page = ReviewLayout(model.organization.works(in: episodes[0].key))
        let drawnAll = Set(page.works.map(\.latest.path))
        let shownAll = Dictionary(uniqueKeysWithValues: page.works.compactMap { work in FileStat(work.latest.path).map { (work.latest.path, $0) } })
        let all = ReviewAll(page.works, drawn: drawnAll, shown: shownAll, hasFile: { !model.hasNoFile($0) }, verdict: model.verdict)
        #expect(all.approve.count == 4 && all.oneByOne == "1 video, 1 audio file and 1 other file to review one by one")
        step += 1
        try await Self.menu([(Wording.reviewAll(.approved, all.approve.count), !all.approve.isEmpty),
                             (Wording.reviewAll(.changesRequested, all.changes.count), !all.changes.isEmpty),
                             (Wording.reviewAll(.rejected, all.reject.count), !all.reject.isEmpty)], note: all.oneByOne,
                            to: out.appendingPathComponent(String(format: "review-%02d-review-all-menu.png", step)))

        // Every file of episode 1 approved as shown, its script asked again, its video published.
        let shown = Dictionary(uniqueKeysWithValues: model.organization.works(in: episodes[0].key).compactMap { work in
            FileStat(work.latest.path).map { (work.latest.path, $0) }
        })
        await model.review(model.organization.works(in: episodes[0].key), as: .approved, shown: shown)
        await model.review([try work("ep01/script.md")], as: .changesRequested, note: "Shorten the open")
        await model.review([try work("ep01/ep01.mp4")], as: .published, note: "the channel")
        #expect(model.waiting(in: episodes[0].key) == 0)
        try await tall("episode-1-after-review")

        // The recut: the verdict stays on the bytes it was made on.
        try Self.phase("review-revise", home: home)
        model.reindex()
        try await Self.until { model.organization.work(containing: path("ep01/ep01.mp4"))?.deliveries.count == 2 }
        let recut = try work("ep01/ep01.mp4")
        #expect({ if case .mayHaveChanged = model.verdict(of: recut) { true } else { false } }())
        model.place = .toReview
        try await shot("to-review")
        model.selection = recut.id
        await model.observe(recut.latest)
        #expect({ if case .changed = model.verdict(of: recut) { true } else { false } }())
        try await shot("to-review-recut-selected")
        if let sha = recut.latest.latest.sha256 { await model.stage(sha: sha, artifact: recut.latest) }
        try await tall("recut-detail-with-review-section")
        model.selection = try work("ep01/script.md").id
        await model.observe(try work("ep01/script.md").latest)
        try await tall("script-detail-with-history")

        let sheet = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 420, height: 260),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        sheet.contentView = NSHostingView(rootView: NoteSheet(asking: Asking(works: [try work("ep02/script.md")], kind: .changesRequested, shown: [:]))
            .environment(model).background(Color(nsColor: .windowBackgroundColor)))
        sheet.orderBack(nil)
        step += 1
        try await Self.snapshot(sheet, to: out.appendingPathComponent(String(format: "review-%02d-note-sheet.png", step)))
        sheet.close()

        // A master over 64 MB that Git ignores: Request Changes offers Save a Copy, on, and says
        // the bytes judged wouldn't be kept otherwise.
        let masterPath = home.appendingPathComponent("work/masters/reading-list-master.mov").path
        let master = try #require(model.organization.work(containing: masterPath))
        let large = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 420, height: 300),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        large.isReleasedWhenClosed = false
        large.contentView = NSHostingView(rootView: NoteSheet(asking: Asking(works: [master], kind: .changesRequested,
                                                                             shown: [masterPath: try #require(FileStat(masterPath))]))
            .environment(model).background(Color(nsColor: .windowBackgroundColor)))
        large.orderBack(nil)
        step += 1
        try await Self.snapshot(large, to: out.appendingPathComponent(String(format: "review-%02d-note-sheet-not-kept.png", step)))
        large.close()
        // Approved without it: the verdict's row says so, with Save a Copy beside it.
        await model.review([master], as: .approved)
        await model.lookUpGit([masterPath])
        model.place = .project(master.project)
        model.selection = master.id
        await model.observe(master.latest)
        // Its copy prepared first, as for the recut: Quick Look is never handed a file after the
        // detail's window has closed.
        if let sha = master.latest.latest.sha256 { await model.stage(sha: sha, artifact: master.latest) }
        try await tall("master-detail-not-kept")

        model.place = .sources
        model.sourcePage = .corrections
        try await shot("corrections")

        window.close()
        window = Self.window(model, appearance: NSAppearance(named: .darkAqua))
        try await Self.settle(0.2)
        model.place = .unit(made.key)
        model.outlineSelection = .unit(episodes[1].key)
        try await shot("dark-episode-2-review-page")

        // An image nothing can draw says so, rather than looking like one still being read (A20).
        let broken = home.appendingPathComponent("work/broken.png")
        try Data("not an image".utf8).write(to: broken)
        let tile = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 260),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        tile.isReleasedWhenClosed = false
        tile.contentView = NSHostingView(rootView: ImageTile(path: broken.path, generation: 0).padding(16)
            .background(Color(nsColor: .windowBackgroundColor)))
        tile.orderBack(nil)
        step += 1
        try await Self.snapshot(tile, to: out.appendingPathComponent(String(format: "review-%02d-image-that-cant-be-drawn.png", step)))
        tile.close()
    }

    /// Runs a phase of `scripts/acceptance-home.py` on `home`.
    static func phase(_ name: String, home: URL) throws {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/acceptance-home.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, home.path, name]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    /// The whole detail column, as a person scrolling it would see it.
    static func detail(_ model: LibraryModel, to url: URL) async throws {
        // A titled window is kept within the screen; a borderless one holding the detail alone isn't.
        let detail = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 980, height: 2400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        detail.isReleasedWhenClosed = false
        detail.contentView = NSHostingView(rootView: DetailColumn().environment(model))
        detail.orderBack(nil)
        try await snapshot(detail, to: url)
        // Its views go with it: a Quick Look view closed with its window takes no other file.
        detail.contentView = nil
        detail.close()
    }

    /// A menu's items as it shows them, the disabled ones dimmed, and a note under a divider: a
    /// stand-in drawn from the same values the menu reads, since a menu doesn't open off screen.
    static func menu(_ items: [(title: String, enabled: Bool)], note: String?, to url: URL) async throws {
        let panel = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 320, height: 140),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.title) { item in
                Text(item.title).foregroundStyle(item.enabled ? .primary : .tertiary).padding(.horizontal, 14).padding(.vertical, 3)
            }
            if let note {
                Divider().padding(.vertical, 5)
                Text(note).foregroundStyle(.tertiary).padding(.horizontal, 14).padding(.vertical, 3)
            }
        }
        .font(.body)
        .padding(.vertical, 6)
        .frame(width: 300, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor)))
        panel.orderBack(nil)
        try await snapshot(panel, to: url)
        panel.close()
    }

    /// The whole content column, as a person scrolling it would see it.
    static func content(_ model: LibraryModel, to url: URL) async throws {
        let column = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 420, height: 2400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        column.isReleasedWhenClosed = false
        column.contentView = NSHostingView(rootView: ContentColumn().environment(model))
        column.orderBack(nil)
        try await snapshot(column, to: url)
        column.close()
    }

    /// A short H.264 video of `size`, a band crossing a field of `color`: a real movie to play.
    static func writeVideo(to url: URL, size: CGSize, color: NSColor) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        for frame in 0..<20 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let context = try #require(CGContext(
                data: CVPixelBufferGetBaseAddress(pixels), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue))
            context.setFillColor(CGColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(gray: 1, alpha: 0.6))
            context.fill(CGRect(x: size.width * CGFloat(frame) / 20, y: 0, width: size.width / 10, height: size.height))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 10))
        }
        input.markAsFinished()
        await withCheckedContinuation { done in writer.finishWriting { done.resume() } }
        #expect(writer.status == .completed)
    }

    static func window(_ model: LibraryModel, appearance: NSAppearance? = nil) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1320, height: 860),
                              styleMask: [.titled, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Gleaner"
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = NSHostingView(rootView: LibraryView().environment(model))
        window.orderBack(nil)
        return window
    }

    static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await settle(0.05) }
    }

    static func settle(_ seconds: TimeInterval) async throws {
        spin(seconds)
        await Task.yield()
    }

    /// Lets the main run loop draw and lay out the window, and run the work the model queued.
    static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func snapshot(_ window: NSWindow, to url: URL) async throws {
        for _ in 0..<12 { try await settle(0.05) }
        // The content view: the frame view would add the toolbar but draw the sidebar's material blank.
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        // The window's background is drawn by its frame, not the content view: lay it down first,
        // in the window's appearance, so transparent areas read as they do on screen.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (window.appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: view.bounds.size).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}

private extension URL {
    func creating() throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}
