import Foundation
import Testing
@testable import GleanerCore

@Suite struct LogWatcherTests {
    private final class Changes: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func add() { lock.withLock { count += 1 } }
        func reset() { lock.withLock { count = 0 } }
        var seen: Bool { lock.withLock { count > 0 } }
    }

    private func waitForChange(_ changes: Changes) async throws {
        var waited = 0
        while !changes.seen && waited < 30 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
    }

    @Test func aLogFolderCreatedAfterLaunchIsNoticedAndThenWatched() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("gleaner-watch-\(UUID().uuidString)")
        let sessions = home.appendingPathComponent("codex/sessions")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let changes = Changes()
        let watcher = LogWatcher(directories: [sessions.path], latency: 0.1, queue: DispatchQueue(label: "gleaner.test.watch")) {
            changes.add()
        }
        // Other files in the folder it would appear in are not log changes.
        try await Task.sleep(for: .milliseconds(300))
        try "notes".write(to: home.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(1))
        #expect(!changes.seen)

        // Codex runs for the first time while Gleaner is open: its folder appearing is a change.
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try await waitForChange(changes)
        #expect(changes.seen)

        // The library rereads on that change, which watches the new folder from then on.
        watcher.refresh()
        changes.reset()
        try "{}\n".write(to: sessions.appendingPathComponent("rollout-1.jsonl"), atomically: false, encoding: .utf8)
        try await waitForChange(changes)
        #expect(changes.seen)
        withExtendedLifetime(watcher) {}
    }
}
