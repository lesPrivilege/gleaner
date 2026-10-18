import AppKit
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
        model.sourcePage = .corrections
        try await shot("sources-corrections")

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

        // Every mark, at the sizes the window uses it.
        let sheet = VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(stride(from: 0, to: Glyph.allCases.count, by: 7)), id: \.self) { start in
                HStack(spacing: 18) {
                    ForEach(Array(Glyph.allCases[start..<min(start + 7, Glyph.allCases.count)].enumerated()), id: \.offset) { _, glyph in
                        VStack(spacing: 4) {
                            GlyphView(glyph: glyph, size: 32)
                            HStack(spacing: 6) { GlyphView(glyph: glyph, size: 16); GlyphView(glyph: glyph, size: 11) }
                            Text(String(describing: glyph)).font(.system(size: 10))
                        }
                        .frame(width: 76)
                    }
                }
            }
        }
        .padding(20).background(Color.white).foregroundStyle(Color.black)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try #require(renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        step += 1
        try #require(image.representation(using: .png, properties: [:]))
            .write(to: out.appendingPathComponent(String(format: "%02d-marks.png", step)))
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
