#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(Darwin)
import Darwin
private typealias NativeStat = Darwin.stat
#else
import Glibc
private typealias NativeStat = Glibc.stat
#endif
import Foundation
import GleanerCore

/// Development experiment only. An observation of the current original never completes a
/// capture, changes a review, or proves that these were the bytes delivered in the past.
/// No registry is accepted by this API. The caller supplies scope; cwd is never authority.
public enum OriginalResolutionExperiment {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case pathOnly = "path_only", metadata, hashCurrent = "hash_current"
    }

    public enum EvidenceKind: String, Codable, Sendable {
        case explicitDelivery = "explicit_delivery", folderMember = "folder_member", kept
    }

    public enum State: String, Codable, Sendable {
        case unverifiedPath = "unverified_path", metadataOnly = "metadata_only", hashedCurrent = "hashed_current"
        case missing, unreadable, notRegular = "not_regular", deniedScope = "denied_scope"
        case changedDuringObservation = "changed_during_observation", hashLimitExceeded = "hash_limit_exceeded"
    }

    /// Device/inode and change time supplement size/mtime, as the shared core's FileStat does.
    /// Integer timestamps preserve the descriptor's precision when checking concurrent writes.
    public struct Metadata: Codable, Sendable, Equatable {
        public var size: Int64
        public var device: UInt64
        public var inode: UInt64
        public var modifiedSeconds: Int64
        public var modifiedNanoseconds: Int64
        public var changedSeconds: Int64
        public var changedNanoseconds: Int64

        fileprivate init(_ info: NativeStat) {
            size = Int64(info.st_size)
            #if canImport(Darwin)
            // Darwin dev_t is signed; its identifier's bit pattern is not a negative size.
            device = UInt64(UInt32(bitPattern: info.st_dev))
            #else
            device = UInt64(info.st_dev)
            #endif
            inode = UInt64(info.st_ino)
            #if canImport(Darwin)
            let modified = info.st_mtimespec, changed = info.st_ctimespec
            #else
            let modified = info.st_mtim, changed = info.st_ctim
            #endif
            modifiedSeconds = Int64(modified.tv_sec)
            modifiedNanoseconds = Int64(modified.tv_nsec)
            changedSeconds = Int64(changed.tv_sec)
            changedNanoseconds = Int64(changed.tv_nsec)
        }
    }

    public struct Current: Codable, Sendable {
        public var path: String
        public var state: State
        public var checkedAt: Date
        /// Nil when no file metadata/bytes were observed, including path-only mode.
        public var observedAt: Date?
        public var metadata: Metadata?
        public var observedCurrentSha256: String?
        /// Only compares bytes with a recorded capture. Capture provenance still determines
        /// whether that capture was at delivery or first seen later.
        public var matchesCapturedBytes: Bool?
        public var reason: String?
    }

    public struct Result: Codable, Sendable {
        public var deliveryID: String
        public var provider: String
        public var sessionID: String
        public var evidenceKind: EvidenceKind
        public var evidence: [Evidence]
        public var folderDeliveryID: String?
        public var keptAt: Date?
        public var captureState: Provenance?
        public var capturedSha256: String?
        public var mode: Mode
        public var current: Current
        public var bytesRead: UInt64
        public var elapsedNanoseconds: UInt64
    }

    /// Path-only mode applies lexical scope and returns an explicitly unverified locator without
    /// disk access. Parent (`..`) components are refused in locators and authorized roots rather
    /// than collapsed across a possible symlink. Checked modes reject every symlink in the path,
    /// including root ancestors.
    /// Hash mode reads at most `hashByteLimit + 1` bytes (one EOF/overflow sentinel), uses a
    /// 256 KiB read buffer, and refuses a hash if metadata or reopened path identity changes. It returns
    /// no staged bytes: using this path later requires another check.
    public static func resolve(delivery: Delivery, mode: Mode, authorizedRoots: [URL],
                               hashByteLimit: Int64 = 64 << 20) -> Result {
        resolve(delivery: delivery, mode: mode, authorizedRoots: authorizedRoots,
                hashByteLimit: hashByteLimit, afterChunk: nil)
    }

    /// Deterministic mutation hook for the experimental tests; not a production callback API.
    static func resolve(delivery: Delivery, mode: Mode, authorizedRoots: [URL],
                        hashByteLimit: Int64, afterChunk: ((UInt64) -> Void)?) -> Result {
        let started = DispatchTime.now().uptimeNanoseconds
        var current = Current(path: delivery.path, state: .unverifiedPath, checkedAt: Date())
        var bytesRead: UInt64 = 0
        func finish() -> Result {
            Result(deliveryID: delivery.id, provider: delivery.provider.rawValue, sessionID: delivery.sessionID,
                   evidenceKind: delivery.kept != nil ? .kept : delivery.member != nil ? .folderMember : .explicitDelivery,
                   evidence: delivery.evidence, folderDeliveryID: delivery.member?.folderDelivery,
                   keptAt: delivery.kept?.keptAt, captureState: delivery.capture?.provenance,
                   capturedSha256: delivery.sha256, mode: mode, current: current, bytesRead: bytesRead,
                   elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started)
        }
        guard let path = absolute(delivery.path), authorizedRoots.contains(where: { root in
            guard root.isFileURL, let rootPath = absolute(root.path) else { return false }
            return path == rootPath || path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
        }) else {
            current.state = .deniedScope
            current.reason = "The original is outside the explicit roots or uses an unsupported parent traversal."
            return finish()
        }
        current.path = path
        guard mode != .pathOnly else { return finish() }

        do {
            let descriptor = try openOriginal(path)
            defer { _ = close(descriptor) }
            let before = try metadata(descriptor)
            current.metadata = before
            current.observedAt = Date()
            current.state = .metadataOnly
            guard mode == .hashCurrent else { return finish() }
            guard hashByteLimit >= 0, before.size <= hashByteLimit else {
                throw Failure(.hashLimitExceeded, "The current file exceeds the requested hash byte limit.")
            }
            let hash = try hashCurrent(descriptor, limit: UInt64(hashByteLimit), bytesRead: &bytesRead, afterChunk: afterChunk)
            guard try metadata(descriptor) == before else {
                throw Failure(.changedDuringObservation, "The opened file changed while it was observed.")
            }
            let reopened: Int32
            do { reopened = try openOriginal(path) }
            catch let failure as Failure where failure.state == .deniedScope { throw failure }
            catch { throw Failure(.changedDuringObservation, "The original path no longer identifies the opened file.") }
            defer { _ = close(reopened) }
            guard try metadata(reopened) == before else {
                throw Failure(.changedDuringObservation, "The original path now identifies different bytes or a different file.")
            }
            current.state = .hashedCurrent
            current.observedAt = Date()
            current.observedCurrentSha256 = hash
            current.matchesCapturedBytes = delivery.sha256.map { $0 == hash }
        } catch let failure as Failure {
            current.state = failure.state
            current.reason = failure.reason
        } catch {
            current.state = .unreadable
            current.reason = "The current original could not be observed."
        }
        return finish()
    }

    private struct Failure: Error {
        var state: State
        var reason: String
        init(_ state: State, _ reason: String) { self.state = state; self.reason = reason }
    }

    private static func absolute(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        // Scope comparison must be lexical. Foundation may shorten /private/var to /var
        // even after resolvingSymlinksInPath, introducing an ancestor link that the descriptor
        // walk deliberately rejects. Do not resolve links or consult existence here, including
        // for path-only mode; preserve the caller's physical spelling.
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            // Collapsing link/.. can change the meaning of a pathname and its scope.
            case "..": return nil
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Follow directory descriptors, never symlinks. This is a conservative experimental scope
    /// policy: a link within the same root is denied too, not called missing. Parent directories
    /// are pinned as capabilities while walking; the full path is checked again after hashing.
    private static func openOriginal(_ path: String) throws -> Int32 {
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { throw Failure(.notRegular, "The original is a directory.") }
        var directory = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { throw systemFailure() }
        defer { _ = close(directory) }
        for part in parts.dropLast() {
            let next = try openChild(part, in: directory, directory: true)
            _ = close(directory)
            directory = next
        }
        return try openChild(parts.last!, in: directory, directory: false)
    }

    private static func openChild(_ name: String, in parent: Int32, directory: Bool) throws -> Int32 {
        var before = NativeStat()
        guard fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW) == 0 else { throw systemFailure() }
        if before.st_mode & S_IFMT == S_IFLNK {
            throw Failure(.deniedScope, "Checked modes conservatively reject symbolic links, including root ancestors.")
        }
        guard before.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else {
            throw Failure(.notRegular, directory ? "A path component is not a directory." : "The original is not a regular file.")
        }
        let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (directory ? O_DIRECTORY : 0)
        let descriptor = openat(parent, name, flags)
        guard descriptor >= 0 else { throw systemFailure() }
        var after = NativeStat()
        guard fstat(descriptor, &after) == 0, after.st_dev == before.st_dev,
              after.st_ino == before.st_ino, after.st_mode & S_IFMT == before.st_mode & S_IFMT else {
            _ = close(descriptor)
            throw Failure(.changedDuringObservation, "A path component changed while it was opened.")
        }
        return descriptor
    }

    private static func metadata(_ descriptor: Int32) throws -> Metadata {
        var info = NativeStat()
        guard fstat(descriptor, &info) == 0 else { throw systemFailure() }
        guard info.st_mode & S_IFMT == S_IFREG else { throw Failure(.notRegular, "The original is not a regular file.") }
        return Metadata(info)
    }

    /// Uses the same SHA256 implementation as Locator/Comparison. Their public APIs read by
    /// pathname without a byte bound; this experiment needs a pinned descriptor and bounded I/O.
    private static func hashCurrent(_ descriptor: Int32, limit: UInt64, bytesRead: inout UInt64,
                                    afterChunk: ((UInt64) -> Void)?) throws -> String {
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 256 << 10)
        while true {
            let remaining = limit - bytesRead
            let wanted = remaining == 0 ? 1 : Int(min(UInt64(buffer.count), remaining))
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress!, wanted) }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw systemFailure()
            }
            bytesRead += UInt64(count)
            guard bytesRead <= limit else { throw Failure(.hashLimitExceeded, "The file grew beyond the requested hash byte limit.") }
            hasher.update(data: Data(buffer.prefix(count)))
            afterChunk?(bytesRead)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func systemFailure() -> Failure {
        switch errno {
        case ENOENT, ENOTDIR: Failure(.missing, "The original or a containing directory is missing.")
        case ELOOP: Failure(.deniedScope, "A symbolic link cannot be used by checked modes.")
        default: Failure(.unreadable, "The original or a containing directory could not be read.")
        }
    }
}
