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

    /// The id of a delivery of `path` whose first mention is in the reply record at `line`. With
    /// `distinct`, the id for when that one already belongs to another reply's capture.
    static func id(logPath: String, line: Int, path: String, distinct: String? = nil) -> String {
        let key = "\(logPath)\n\(line)\n\(path)" + (distinct.map { "\n" + $0 } ?? "")
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
            /// Logs found shorter than when Gleaner read them, now or on an earlier run: records were
            /// lost. What they name is added, and nothing they no longer name is removed, however
            /// they grow again; reading again can't bring the records back.
            public var shortenedLogs: [String] = []
            /// Logs that could not be read or stored, with the reason. Their deliveries stay as they were.
            public var failures: [String] = []
            /// Folders in it that could not be listed, with the reason. Their logs went unread; what
            /// they delivered stays as it was.
            public var unlistedFolders: [String] = []
            /// What the walks of its sessions' workspaces couldn't see, each with why: a walk stopped
            /// at its bound, a folder in it couldn't be listed, or what it found couldn't be recorded.
            /// Files there may be missing from what was observed; no delivery is affected.
            public var workspaceProblems: [String] = []
            /// Folders its sessions worked in that aren't walked, each with why: skipped (the home
            /// folder, a system or hidden folder, the agents' logs) or no longer there. Not a problem:
            /// it says why nothing was observed there.
            public var unwalkedWorkspaces: [String] = []
            /// What the listings of folders its replies delivered couldn't see, each with why: a
            /// listing stopped at its bound, a folder in it couldn't be read, or its files couldn't
            /// be recorded. Files there may be missing from what was handed over (SPEC §5.4).
            public var folderProblems: [String] = []
            /// Folders its replies delivered whose files aren't listed, each with why: the home, a
            /// folder directly in it, a project's own folder or one holding it. Not a problem: it
            /// says why the folder stands alone.
            public var foldersNotUnpacked: [String] = []

            /// Listed, but not everything in it could be read or understood.
            public var hasProblems: Bool {
                !unknownRecordTypes.isEmpty || !shortenedLogs.isEmpty || !workspaceProblems.isEmpty || !folderProblems.isEmpty
                    || isIncomplete
            }

            /// Something reading again may fix: the folder, a folder in it, or a log couldn't be read
            /// whole. Unknown record types stay until Gleaner learns them, and lost records stay lost.
            public var isIncomplete: Bool {
                if case .unreadable = folder { return true }
                return !partialLogs.isEmpty || !failures.isEmpty || !unlistedFolders.isEmpty
            }
        }

        public var logsRead = 0
        public var newDeliveries = 0
        /// Files recorded as observed during a session for the first time.
        public var newObservations = 0
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
    /// The folder taken for the person's home. A session working in it, or in a system folder, has
    /// no workspace walked; the real home never is, whatever this says (docs/design/capture.md).
    public var home = NSHomeDirectory()
    /// How far each stretch of a session's span reaches before its request and after its last
    /// reply, for the clocks of the log's writer and the disk's.
    public var spanGrace: TimeInterval = 60
    /// Entries one workspace walk looks at before it stops (`Workspace.limit`).
    public var walkLimit = Workspace.limit

    public init(registry: Registry, store: ContentStore, sources: LogSources) {
        self.registry = registry
        self.store = store
        self.sources = sources
    }

    /// Reads the logs of `providers`; the others are neither listed nor read, so nothing they
    /// delivered is touched.
    public func run(providers: Set<Provider> = Set(Provider.allCases), now: () -> Date = Date.init,
                    progress: (Int, Int) -> Void = { _, _ in }) throws -> Report {
        var report = Report()
        var files: [(Provider, URL)] = []
        for provider in Provider.allCases where providers.contains(provider) {
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
            if let found = try registry.findings(unchangedLog: url.path, size: size, mtime: mtime) {
                report.sources[provider]?.unknownRecordTypes.merge(found.unknownRecordTypes, uniquingKeysWith: +)
                if found.shortened { report.sources[provider]?.shortenedLogs.append(url.path) }
            } else {
                let shortened = try registry.lastRead(logFile: url.path).map { $0.shortened || size < $0.size } ?? false
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
                // A log shorter than when it was read lost records, so like a malformed one it can't
                // show that a delivery is gone: not now, and not once it grows again.
                let complete = log.map { $0.isComplete && !shortened } ?? true
                let derived = log.flatMap(span(of:))
                do {
                    report.newDeliveries += try registry.transaction {
                        let added = try log.map { try ingest($0, isComplete: complete, now: now()) } ?? 0
                        // With the log's reading, so a session whose walk a quit cut off is walked next run.
                        if let log, let derived {
                            try registry.recordSpan(of: log.session, provider: provider, span: derived.span,
                                                    workspaces: derived.workspaces, unwalked: derived.unwalked)
                        }
                        if shortened { try registry.markShortened(logFile: url.path) }
                        // A log with malformed lines stays unread, so it is read and reported again next run.
                        if log?.isComplete ?? true {
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

        // Every log is in: each delivered folder not listed yet is listed, and each workspace waiting
        // to be walked is walked once, for every session in it.
        let unpacked = unpack(at: now(), providers: providers)
        let observed = observe(at: now(), providers: providers)
        report.newObservations = observed.recorded
        let problems = try registry.workspaceProblems(), unwalked = try registry.unwalkedWorkspaces()
        let folders = try registry.unpackings()
        for provider in report.sources.keys {
            report.sources[provider]?.workspaceProblems = (problems[provider] ?? []) + (observed.failures[provider] ?? [])
            report.sources[provider]?.unwalkedWorkspaces = unwalked[provider] ?? []
            report.sources[provider]?.folderProblems = (folders.problems[provider] ?? []) + (unpacked[provider] ?? [])
            report.sources[provider]?.foldersNotUnpacked = folders.notUnpacked[provider] ?? []
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
        let turns = log.turns.map { turn in
            (turn, MentionExtractor.candidates(in: turn).enumerated().filter { Admission.admits($0.element) })
        }
        // Record times two replies naming the same file share: they don't tell those replies apart.
        var seen: [String: Set<Double>] = [:], shared: [String: Set<Double>] = [:]
        for (turn, candidates) in turns {
            let times = Turn.times(turn)
            for (_, candidate) in candidates {
                shared[candidate.path, default: []].formUnion(times.intersection(seen[candidate.path] ?? []))
                seen[candidate.path, default: []].formUnion(times)
            }
        }
        for (turn, candidates) in turns {
            for (rank, candidate) in candidates {
                let first = candidate.evidence[0]
                let id = try deliveryID(of: candidate, in: turn, logPath: log.session.logPath, taken: admitted,
                                        shared: shared[candidate.path] ?? [])
                admitted.insert(id)
                let isNew = try !registry.hasCapture(id)
                try registry.upsertDelivery(
                    id: id, sessionID: log.session.id, logPath: log.session.logPath, path: candidate.path, deliveredAt: first.part.at,
                    replyLine: turn.parts[0].line, replyRank: rank, cwd: first.part.cwd, request: turn.request,
                    evidence: candidate.evidence.map {
                        Evidence(line: $0.part.line, syntax: $0.mention.syntax.rawValue,
                                 rawTarget: Redactor.redact($0.mention.rawTarget),
                                 anchor: $0.mention.anchor.map(Redactor.redact), excerpt: $0.mention.excerpt)
                    },
                    model: turn.model)
                if isNew {
                    let file = Workspace.file(at: candidate.path)
                    let captured = capture(candidate.path, deliveredAt: first.part.at, now: now)
                    try registry.addCapture(captured, for: id, logPath: log.session.logPath, path: candidate.path,
                                            replyTimes: Turn.times(turn))
                    // Gleaner's first read of the file for an earlier delivery whose bytes it never had,
                    // or one in a folder, listed as the file still is.
                    if captured.sha256 != nil {
                        try registry.complete(capturesOf: candidate.path, with: captured)
                        try completeMembers(of: candidate.path, with: captured, file: file)
                    }
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
        return added
    }

    /// A delivery keeps the id, and the capture, it was first given: a new capture would record the
    /// bytes as they are now. A capture records the times of its reply's records, and the reply
    /// finds it by a time no other reply naming the file has, wherever the reply sits in the log
    /// now: a later extractor may find the reply's first mention in another record, a reread may
    /// admit it again after dropping it, a rewritten log may move it, and the reply may have grown.
    /// A reply whose times other replies share (`shared`), or that has none, is found by its place,
    /// as before Gleaner kept the times, but never takes a capture recording a time it doesn't have.
    /// `taken` holds the ids other replies in the log were given in this read.
    func deliveryID(of candidate: DeliveryCandidate, in turn: Turn, logPath: String, taken: Set<String>,
                    shared: Set<Double>) throws -> String {
        let times = Turn.times(turn)
        let own = times.subtracting(shared)
        let fresh = candidate.id(logPath: logPath)
        let placed = [fresh] + turn.parts.map { DeliveryCandidate.id(logPath: logPath, line: $0.line, path: candidate.path) }
        if !own.isEmpty {
            let mine = try registry.captures(logPath: logPath, path: candidate.path)
                .filter { !taken.contains($0.id) && !$0.times.isDisjoint(with: own) }
            if let capture = mine.first(where: { placed.contains($0.id) }) ?? mine.first { return capture.id }
        }
        for id in placed where !taken.contains(id) {
            guard let recorded = try registry.captureTimes(id), recorded.isSubset(of: times) else { continue }
            // Recording only times other replies share, it may be another reply's: a reply with a
            // time of its own doesn't take it by its place.
            if !recorded.isEmpty, !own.isEmpty, recorded.isDisjoint(with: own) { continue }
            if recorded.isEmpty { try registry.place(capture: id, logPath: logPath, path: candidate.path, times: times) }
            return id
        }
        if !taken.contains(fresh), try registry.captureTimes(fresh) == nil { return fresh }
        // The reply's place is held by another reply's capture: it gets an id of its own, the same
        // on every read while its place and times stay.
        var n = 0
        while true {
            n += 1
            let id = DeliveryCandidate.id(logPath: logPath, line: candidate.evidence[0].part.line, path: candidate.path, distinct: "\(n)")
            guard !taken.contains(id) else { continue }
            guard let recorded = try registry.captureTimes(id) else { return id }
            // Only this loop gives these ids: one recording this reply's times, or none for a reply
            // without times, is the one it gave this reply before.
            if recorded.isSubset(of: times), !recorded.isEmpty || times.isEmpty { return id }
        }
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
        try registry.markSaved(delivery, at: date)
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

    /// Reads the file at `path` for deliveries of it whose bytes Gleaner never had: because the path
    /// was missing, unreadable or not a regular file when it first looked, or because the file was
    /// listed with a delivered folder and not read (SPEC §5.4). This first read completes their
    /// captures, once: the first as first seen after delivery (SPEC §5.1), the listed ones only while
    /// the file is still as listed (`completeMembers`). It saves a small file as a capture does.
    /// Returns whether it completed any.
    public func completeCaptures(of path: String, now: Date) throws -> Bool {
        let file = Workspace.file(at: path)
        let listed = try file.map { try !registry.listedMembers(of: path, as: $0).isEmpty } ?? false
        guard try listed || registry.hasIncompleteCapture(path: path) else { return false }
        let read = capture(path, deliveredAt: nil, now: now)
        guard read.sha256 != nil else { return false }
        try registry.transaction {
            try registry.complete(capturesOf: path, with: read)
            try completeMembers(of: path, with: read, file: file)
        }
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

extension Turn {
    /// The times of a reply's records, in seconds since 1970, as captures record them.
    static func times(_ turn: Turn) -> Set<Double> {
        Set(turn.parts.compactMap { $0.at?.timeIntervalSince1970 })
    }
}
