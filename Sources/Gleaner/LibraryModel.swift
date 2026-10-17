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

/// A verified copy prepared for dragging, or why there isn't one.
enum Staging: Equatable {
    case idle
    case preparing
    case ready(URL, sha: String)
    case failed(String)
}

@MainActor @Observable
final class LibraryModel {
    var artifacts: [Artifact] = []
    var query = ""
    var kind: Artifact.Kind?
    var selection: Artifact.ID? {
        didSet { if selection != oldValue { chosenDelivery = nil } }
    }
    /// Set when the person picks a delivery; otherwise the delivery the search matched.
    var chosenDelivery: Delivery.ID?
    var progress: (done: Int, total: Int)?
    var status = "Starting…"
    var observations: [String: FileObservation] = [:]
    var staging: Staging = .idle

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
            guard kind == nil || artifact.kind == kind, let match = artifact.match(tokens) else { return nil }
            return SearchResult(artifact: artifact, deliveryIndex: match.deliveryIndex, matchedIn: match.fields)
        }
    }

    var selected: SearchResult? { results.first { $0.id == selection } }

    func delivery(in result: SearchResult) -> Delivery {
        if let chosen = chosenDelivery, let d = result.artifact.deliveries.first(where: { $0.id == chosen }) { return d }
        return result.artifact.deliveries[result.deliveryIndex]
    }

    func hasSaved(_ sha: String) -> Bool { indexer.store.has(sha) }

    /// Checks the file now (hash and git), off the main thread.
    func observe(_ artifact: Artifact) async {
        let path = artifact.path
        let state = await Task.detached(priority: .userInitiated) { Locator.observe(path) }.value
        observations[path] = FileObservation(state: state, checkedAt: Date())
    }

    /// Prepares a verified, immutable copy of `sha` to drag.
    func stage(sha: String, artifact: Artifact) async {
        staging = .preparing
        let store = indexer.store
        let name = artifact.name
        let source = artifact.path
        let result = await Task.detached(priority: .userInitiated) {
            Swift.Result { try store.stage(sha: sha, name: name, source: source) }
        }.value
        switch result {
        case .success(let url): staging = .ready(url, sha: sha)
        case .failure(ContentStore.Failure.changed): staging = .failed("The file changed while Gleaner was copying it. Check again.")
        case .failure: staging = .failed("Gleaner couldn’t read these bytes.")
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
