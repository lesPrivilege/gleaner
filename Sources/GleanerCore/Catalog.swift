import Foundation

/// Read-only queries over the library, for a local agent and for anything else outside the app
/// (docs/design/query-core.md). It opens the registry to read only, never indexes, and never
/// writes a project folder. Every answer carries the index it is evidence of (`Index`).
public struct Catalog {
    public let registry: Registry
    public let store: ContentStore

    public init(registry: Registry, store: ContentStore) {
        self.registry = registry
        self.store = store
    }

    /// The library where the app keeps it: Application Support, and Caches for hand-off copies.
    /// `home` stands in for the home folder, as the app's `-GleanerHome` does.
    public init(home: URL? = nil) throws {
        let fm = FileManager.default
        let library = home.map { $0.appendingPathComponent("Library") }
        let support = (library?.appendingPathComponent("Application Support")
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).appendingPathComponent("Gleaner")
        let caches = (library?.appendingPathComponent("Caches")
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]).appendingPathComponent("Gleaner")
        self.init(
            registry: try Registry(readingAt: support.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: support.appendingPathComponent("objects"), staging: caches.appendingPathComponent("handoff")))
    }

    /// How answers are written as JSON: snake_case keys, ISO 8601 dates, keys sorted, paths as they are.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Reads what `encoder` wrote.
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension Catalog {
    /// Why the catalog can't answer, each with the exit code the `gleaner` command gives it.
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// No library at this path: Gleaner never ran with this home.
        case noLibrary(String)
        /// The library at this path is of another version of Gleaner. There is no compatibility mode.
        case wrongVersion(String, found: Int)

        /// 3: no library, or the wrong version.
        public var exitCode: Int32 {
            switch self {
            case .noLibrary, .wrongVersion: 3
            }
        }

        public var description: String {
            switch self {
            case .noLibrary(let path):
                "There is no Gleaner library at \(path). Open Gleaner to make one."
            case .wrongVersion(let path, let found):
                "The Gleaner library at \(path) is version \(found); this reads version \(Registry.extractorVersion). Open Gleaner to update it."
            }
        }
    }

    /// What an answer is evidence of (query-core "Freshness"): the library, and its last completed
    /// run. An empty answer is not evidence of absence before the first run (generation 0), from a
    /// stale run, or for a source that couldn't be read or was read with problems.
    public struct Index: Codable, Equatable, Sendable {
        /// The namespace of every delivery id.
        public var library: String
        /// Completed runs of the indexer; 0 before the first.
        public var generation: Int
        /// When the last completed run finished; nil before the first.
        public var scannedAt: Date?
        /// How each agent's logs read in that run, by provider (`claude-code`, `codex`).
        public var sources: [String: Source]

        // `scanned_at` is written as null, not left out, before the first run.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(library, forKey: .library)
            try container.encode(generation, forKey: .generation)
            try container.encode(scannedAt, forKey: .scannedAt)
            try container.encode(sources, forKey: .sources)
        }
    }

    /// One agent's log folder as a run read it (SPEC §8), with what went wrong counted. What the
    /// library holds from a source that is unreadable or read with problems may be incomplete.
    public struct Source: Codable, Equatable, Sendable {
        public enum State: String, Codable, Sendable {
            /// Not on this Mac.
            case absent
            /// There, but it couldn't be listed (`reason`).
            case unreadable
            case read
            /// Listed, but not everything in it could be read or understood.
            case readWithProblems = "read_with_problems"
        }

        public var state: State
        /// Why the folder couldn't be listed.
        public var reason: String?
        /// Record types the adapter doesn't recognize, with counts.
        public var unknownRecordTypes: [String: Int] = [:]
        /// Logs with malformed lines.
        public var partialLogs = 0
        /// Logs found shorter than when Gleaner read them: records were lost.
        public var shortenedLogs = 0
        /// Logs that couldn't be read or stored.
        public var failures = 0
        /// Folders in it that couldn't be listed.
        public var unlistedFolders = 0
    }
}

extension Catalog.Source {
    init(_ source: Indexer.Report.Source) {
        switch source.folder {
        case .absent: state = .absent
        case .unreadable(let why): state = .unreadable; reason = why
        case .listed: state = source.hasProblems ? .readWithProblems : .read
        }
        unknownRecordTypes = source.unknownRecordTypes
        partialLogs = source.partialLogs.count
        shortenedLogs = source.shortenedLogs.count
        failures = source.failures.count
        unlistedFolders = source.unlistedFolders.count
    }
}
