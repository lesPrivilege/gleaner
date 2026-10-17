import CryptoKit
import Foundation

/// Two exact versions of one artifact, compared read-only. Each end names its bytes and their
/// hash; content that no longer hashes to it is refused rather than compared.
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
        case images(URL, URL)
        case bytes(Bytes, Bytes)
        case failed(String)
    }

    /// Text kinds get a line diff, images a side-by-side view, everything else sizes and hashes.
    public static func load(_ from: End, _ to: End, kind: Artifact.Kind) -> Content {
        if from.sha == to.sha, kind != .image {
            return .text(.rows([]))
        }
        for end in [from, to] where Locator.sha256(end.url.path) != end.sha {
            return .failed("\(end.title) changed since Gleaner checked it. Check again.")
        }
        switch kind {
        case .image:
            return .images(from.url, to.url)
        case .document, .code, .data, .web:
            switch (read(from), read(to)) {
            case (.failure(let reason), _), (_, .failure(let reason)):
                return .failed(reason.message)
            case (.success(let old), .success(let new)):
                guard let a = text(old), let b = text(new) else { return bytes(from, to) }
                return .text(TextDiff.compare(a, b))
            }
        default:
            return bytes(from, to)
        }
    }

    struct Failure: Error { var message: String }

    static func read(_ end: End) -> Result<Data, Failure> {
        let size = (try? FileManager.default.attributesOfItem(atPath: end.url.path)[.size] as? NSNumber)?.intValue
        guard let size else { return .failure(Failure(message: "\(end.title) can no longer be read.")) }
        if size > TextDiff.maxBytes {
            return .failure(Failure(message: "\(end.title) is larger than \(TextDiff.maxBytes >> 10) KB. Read either exact version on its own."))
        }
        guard let data = try? Data(contentsOf: end.url) else {
            return .failure(Failure(message: "\(end.title) can no longer be read."))
        }
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == end.sha else {
            return .failure(Failure(message: "\(end.title) changed since Gleaner checked it. Check again."))
        }
        return .success(data)
    }

    /// Strict UTF-8 without NUL bytes; anything else is compared as bytes.
    static func text(_ data: Data) -> String? {
        guard !data.contains(0), let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func bytes(_ from: End, _ to: End) -> Content {
        func size(_ end: End) -> Int64 {
            (try? FileManager.default.attributesOfItem(atPath: end.url.path)[.size] as? NSNumber)?.int64Value ?? 0
        }
        return .bytes(Bytes(size: size(from), sha: from.sha), Bytes(size: size(to), sha: to.sha))
    }
}
