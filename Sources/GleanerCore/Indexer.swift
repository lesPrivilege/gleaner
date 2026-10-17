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

    public var watchedDirectories: [String] {
        [claudeProjects.path, codexHome.appendingPathComponent("sessions").path]
    }
}

extension DeliveryCandidate {
    /// Stable for a given reply and path, so re-reading a log never duplicates a delivery.
    public func id(logPath: String) -> String {
        let key = "\(logPath)\n\(evidence[0].part.line)\n\(path)"
        return SHA256.hash(data: Data(key.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
}

/// Reads changed logs into the registry and captures each new delivery's bytes once.
public final class Indexer: @unchecked Sendable {
    public struct Report: Sendable {
        public var logsRead = 0
        public var newDeliveries = 0
        public var unknownRecordTypes: [String: Int] = [:]
        public var failures: [String] = []
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
        let codex = CodexAdapter(titles: CodexAdapter.loadTitles(
            index: sources.codexHome.appendingPathComponent("session_index.jsonl")))
        let files: [(Provider, URL)] =
            ClaudeCodeAdapter.sessionFiles(root: sources.claudeProjects).map { (.claudeCode, $0) }
            + CodexAdapter.sessionFiles(root: sources.codexHome.appendingPathComponent("sessions")).map { (.codex, $0) }

        var changed: [(Provider, URL, Int64, Date)] = []
        for (provider, url) in files {
            let info = Locator.stat(url.path)
            guard let size = info.size, let mtime = info.modifiedAt else { continue }
            if try !registry.isUnchanged(logFile: url.path, size: size, mtime: mtime) {
                changed.append((provider, url, size, mtime))
            }
        }

        var report = Report()
        let jobs = changed
        let parsed = Slots<Result<SessionLog?, Error>>(count: jobs.count)
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let (provider, url, _, _) = jobs[index]
            parsed[index] = Result { () throws -> SessionLog? in
                switch provider {
                case .claudeCode: try ClaudeCodeAdapter.parse(url)
                case .codex: try codex.parse(url)
                }
            }
        }

        for (index, (_, url, size, mtime)) in changed.enumerated() {
            progress(index, changed.count)
            switch parsed[index] {
            case .failure(let error):
                report.failures.append("\(url.path): \(error)")
                continue
            case .success(let log):
                try registry.transaction {
                    if let log {
                        report.newDeliveries += try ingest(log, now: now())
                        report.unknownRecordTypes.merge(log.unknownRecordTypes, uniquingKeysWith: +)
                    }
                    try registry.markRead(logFile: url.path, size: size, mtime: mtime)
                }
                report.logsRead += 1
            }
        }
        progress(changed.count, changed.count)
        return report
    }

    func ingest(_ log: SessionLog, now: Date) throws -> Int {
        try registry.upsert(log.session)
        var added = 0
        var admitted = Set<String>()
        for turn in log.turns {
            for candidate in MentionExtractor.candidates(in: turn) where Admission.admits(candidate) {
                let id = candidate.id(logPath: log.session.logPath)
                admitted.insert(id)
                let isNew = try !registry.hasDelivery(id)
                let first = candidate.evidence[0]
                try registry.upsertDelivery(
                    id: id, sessionID: log.session.id, logPath: log.session.logPath, path: candidate.path, deliveredAt: first.part.at,
                    cwd: first.part.cwd, request: turn.request,
                    evidence: candidate.evidence.map {
                        Evidence(line: $0.part.line, syntax: $0.mention.syntax.rawValue,
                                 rawTarget: Redactor.redact($0.mention.rawTarget),
                                 anchor: $0.mention.anchor.map(Redactor.redact), excerpt: Redactor.redact($0.mention.excerpt))
                    })
                guard isNew else { continue }
                try registry.setCapture(capture(candidate.path, deliveredAt: first.part.at, now: now), for: id)
                added += 1
            }
        }
        try registry.removeDeliveries(logPath: log.session.logPath, except: admitted)
        return added
    }

    /// Reads the delivery's bytes once, saves small files, and records when that happened relative
    /// to the delivery (SPEC §5.1).
    public func capture(_ path: String, deliveredAt: Date?, now: Date) -> Capture {
        let info = Locator.stat(path)
        let live = deliveredAt.map { delivered in
            now.timeIntervalSince(delivered) <= liveWindow
                && (info.modifiedAt.map { $0 <= delivered.addingTimeInterval(clockTolerance) } ?? false)
        } ?? false
        let provenance: Provenance = live ? .atDelivery : .firstSeenAfterDelivery
        switch info.kind {
        case .missing, .special:
            return Capture(sha256: nil, size: nil, modifiedAt: nil, observedAt: now, savedAt: nil,
                           provenance: .neverObserved, isDirectory: false)
        case .directory:
            return Capture(sha256: nil, size: nil, modifiedAt: info.modifiedAt, observedAt: now, savedAt: nil,
                           provenance: provenance, isDirectory: true)
        case .file:
            if let size = info.size, size <= saveLimit, let saved = try? store.save(path) {
                return Capture(sha256: saved.sha, size: saved.size, modifiedAt: info.modifiedAt, observedAt: now,
                               savedAt: now, provenance: provenance, isDirectory: false)
            }
            return Capture(sha256: Locator.sha256(path), size: info.size, modifiedAt: info.modifiedAt, observedAt: now,
                           savedAt: nil, provenance: provenance, isDirectory: false)
        }
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
