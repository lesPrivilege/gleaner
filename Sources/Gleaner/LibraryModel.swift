import AppKit
import GleanerCore
import Observation

/// One search result: the artifact, and the delivery the search matched.
struct SearchResult: Identifiable {
    var artifact: Artifact
    var deliveryIndex: Int
    var matchedIn: [String]
    var id: String { artifact.id }
}

/// A verified copy prepared for dragging, or why there isn't one. Every state names the version
/// it is for, so work started for one selection is never shown under another.
enum Staging: Equatable {
    case idle
    case preparing(sha: String)
    case ready(URL, sha: String)
    case failed(String, sha: String)

    var sha: String? {
        switch self {
        case .idle: nil
        case .preparing(let sha), .ready(_, let sha), .failed(_, let sha): sha
        }
    }
}

@MainActor @Observable
final class LibraryModel {
    var artifacts: [Artifact] = [] {
        didSet {
            siblings = Self.siblings(of: artifacts)
            missing = Self.missing(artifacts)
        }
    }
    /// Paths not on disk, checked once per load and refreshed when a file is observed, so list
    /// rows never touch the disk while drawing.
    private(set) var missing: Set<String> = []
    /// Files named in the same reply, keyed by delivery id.
    private(set) var siblings: [Delivery.ID: [Artifact.ID]] = [:]
    /// False until the first read of the logs finishes.
    private(set) var indexed = false
    var query = "" {
        didSet { if query != oldValue { chosenDelivery = nil } }
    }
    var kind: Artifact.Kind?
    /// nil shows every project.
    var project: String?
    var selection: Artifact.ID? {
        didSet { if selection != oldValue { chosenDelivery = nil } }
    }
    /// Set when the person picks a delivery; otherwise the delivery the search matched.
    var chosenDelivery: Delivery.ID?
    var progress: (done: Int, total: Int)?
    var status = "Starting…"
    var observations: [String: FileObservation] = [:]
    private(set) var staging: Staging = .idle

    let indexer: Indexer
    private let work = DispatchQueue(label: "gleaner.index", qos: .utility)
    private var watcher: LogWatcher?
    private var indexing = false
    private var pending = false

    init() throws {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Gleaner")
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Gleaner")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let registry = try Registry(path: support.appendingPathComponent("registry.sqlite").path)
        indexer = Indexer(
            registry: registry,
            store: ContentStore(objects: support.appendingPathComponent("objects"), staging: caches.appendingPathComponent("handoff")),
            sources: .standard)
        artifacts = (try? registry.artifacts()) ?? []
        siblings = Self.siblings(of: artifacts)
        missing = Self.missing(artifacts)
    }

    private static func missing(_ artifacts: [Artifact]) -> Set<String> {
        Set(artifacts.lazy.map(\.path).filter { !FileManager.default.fileExists(atPath: $0) })
    }

    /// The agent log folders that exist on this Mac.
    var logFolders: (found: [String], missing: [String]) {
        let all = indexer.sources.watchedDirectories
        let found = all.filter { FileManager.default.fileExists(atPath: $0) }
        return (found, all.filter { !found.contains($0) })
    }

    /// Projects, most recently delivered to first.
    var projects: [String] {
        var seen = Set<String>()
        return artifacts.compactMap { seen.insert($0.project).inserted ? $0.project : nil }
    }

    func clearFilters() {
        query = ""
        kind = nil
        project = nil
    }

    /// One reply is one log and one delivery time; every file it named shares both.
    private static func siblings(of artifacts: [Artifact]) -> [Delivery.ID: [Artifact.ID]] {
        var byReply: [String: [(Delivery.ID, Artifact.ID)]] = [:]
        for artifact in artifacts {
            for d in artifact.deliveries {
                guard let at = d.deliveredAt else { continue }
                byReply["\(d.logPath)|\(at.timeIntervalSince1970)", default: []].append((d.id, artifact.id))
            }
        }
        var result: [Delivery.ID: [Artifact.ID]] = [:]
        for group in byReply.values where group.count > 1 {
            for (delivery, artifact) in group {
                result[delivery] = group.map(\.1).filter { $0 != artifact }.sorted()
            }
        }
        return result
    }

    func start() {
        watcher = LogWatcher(directories: indexer.sources.watchedDirectories, queue: work) { [weak self] in
            Task { @MainActor in self?.reindex() }
        }
        reindex()
    }

    func reindex() {
        guard !indexing else { pending = true; return }
        indexing = true
        let indexer = indexer
        work.async {
            let outcome = Swift.Result {
                try indexer.run(progress: { done, total in
                    Task { @MainActor [weak self] in self?.progress = total > 0 && done < total ? (done, total) : nil }
                })
            }
            let artifacts = (try? indexer.registry.artifacts()) ?? []
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.artifacts = artifacts
                self.progress = nil
                self.indexed = true
                switch outcome {
                case .success(let report):
                    let failures = report.failures.isEmpty ? "" : " · \(report.failures.count) logs unreadable"
                    self.status = "\(artifacts.count) delivered files\(failures)"
                case .failure(let error):
                    self.status = "Indexing failed: \(error)"
                }
                self.indexing = false
                if self.pending { self.pending = false; self.reindex() }
            }
        }
    }

    var tokens: [String] { query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init) }

    var results: [SearchResult] {
        let tokens = tokens
        return artifacts.compactMap { artifact in
            guard kind == nil || artifact.kind == kind, project == nil || artifact.project == project,
                  let match = artifact.match(tokens) else { return nil }
            return SearchResult(artifact: artifact, deliveryIndex: match.deliveryIndex, matchedIn: match.fields)
        }
    }

    var selected: SearchResult? { results.first { $0.id == selection } }

    func delivery(in result: SearchResult) -> Delivery {
        if let chosen = chosenDelivery, let d = result.artifact.deliveries.first(where: { $0.id == chosen }) { return d }
        return result.artifact.deliveries[result.deliveryIndex]
    }

    func hasSaved(_ sha: String) -> Bool { indexer.store.has(sha) }

    /// What the selection would hand over now, once its file has been checked.
    var selectedHandoff: (artifact: Artifact, delivery: Delivery, plan: Handoff)? {
        guard let result = selected, let observation = observations[result.artifact.path] else { return nil }
        let delivery = delivery(in: result)
        return (result.artifact, delivery, result.artifact.handoff(delivery, now: observation, hasSaved: hasSaved))
    }

    /// The verified copy (or folder) the selection hands over, when it is ready.
    var selectedHandoffURL: URL? {
        guard let (artifact, _, plan) = selectedHandoff else { return nil }
        if plan == .folder { return URL(fileURLWithPath: artifact.path) }
        if case .ready(let url, _) = staging(for: plan.sha) { return url }
        return nil
    }

    /// The hand-off state for the version `sha`; idle when what is staged belongs to another one.
    func staging(for sha: String?) -> Staging {
        sha != nil && staging.sha == sha ? staging : .idle
    }

    func clearStaging() { staging = .idle }

    /// Checks the file now (hash and git), off the main thread.
    func observe(_ artifact: Artifact) async {
        let path = artifact.path
        let state = await Task.detached(priority: .userInitiated) { Locator.observe(path) }.value
        observations[path] = FileObservation(state: state, checkedAt: Date())
        if state.kind == .missing { missing.insert(path) } else { missing.remove(path) }
    }

    /// Prepares a verified, immutable copy of `sha` to drag.
    func stage(sha: String, artifact: Artifact) async {
        staging = .preparing(sha: sha)
        let store = indexer.store
        let name = artifact.name
        let source = artifact.path
        let result = await Task.detached(priority: .userInitiated) {
            Swift.Result { try store.stage(sha: sha, name: name, source: source) }
        }.value
        // The selection moved on, or another version is being prepared: this result is stale.
        guard !Task.isCancelled, staging == .preparing(sha: sha) else { return }
        switch result {
        case .success(let url): staging = .ready(url, sha: sha)
        case .failure(ContentStore.Failure.changed):
            staging = .failed("The file changed while Gleaner was copying it. Check again.", sha: sha)
        case .failure: staging = .failed("Gleaner couldn’t read these bytes.", sha: sha)
        }
    }

    /// Saves a copy of a large delivery whose bytes are still on disk, after checking they match.
    func saveCopy(of delivery: Delivery, artifact: Artifact) async {
        guard let sha = delivery.sha256 else { return }
        let indexer = indexer
        let path = artifact.path
        let ok = await Task.detached {
            guard let saved = try? indexer.store.save(path), saved.sha == sha else { return false }
            try? indexer.registry.markSaved(deliveryID: delivery.id, at: Date())
            return true
        }.value
        if ok { artifacts = (try? indexer.registry.artifacts()) ?? artifacts }
        await observe(artifact)
    }
}
