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

/// Where Gleaner keeps its library, one place for the app and for everything that reads it: the
/// registry and saved copies in Application Support, hand-off copies in Caches, and the agents'
/// logs. `home` stands in for the home folder, as the app's `-GleanerHome` and the command's
/// `--home` do; nil is the person's own.
public struct LibraryFolders: Sendable {
    /// Application Support/Gleaner: the registry and the saved copies.
    public var support: URL
    /// Caches/Gleaner: hand-off copies.
    public var caches: URL
    public var sources: LogSources

    public init(home: URL?) {
        let fm = FileManager.default
        let library = home.map { $0.appendingPathComponent("Library") }
        support = (library?.appendingPathComponent("Application Support")
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).appendingPathComponent("Gleaner")
        caches = (library?.appendingPathComponent("Caches")
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]).appendingPathComponent("Gleaner")
        sources = home.map {
            LogSources(claudeProjects: $0.appendingPathComponent(".claude/projects"), codexHome: $0.appendingPathComponent(".codex"))
        } ?? .standard
    }

    public var registry: String { support.appendingPathComponent("registry.sqlite").path }
    public var objects: URL { support.appendingPathComponent("objects") }
    public var staging: URL { caches.appendingPathComponent("handoff") }
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

extension Delivery {
    /// True for text shaped as `DeliveryCandidate.id` makes an id: 20 lowercase hex digits. Any
    /// other text names no delivery.
    public static func isID(_ text: String) -> Bool {
        text.utf8.count == 20 && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
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
            /// Keys the adapter does not know inside the record types it does, as "type.key", with
            /// counts, whichever run read them. Non-empty means the format moved.
            public var unknownFields: [String: Int] = [:]
            /// Logs with malformed lines. What they name was added and nothing was removed; they are
            /// read again next run.
            public var partialLogs: [String] = []
            /// Logs found shorter than when Gleaner read them, now or on an earlier run: records were
            /// lost. What they name is added, and nothing they no longer name is removed, however
            /// they grow again; reading again can't bring the records back.
            public var shortenedLogs: [String] = []
            /// Logs with assistant records but no final reply, not counting the last turn while it has
            /// none (the session may still be running): the adapter may no longer recognize one.
            public var logsWithoutFinalReply: [String] = []
            /// Logs whose last complete read found fewer final replies than the one before it: the log
            /// or the adapter changed, and the deliveries only those replies named were removed.
            public var logsWithFewerReplies: [String] = []
            /// Logs that could not be read or stored, with the reason. Their deliveries stay as they were.
            public var failures: [String] = []
            /// Folders in it that could not be listed, with the reason. Their logs went unread; what
            /// they delivered stays as it was.
            public var unlistedFolders: [String] = []

            /// Listed, but not everything in it could be read or understood.
            public var hasProblems: Bool {
                !unknownRecordTypes.isEmpty || !unknownFields.isEmpty || !shortenedLogs.isEmpty
                    || !logsWithoutFinalReply.isEmpty || !logsWithFewerReplies.isEmpty || isIncomplete
            }

            /// Something reading again may fix: the folder, a folder in it, or a log couldn't be read
            /// whole. Unknown record types and fields stay until Gleaner learns them, lost records stay
            /// lost, and a log's replies are counted again only once it changes.
            public var isIncomplete: Bool {
                if case .unreadable = folder { return true }
                return !partialLogs.isEmpty || !failures.isEmpty || !unlistedFolders.isEmpty
            }

            /// Adds what reading `log` found, by this run or by the run that last read it whole.
            mutating func add(_ found: LogFindings, log: String) {
                unknownRecordTypes.merge(found.unknownRecordTypes, uniquingKeysWith: +)
                unknownFields.merge(found.unknownFields, uniquingKeysWith: +)
                if found.shortened { shortenedLogs.append(log) }
                if found.lacksFinalReply { logsWithoutFinalReply.append(log) }
                if found.fewerReplies { logsWithFewerReplies.append(log) }
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

        var changed: [(Provider, URL, Int64, Date, shortened: Bool, finalReplies: Int?)] = []
        for (provider, url) in files {
            let info = Locator.stat(url.path)
            guard let size = info.size, let mtime = info.modifiedAt else { continue }
            if let found = try registry.findings(unchangedLog: url.path, size: size, mtime: mtime) {
                report.sources[provider]?.add(found, log: url.path)
            } else {
                let last = try registry.lastRead(logFile: url.path)
                changed.append((provider, url, size, mtime, last.map { $0.shortened || size < $0.size } ?? false, last?.finalReplies))
            }
        }

        let jobs = changed
        let parsed = Slots<Result<SessionLog?, Error>>(count: jobs.count)
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let (provider, url, _, _, _, _) = jobs[index]
            parsed[index] = Result { () throws -> SessionLog? in
                switch provider {
                case .claudeCode: try ClaudeCodeAdapter.parse(url)
                case .codex: try codex.parse(url)
                }
            }
        }

        for (index, (provider, url, size, mtime, shortened, finalReplies)) in changed.enumerated() {
            progress(index, changed.count)
            switch parsed[index] {
            case .failure(let error):
                report.sources[provider]?.failures.append("\(url.path): \(error)")
                continue
            case .success(let log):
                // A log shorter than when it was read lost records, so like a malformed one it can't
                // show that a delivery is gone: not now, and not once it grows again.
                let complete = log.map { $0.isComplete && !shortened } ?? true
                let found: LogFindings
                do {
                    let added: Int
                    (added, found) = try registry.transaction {
                        let (added, candidates) = try log.map { try ingest($0, isComplete: complete, now: now()) } ?? (0, 0)
                        let counts = log.map {
                            LogCounts(records: $0.records, knownRecords: $0.knownRecords, turns: $0.answeredTurns,
                                      finalReplies: $0.turns.count, candidates: candidates)
                        }
                        let findings = LogFindings(
                            unknownRecordTypes: log?.unknownRecordTypes ?? [:], unknownFields: log?.unknownFields ?? [:],
                            counts: counts,
                            // Only a whole read shows that replies are gone, as it does deliveries.
                            fewerReplies: complete && (counts?.finalReplies ?? 0) < (finalReplies ?? 0),
                            shortened: shortened)
                        if shortened { try registry.markShortened(logFile: url.path) }
                        // A log with malformed lines stays unread, so it is read and reported again next run.
                        if log?.isComplete ?? true { try registry.markRead(logFile: url.path, size: size, mtime: mtime, findings: findings) }
                        return (added, findings)
                    }
                    report.newDeliveries += added
                } catch {
                    // A log the registry refuses fails alone; the run goes on.
                    report.sources[provider]?.failures.append("\(url.path): \(error)")
                    continue
                }
                report.sources[provider]?.add(found, log: url.path)
                if log?.isComplete == false { report.sources[provider]?.partialLogs.append(url.path) }
                report.logsRead += 1
            }
        }
        progress(changed.count, changed.count)
        // A result read from the library is evidence only within this run (query-core "Freshness").
        try registry.recordRun(finishedAt: now(), sources: report.sources)
        return report
    }

    /// `isComplete` says the whole log was read: only then does it show that a delivery it no
    /// longer admits is gone. Returns the deliveries it added, and the candidates the log's final
    /// replies name, admitted or not.
    func ingest(_ log: SessionLog, isComplete: Bool, now: Date) throws -> (added: Int, candidates: Int) {
        try registry.upsert(log.session)
        var added = 0
        var candidates = 0
        var admitted = Set<String>()
        for turn in log.turns {
            let found = MentionExtractor.candidates(in: turn)
            candidates += found.count
            for (rank, candidate) in found.enumerated() where Admission.admits(candidate) {
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
                    replyLine: turn.parts[0].line, replyRank: rank, cwd: first.part.cwd, request: turn.request,
                    evidence: candidate.evidence.map {
                        Evidence(line: $0.part.line, syntax: $0.mention.syntax.rawValue,
                                 rawTarget: Redactor.redact($0.mention.rawTarget),
                                 anchor: $0.mention.anchor.map(Redactor.redact), excerpt: $0.mention.excerpt)
                    })
                if isNew {
                    let captured = capture(candidate.path, deliveredAt: first.part.at, now: now)
                    try registry.addCapture(captured, for: id)
                    // Gleaner's first read of the file for an earlier delivery whose bytes it never had.
                    if captured.sha256 != nil { try registry.complete(capturesOf: candidate.path, with: captured) }
                    added += 1
                }
                // Where the file is, only while its folder is there to show it: once a worktree is
                // removed, its paths resolve to the main folder that kept it (SPEC §5).
                if Locator.stat((candidate.path as NSString).deletingLastPathComponent).kind == .directory,
                   let repository = Projects.repository(path: candidate.path, cwd: first.part.cwd) {
                    try registry.record(repository: repository, checkout: Projects.checkout(path: candidate.path)?.folder, of: id)
                }
            }
        }
        if isComplete { try registry.removeDeliveries(logPath: log.session.logPath, except: admitted) }
        return (added, candidates)
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
