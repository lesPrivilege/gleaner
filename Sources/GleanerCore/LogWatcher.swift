import CoreServices
import Foundation

/// Calls back when anything under the agents' log directories changes (SPEC §7). Only the log
/// directories are watched, never the delivered files themselves.
public final class LogWatcher {
    private final class Box {
        let onChange: () -> Void
        init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    }

    private var stream: FSEventStreamRef?
    private let box: Box

    public init(directories: [String], latency: TimeInterval = 2, queue: DispatchQueue, onChange: @escaping () -> Void) {
        box = Box(onChange)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Box>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        let existing = directories.filter { FileManager.default.fileExists(atPath: $0) }
        stream = FSEventStreamCreate(
            nil, callback, &context, existing as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
