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

    public init(objects: URL, staging: URL) {
        self.objects = objects
        self.staging = staging
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
    /// On APFS the copy is a clone and costs no space until the source changes.
    @discardableResult
    public func save(_ path: String) throws -> (sha: String, size: Int64) {
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
        let size = (try? fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        let target = objectURL(sha)
        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: temporary)
        } else {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: temporary, to: target)
            try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: target.path)
        }
        return (sha, size)
    }

    /// An immutable copy of the version `sha`, named `name`, ready to hand to another app.
    /// It is copied from the saved copy when there is one, else from `source`, and handed out only
    /// if the copy itself hashes to `sha`.
    public func stage(sha: String, name: String, source: String?) throws -> URL {
        let fm = FileManager.default
        let directory = staging.appendingPathComponent(sha)
        let target = directory.appendingPathComponent(name)
        if fm.fileExists(atPath: target.path), Locator.sha256(target.path) == sha { return target }

        let origin: String
        if has(sha) {
            origin = objectURL(sha).path
        } else if let source {
            origin = source
        } else {
            throw Failure.unavailable
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) {
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
            try fm.removeItem(at: target)
        }
        try fm.copyItem(at: URL(fileURLWithPath: origin).resolvingSymlinksInPath(), to: target)
        let found = Self.isRegularFile(target) ? Locator.sha256(target.path) ?? "" : ""
        guard found == sha else {
            try? fm.removeItem(at: target)
            throw Failure.changed(expected: sha, found: found)
        }
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: target.path)
        return target
    }
}
