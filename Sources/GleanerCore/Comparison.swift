import CryptoKit
import Foundation

/// Two exact versions of one artifact, compared read-only. Each end names its bytes and their
/// hash; content that no longer hashes to it is refused rather than compared. Each end is read
/// once, from a regular file only, and what is compared is exactly what was hashed.
public enum Comparison {
    public struct End: Sendable, Equatable {
        /// "Delivery 3", "File on disk".
        public var title: String
        /// "saved copy", "file on disk".
        public var source: String
        public var sha: String
        public var url: URL

        public init(title: String, source: String, sha: String, url: URL) {
            self.title = title
            self.source = source
            self.sha = sha
            self.url = url
        }
    }

    public struct Bytes: Sendable, Equatable {
        public var size: Int64
        public var sha: String
    }

    public enum Content: Sendable, Equatable {
        case text(TextDiff.Outcome)
        /// Each image's bytes as they were hashed, never a path that could change after the check.
        case images(Data, Data)
        case bytes(Bytes, Bytes)
        case failed(String)
    }

    /// Text kinds get a line diff, images a side-by-side view, everything else sizes and hashes.
    /// A text kind that is not text (a PDF, a spreadsheet) is compared by size and hash too, at
    /// any size; text over the limit is reported as limited.
    public static func load(_ from: End, _ to: End, kind: Artifact.Kind) -> Content {
        if from.sha == to.sha, kind != .image {
            return .text(.rows([]))
        }
        let keep = switch kind {
        case .image: Int.max
        case .document, .code, .data, .web: TextDiff.maxBytes
        default: 0
        }
        let old: Read, new: Read
        switch (read(from, keeping: keep), read(to, keeping: keep)) {
        case (.failure(let reason), _), (_, .failure(let reason)):
            return .failed(reason.message)
        case (.success(let a), .success(let b)):
            (old, new) = (a, b)
        }
        let sizes = Content.bytes(Bytes(size: old.size, sha: from.sha), Bytes(size: new.size, sha: to.sha))
        switch kind {
        case .image:
            return .images(old.data, new.data)
        case .document, .code, .data, .web:
            guard isText(old), isText(new) else { return sizes }
            guard old.isWhole, new.isWhole else {
                return .text(.limited("One version is larger than \(TextDiff.maxBytes >> 10) KB."))
            }
            return .text(TextDiff.compare(String(decoding: old.data, as: UTF8.self), String(decoding: new.data, as: UTF8.self)))
        default:
            return sizes
        }
    }

    struct Failure: Error { var message: String }

    /// One end as read: its size, and its first bytes up to what the comparison needs.
    struct Read {
        var data = Data()
        var size: Int64 = 0
        var isWhole: Bool { Int64(data.count) == size }
    }

    /// Reads an end once, hashing as it goes, and keeps its first `limit` bytes. Only a regular
    /// file is opened, as for staging: opening a pipe would block for ever.
    static func read(_ end: End, keeping limit: Int) -> Result<Read, Failure> {
        let unreadable = Failure(message: "\(end.title) can no longer be read.")
        let url = end.url.resolvingSymlinksInPath()
        guard ContentStore.isRegularFile(url), let handle = try? FileHandle(forReadingFrom: url) else {
            return .failure(unreadable)
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        var read = Read()
        do {
            while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
                read.size += Int64(chunk.count)
                if read.data.count < limit { read.data.append(chunk.prefix(limit - read.data.count)) }
            }
        } catch {
            return .failure(unreadable)
        }
        guard hasher.finalize().map({ String(format: "%02x", $0) }).joined() == end.sha else {
            return .failure(Failure(message: "\(end.title) changed since Gleaner checked it. Check again."))
        }
        return .success(read)
    }

    /// Strict UTF-8 without NUL bytes; anything else is compared as bytes. When only the start of
    /// a file was read, a character the cut splits still counts as text.
    static func isText(_ read: Read) -> Bool {
        let cut = read.isWhole ? 0 : 3
        return !read.data.contains(0) && (0...cut).contains { String(data: read.data.dropLast($0), encoding: .utf8) != nil }
    }
}
