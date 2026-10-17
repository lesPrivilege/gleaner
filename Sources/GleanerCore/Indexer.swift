import CryptoKit
import Foundation

/// Where the agents keep their logs.
public struct LogSources: Sendable {
    public var claudeProjects: URL
    public var codexHome: URL

    public init(claudeProjects: URL, codexHome: URL) {
        self.claudeProjects = claudeProjects
        self.codexHome = codexHome
    }

    public static var standard: LogSources {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return LogSources(
            claudeProjects: home.appendingPathComponent(".claude/projects"),
            codexHome: home.appendingPathComponent(".codex"))
    }

    /// The folder holding each agent's session logs.
    public func folder(_ provider: Provider) -> URL {
        switch provider {
        case .claudeCode: claudeProjects
        case .codex: codexHome.appendingPathComponent("sessions")
        }
    }

    public var watchedDirectories: [String] { Provider.allCases.map { folder($0).path } }

    /// One agent's session logs, and how its folder read (SPEC §8). A folder that is missing or
    /// can't be listed is reported, never taken for an empty one.
    public func logs(_ provider: Provider) -> (source: Indexer.Report.Source, files: [URL]) {
        let folder = folder(provider)
        guard FileManager.default.fileExists(atPath: folder.path) else { return (Indexer.Report.Source(folder: .absent), []) }
        do {
            let (logs, unlisted) = switch provider {
            case .claudeCode: try ClaudeCodeAdapter.sessionFiles(root: folder)
            case .codex: try CodexAdapter.sessionFiles(root: folder)
            }
            return (Indexer.Report.Source(folder: .listed, unlistedFolders: unlisted), logs)
        } catch {
            return (Indexer.Report.Source(folder: .unreadable(error.localizedDescription)), [])
        }
    }
}

extension DeliveryCandidate {
    /// Stable for a given reply and path, so re-reading a log never duplicates a delivery.
    public func id(logPath: String) -> String {
        Self.id(logPath: logPath, line: evidence[0].part.line, path: path)
    }

    /// The id of a delivery of `path` whose first mention is in the reply record at `line`.
    static func id(logPath: String, line: Int, path: String) -> String {
        let key = "\(logPath)\n\(line)\n\(path)"
        return SHA256.hash(data: Data(key.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
}

/// Reads changed logs into the registry and captures each new delivery's bytes once.
public final class Indexer: @unchecked Sendable {
    /// What a run read. Each agent's logs are reported apart, so a source that is missing,
    /// unreadable or read with problems never looks like one that delivered nothing (SPEC §8).
    public struct Report: Sendable {
        /// How one agent's log folder read.
        public struct Source: Sendable, Equatable {
            public enum Folder: Sendable, Equatable {
                /// Not on this Mac.
                case absent
                /// There, but could not be listed, with the reason. What the library holds stays.
                case unreadable(String)
                case listed
            }

            public var folder: Folder
            /// Record types the adapter does not recognize in the folder's logs, with counts, whichever
            /// run read them. Non-empty means the format moved; reading again can't change it.
            public var unknownRecordTypes: [String: Int] = [:]
            /// Logs with malformed lines. What they name was added and nothing was removed; they are
            /// read again next run.
            public var partialLogs: [String] = []
            /// Logs shorter than when they were last read whole: records were lost. What they name
            /// was added and nothing was removed; they are read again next run, but reading again
            /// can't bring the records back.
            public var shortenedLogs: [String] = []
            /// Logs that could not be read or stored, with the reason. Their deliveries stay as they were.
            public var failures: [String] = []
            /// Folders in it that could not be listed, with the reason. Their logs went unread; what
            /// they delivered stays as it was.
            public var unlistedFolders: [String] = []

            /// Listed, but not everything in it could be read or understood.
            public var hasProblems: Bool { !unknownRecordTypes.isEmpty || !shortenedLogs.isEmpty || isIncomplete }

            /// Something reading again may fix: the folder, a folder in it, or a log couldn't be read
            /// whole. Unknown record types stay until Gleaner learns them, and lost records stay lost.
            public var isIncomplete: Bool {
                if case .unreadable = folder { return true }
                return !partialLogs.isEmpty || !failures.isEmpty || !unlistedFolders.isEmpty
            }
        }

        public var logsRead = 0
        public var newDeliveries = 0
        /// Every provider, whether or not its folder is there.
        public var sources: [Provider: Source] = [:]
    }

    public let registry: Registry
    public let store: ContentStore
    public let sources: LogSources
    /// Files up to this size get a saved copy at capture; larger ones are tracked by hash (SPEC §6).
    public var saveLimit: Int64 = 64 << 20
    /// A capture within this window of the reply, of a file not modified after it, counts as at
    /// delivery (SPEC §5.1). The window bounds how long an unchanged modification time is trusted.
    public var liveWindow: TimeInterval = 600
    /// Log and file timestamps come from different writers; this absorbs their granularity only.
    public var clockTolerance: TimeInterval = 2

    public init(registry: Registry, store: ContentStore, sources: LogSources) {
        self.registry = registry
        self.store = store
        self.sources = sources
    }

    public func run(now: () -> Date = Date.init, progress: (Int, Int) -> Void = { _, _ in }) throws -> Report {
        var report = Report()
        var files: [(Provider, URL)] = []
        for provider in Provider.allCases {
            let (source, logs) = sources.logs(provider)
            report.sources[provider] = source
            files += logs.map { (provider, $0) }
        }
        let codex = CodexAdapter(titles: CodexAdapter.loadTitles(
            index: sources.codexHome.appendingPathComponent("session_index.jsonl")))

        var changed: [(Provider, URL, Int64, Date, shortened: Bool)] = []
        for (provider, url) in files {
            let info = Locator.stat(url.path)
            guard let size = info.size, let mtime = info.modifiedAt else { continue }
            if let unknown = try registry.unknownRecordTypes(unchangedLog: url.path, size: size, mtime: mtime) {
                report.sources[provider]?.unknownRecordTypes.merge(unknown, uniquingKeysWith: +)
            } else {
                let shortened = try registry.readSize(logFile: url.path).map { size < $0 } ?? false
                changed.append((provider, url, size, mtime, shortened))
            }
        }

        let jobs = changed
        let parsed = Slots<Result<SessionLog?, Error>>(count: jobs.count)
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let (provider, url, _, _, _) = jobs[index]
            parsed[index] = Result { () throws -> SessionLog? in
                switch provider {
                case .claudeCode: try ClaudeCodeAdapter.parse(url)
                case .codex: try codex.parse(url)
                }
            }
        }

        for (index, (provider, url, size, mtime, shortened)) in changed.enumerated() {
            progress(index, changed.count)
            switch parsed[index] {
            case .failure(let error):
                report.sources[provider]?.failures.append("\(url.path): \(error)")
                continue
            case .success(let log):
                // A log shorter than when it was last read lost records, so like a malformed one it
                // can't show that a delivery is gone.
                let complete = log.map { $0.isComplete && !shortened } ?? true
                do {
                    report.newDeliveries += try registry.transaction {
                        let added = try log.map { try ingest($0, isComplete: complete, now: now()) } ?? 0
                        // A log not read whole stays unread, so it is read and reported again next run.
                        if complete {
                            try registry.markRead(logFile: url.path, size: size, mtime: mtime,
                                                  unknownRecordTypes: log?.unknownRecordTypes ?? [:])
                        }
                        return added
                    }
                } catch {
                    // A log the registry refuses fails alone; the run goes on.
                    report.sources[provider]?.failures.append("\(url.path): \(error)")
                    continue
                }
                if let log {
                    report.sources[provider]?.unknownRecordTypes.merge(log.unknownRecordTypes, uniquingKeysWith: +)
                    if !log.isComplete { report.sources[provider]?.partialLogs.append(url.path) }
                    if shortened { report.sources[provider]?.shortenedLogs.append(url.path) }
                }
                report.logsRead += 1
            }
        }
        progress(changed.count, changed.count)
        return report
    }

    /// `isComplete` says the whole log was read: only then does it show that a delivery it no
    /// longer admits is gone.
    func ingest(_ log: SessionLog, isComplete: Bool, now: Date) throws -> Int {
        try registry.upsert(log.session)
        var added = 0
        var admitted = Set<String>()
        for turn in log.turns {
            for candidate in MentionExtractor.candidates(in: turn) where Admission.admits(candidate) {
                // A delivery keeps the id, and the capture, it was first given. A later extractor may
                // find the reply's first mention of the path in another of its records, or admit it
                // again after a reread dropped it; a new capture would record the bytes as they are now.
                let fresh = candidate.id(logPath: log.session.logPath)
                let known = try ([fresh] + turn.parts.map {
                    DeliveryCandidate.id(logPath: log.session.logPath, line: $0.line, path: candidate.path)
                }).first(where: registry.hasCapture)
                let id = known ?? fresh
                admitted.insert(id)
                let isNew = known == nil
                let first = candidate.evidence[0]
                try registry.upsertDelivery(
                    id: id, sessionID: log.session.id, logPath: log.session.logPath, path: candidate.path, deliveredAt: first.part.at,
                    cwd: first.part.cwd, repository: Projects.repository(path: candidate.path, cwd: first.part.cwd),
                    request: turn.request,
                    evidence: candidate.evidence.map {
                        Evidence(line: $0.part.line, syntax: $0.mention.syntax.rawValue,
                                 rawTarget: Redactor.redact($0.mention.rawTarget),
                                 anchor: $0.mention.anchor.map(Redactor.redact), excerpt: $0.mention.excerpt)
                    })
                guard isNew else { continue }
                let captured = capture(candidate.path, deliveredAt: first.part.at, now: now)
                try registry.addCapture(captured, for: id)
                // Gleaner's first read of the file for an earlier delivery whose bytes it never had.
                if captured.sha256 != nil { try registry.complete(capturesOf: candidate.path, with: captured) }
                added += 1
            }
        }
        if isComplete { try registry.removeDeliveries(logPath: log.session.logPath, except: admitted) }
        return added
    }

    /// Over the save limit: tracked by hash, and saved only when the person asks (SPEC §6). A
    /// smaller file without a saved copy is one Gleaner could not save, not this policy.
    public func isLarge(_ capture: Capture) -> Bool {
        (capture.size ?? 0) > saveLimit
    }

    /// Saves a copy of a delivery's bytes while the file still holds them (SPEC §6). Throws
    /// `ContentStore.Failure.changed` when it no longer does, and any error reading the file or
    /// recording the copy, so the person learns why nothing was kept.
    public func saveCopy(of delivery: Delivery, at date: Date) throws {
        guard let sha = delivery.sha256 else { throw ContentStore.Failure.unavailable }
        let saved = try store.save(delivery.path)
        guard saved.sha == sha else { throw ContentStore.Failure.changed(expected: sha, found: saved.sha) }
        try registry.markSaved(deliveryID: delivery.id, at: date)
    }

    /// Reads the delivery's bytes once, saves small files, and records when that happened relative
    /// to the delivery (SPEC §5.1). A path whose bytes it can't read (nothing there, a file it
    /// can't open, a pipe) is recorded as never observed, with what it found instead.
    public func capture(_ path: String, deliveredAt: Date?, now: Date) -> Capture {
        let info = Locator.stat(path)
        let live = deliveredAt.map { delivered in
            now.timeIntervalSince(delivered) <= liveWindow
                && (info.modifiedAt.map { $0 <= delivered.addingTimeInterval(clockTolerance) } ?? false)
        } ?? false
        let provenance: Provenance = live ? .atDelivery : .firstSeenAfterDelivery
        func unread(_ kind: LocatorState.Kind) -> Capture {
            Capture(sha256: nil, size: nil, modifiedAt: nil, observedAt: now, savedAt: nil, provenance: .neverObserved, kind: kind)
        }
        switch info.kind {
        case .missing, .special, .unreadable:
            return unread(info.kind)
        case .directory:
            return Capture(sha256: nil, size: nil, modifiedAt: info.modifiedAt, observedAt: now, savedAt: nil,
                           provenance: provenance, kind: .directory)
        case .file:
            if let size = info.size, size <= saveLimit, let saved = try? store.save(path) {
                return Capture(sha256: saved.sha, size: saved.size, modifiedAt: info.modifiedAt, observedAt: now,
                               savedAt: now, provenance: provenance, kind: .file)
            }
            guard let sha = Locator.sha256(path) else { return unread(.unreadable) }
            return Capture(sha256: sha, size: info.size, modifiedAt: info.modifiedAt, observedAt: now,
                           savedAt: nil, provenance: provenance, kind: .file)
        }
    }

    /// Reads the file at `path` for deliveries of it whose bytes Gleaner never had, because the
    /// path was missing, unreadable or not a regular file when it first looked. This first read
    /// completes their captures, once, as first seen after delivery (SPEC §5.1), and saves a small
    /// file as a capture does. Returns whether it completed any.
    public func completeCaptures(of path: String, now: Date) throws -> Bool {
        guard try registry.hasIncompleteCapture(path: path) else { return false }
        let read = capture(path, deliveredAt: nil, now: now)
        guard read.sha256 != nil else { return false }
        try registry.complete(capturesOf: path, with: read)
        return true
    }
}

/// Fixed-size results written from concurrent workers, one slot each.
private final class Slots<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [T?]

    init(count: Int) { values = Array(repeating: nil, count: count) }

    subscript(index: Int) -> T {
        get { lock.withLock { values[index]! } }
        set { lock.withLock { values[index] = newValue } }
    }
}
