import CoreServices
import Foundation

/// Calls back when anything under the agents' log directories changes (SPEC §7). Only the log
/// directories are watched, never the delivered files themselves.
public final class LogWatcher {
    private final class Box {
        let onChange: () -> Void
        init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    }

    private let directories: [String]
    private let latency: TimeInterval
    private let queue: DispatchQueue
    private let box: Box
    private var stream: FSEventStreamRef?
    private var watched: [String] = []

    public init(directories: [String], latency: TimeInterval = 2, queue: DispatchQueue, onChange: @escaping () -> Void) {
        self.directories = directories
        self.latency = latency
        self.queue = queue
        box = Box(onChange)
        refresh()
    }

    /// Watches the directories that exist now. FSEvents cannot watch a folder before it exists,
    /// so one that appears later (an agent run here for the first time) is watched from the next
    /// call; the library calls this whenever it rereads the logs.
    public func refresh() {
        let existing = directories.filter { FileManager.default.fileExists(atPath: $0) }
        guard existing != watched else { return }
        stop()
        watched = existing
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Box>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        stream = FSEventStreamCreate(
            nil, callback, &context, existing as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    private func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
