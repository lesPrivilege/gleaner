import Foundation

/// Gleaner's own bytes: saved copies addressed by sha256, and verified hand-off copies.
/// Nothing here ever writes to a project folder.
public struct ContentStore: Sendable {
    public enum Failure: Error, Equatable {
        /// The bytes available no longer hash to the version asked for.
        case changed(expected: String, found: String)
        case unavailable
    }

    public let objects: URL
    public let staging: URL
    private let preparations = Preparations()

    public init(objects: URL, staging: URL) {
        self.objects = objects
        self.staging = staging
    }

    /// Hand-off copies being prepared, by the temporary name each is written under. Clearing
    /// leaves these alone, and never runs while one is being moved into place.
    private final class Preparations: @unchecked Sendable {
        let lock = NSLock()
        var names: Set<String> = []
    }

    /// lstat, not stat: true only for a regular file itself, never for a link to one.
    static func isRegularFile(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular
    }

    public func objectURL(_ sha: String) -> URL {
        objects.appendingPathComponent(String(sha.prefix(2))).appendingPathComponent(sha)
    }

    public func has(_ sha: String) -> Bool {
        FileManager.default.fileExists(atPath: objectURL(sha).path)
    }

    /// Copies a regular file into the store and returns the hash of the stored bytes. The copy is
    /// hashed, not the source, so a write racing the copy can't mislabel what was saved.
    /// On APFS the copy is a clone and costs no space until the source changes. With `expected`,
    /// only those bytes are kept: others throw `Failure.changed` and leave nothing in the store.
    @discardableResult
    public func save(_ path: String, expecting expected: String? = nil) throws -> (sha: String, size: Int64) {
        let fm = FileManager.default
        try fm.createDirectory(at: objects, withIntermediateDirectories: true)
        let temporary = objects.appendingPathComponent(".incoming-\(UUID().uuidString)")
        // Copy what a symlink points at, never the link: a link in the store would follow the
        // live file, and making it read-only would change the project's own file.
        try fm.copyItem(at: URL(fileURLWithPath: path).resolvingSymlinksInPath(), to: temporary)
        guard Self.isRegularFile(temporary), let sha = Locator.sha256(temporary.path) else {
            try? fm.removeItem(at: temporary)
            throw Failure.unavailable
        }
        if let expected, sha != expected {
            try? fm.removeItem(at: temporary)
            throw Failure.changed(expected: expected, found: sha)
        }
        let size = (try? fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        let target = objectURL(sha)
        // A saved copy already there is kept only while it still holds these bytes. One that
        // doesn't, damaged on disk, is replaced by this copy in one rename, so saving again repairs it.
        if Self.isRegularFile(target), Locator.sha256(target.path) == sha {
            try fm.removeItem(at: temporary)
        } else {
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: temporary.path)
                guard rename(temporary.path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            } catch {
                try? fm.removeItem(at: temporary)
                throw error
            }
        }
        return (sha, size)
    }

    /// Removes every hand-off copy but those in `kept`, which were handed out and may still be
    /// read (the one on the clipboard, pasted later). They are disposable: saved copies live in
    /// `objects`. A copy still being prepared is kept, so its preparation still hands over a whole file.
    public func clearStaging(keeping kept: [URL]) throws {
        let fm = FileManager.default
        let kept = kept.map { $0.resolvingSymlinksInPath().path }
        try preparations.lock.withLock {
            guard let items = try? fm.contentsOfDirectory(atPath: staging.path) else { return }
            for item in items where !preparations.names.contains(item) {
                let url = staging.appendingPathComponent(item)
                let folder = url.resolvingSymlinksInPath().path
                if kept.contains(where: { $0 == folder || $0.hasPrefix(folder + "/") }) { continue }
                try fm.removeItem(at: url)
            }
        }
    }

    /// A hand-off copy Gleaner hashed, and how to tell it is still that file: its identity then.
    public struct Prepared: Sendable, Equatable {
        public var url: URL
        public var sha: String
        let identity: Identity
    }

    /// What a file's inode says about it. Writing to the file changes its change time, which no
    /// app can set back, and replacing it gives the path another inode: while this is the same, the
    /// file holds the bytes it held when this was read.
    struct Identity: Sendable, Equatable {
        var device: Int32, inode: UInt64, size: Int64
        var modified: Int, modifiedNanos: Int, changed: Int, changedNanos: Int

        init?(_ url: URL) {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
            device = info.st_dev
            inode = info.st_ino
            size = info.st_size
            modified = info.st_mtimespec.tv_sec
            modifiedNanos = info.st_mtimespec.tv_nsec
            changed = info.st_ctimespec.tv_sec
            changedNanos = info.st_ctimespec.tv_nsec
        }
    }

    /// True while the prepared copy is the very file Gleaner hashed, unchanged since.
    public func isIntact(_ prepared: Prepared) -> Bool {
        Identity(prepared.url) == prepared.identity
    }

    /// An immutable copy of the version `sha`, named `name`, ready to hand to another app.
    public func stage(sha: String, name: String, source: String?) throws -> URL {
        try prepare(sha: sha, name: name, source: source).url
    }

    /// `stage`, with what tells later whether the copy is still the one hashed (`isIntact`).
    /// It is copied from the saved copy when there is one and from `source` when that copy doesn't
    /// hash to `sha`, and handed out only if the copy itself hashes to `sha`. The copy is made under a name of its own and published
    /// whole by one rename, so overlapping stages of a version never remove or truncate each
    /// other's file, and clearing hand-off copies meanwhile never removes it. A copy already there
    /// is hashed again and used only while it hashes to `sha` and stayed the same file throughout.
    public func prepare(sha: String, name: String, source: String?) throws -> Prepared {
        let fm = FileManager.default
        let directory = staging.appendingPathComponent(sha)
        let target = directory.appendingPathComponent(name)
        // Kept read-only: another app may have made it writable while leaving its bytes alone.
        if Identity(target) != nil, (try? fm.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int) != 0o444 {
            try? fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: target.path)
        }
        if let before = Identity(target), Locator.sha256(target.path) == sha, Identity(target) == before {
            return Prepared(url: target, sha: sha, identity: before)
        }

        // The saved copy first, then the file itself: a saved copy damaged on disk doesn't keep a
        // file that still holds the bytes from being handed over.
        let origins = (has(sha) ? [objectURL(sha).path] : []) + (source.map { [$0] } ?? [])
        guard !origins.isEmpty else { throw Failure.unavailable }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let incoming = ".incoming-\(UUID().uuidString)"
        let temporary = staging.appendingPathComponent(incoming)
        preparations.lock.withLock { _ = preparations.names.insert(incoming) }
        defer {
            try? fm.removeItem(at: temporary)
            preparations.lock.withLock { _ = preparations.names.remove(incoming) }
        }
        var hashed: Identity?
        var failure: Error?
        for origin in origins {
            try? fm.removeItem(at: temporary)
            do {
                try fm.copyItem(at: URL(fileURLWithPath: origin).resolvingSymlinksInPath(), to: temporary)
                try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: temporary.path)
                hashed = Identity(temporary)
                let found = hashed != nil ? Locator.sha256(temporary.path) ?? "" : ""
                guard found == sha else { throw Failure.changed(expected: sha, found: found) }
                failure = nil
                break
            } catch {
                // The first origin's failure is the one said: the saved copy's, when there is one.
                failure = failure ?? error
                hashed = nil
            }
        }
        if let failure { throw failure }
        // Published and read under the lock clearing and other stages take, so what is read is this
        // copy. The rename may stamp a new change time; the inode and the bytes' modification time
        // say it is still the file hashed.
        let published = try preparations.lock.withLock {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            guard rename(temporary.path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return Identity(target)
        }
        guard let published, let hashed, published.inode == hashed.inode, published.size == hashed.size,
              published.modified == hashed.modified, published.modifiedNanos == hashed.modifiedNanos
        else { throw Failure.changed(expected: sha, found: "") }
        return Prepared(url: target, sha: sha, identity: published)
    }
}
