import Foundation
import Testing
@testable import GleanerCore

@Suite struct LogWatcherTests {
    private final class Changes: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func add() { lock.withLock { count += 1 } }
        var seen: Bool { lock.withLock { count > 0 } }
    }

    @Test func aLogFolderCreatedAfterLaunchIsWatchedOnceTheLogsAreReread() async throws {
        let sessions = FileManager.default.temporaryDirectory
            .appendingPathComponent("gleaner-watch-\(UUID().uuidString)/codex/sessions")
        let changes = Changes()
        let watcher = LogWatcher(directories: [sessions.path], latency: 0.1, queue: DispatchQueue(label: "gleaner.test.watch")) {
            changes.add()
        }
        // Codex runs for the first time while Gleaner is open.
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        watcher.refresh()
        try "{}\n".write(to: sessions.appendingPathComponent("rollout-1.jsonl"), atomically: false, encoding: .utf8)

        var waited = 0
        while !changes.seen && waited < 30 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        #expect(changes.seen)
        withExtendedLifetime(watcher) {}
    }
}
