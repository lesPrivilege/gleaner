import CoreServices
import Foundation

/// Calls back when anything under the agents' log directories changes (SPEC §7). Only the log
/// directories are watched, never the delivered files themselves. While one does not exist yet,
/// its nearest existing parent is watched, only to notice it appear.
public final class LogWatcher {
    private final class Box: @unchecked Sendable {
        let directories: [String]
        let onChange: () -> Void
        private let lock = NSLock()
        private var roots: [String] = []

        init(directories: [String], onChange: @escaping () -> Void) {
            self.directories = directories
            self.onChange = onChange
        }

        var watched: [String] {
            get { lock.withLock { roots } }
            set { lock.withLock { roots = newValue } }
        }

        /// A change under a parent watched for a missing log folder matters only once a folder on
        /// the way to it appears or goes; anything else is a change to the logs. FSEvents names
        /// paths with their symbolic links resolved, so they are compared that way.
        func changed(_ paths: [String]) {
            let watched = watched
            let parents = watched.filter { !directories.contains($0) }.map(LogWatcher.resolved)
            let logs = directories.map(LogWatcher.resolved)
            let elsewhere = paths.allSatisfy { path in
                parents.contains { LogWatcher.path(path, isIn: $0) } && !logs.contains { LogWatcher.path(path, isIn: $0) }
            }
            if !elsewhere || LogWatcher.roots(directories) != watched { onChange() }
        }
    }

    private let latency: TimeInterval
    private let queue: DispatchQueue
    private let box: Box
    private var stream: FSEventStreamRef?

    public init(directories: [String], latency: TimeInterval = 2, queue: DispatchQueue, onChange: @escaping () -> Void) {
        self.latency = latency
        self.queue = queue
        box = Box(directories: directories, onChange: onChange)
        refresh()
    }

    /// Each directory, or while it is missing, its nearest existing parent: FSEvents reports
    /// nothing for a path that did not exist when its stream was made.
    static func roots(_ directories: [String]) -> [String] {
        directories.map { directory in
            var path = directory
            while path != "/", !FileManager.default.fileExists(atPath: path) { path = (path as NSString).deletingLastPathComponent }
            return path
        }
    }

    static func resolved(_ path: String) -> String {
        guard let real = realpath(path, nil) else { return path }
        defer { free(real) }
        return String(cString: real)
    }

    static func path(_ path: String, isIn folder: String) -> Bool {
        path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    /// Watches each log directory, or the parent a missing one would appear in. When a folder on
    /// the way appears or goes, the stream is made again; the library calls this whenever it
    /// rereads the logs, which such a change sets off.
    public func refresh() {
        let roots = Self.roots(box.directories)
        guard roots != box.watched else { return }
        stop()
        box.watched = roots
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let paths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            Unmanaged<Box>.fromOpaque(info).takeUnretainedValue().changed((0..<count).map { String(cString: paths[$0]) })
        }
        stream = FSEventStreamCreate(
            nil, callback, &context, Array(Set(roots)) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
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
