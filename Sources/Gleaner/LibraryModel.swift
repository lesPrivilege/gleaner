import AppKit
import GleanerCore
import Observation
import UniformTypeIdentifiers

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
            siblings = Artifact.deliveredWith(artifacts)
            missing = Self.missing(artifacts)
        }
    }
    /// Paths not on disk, checked once per load and refreshed when a file is observed, so list
    /// rows never touch the disk while drawing.
    private(set) var missing: Set<String> = []
    /// The other files named in the same reply, as their deliveries from it, keyed by delivery id.
    private(set) var siblings: [Delivery.ID: [Delivery]] = [:]
    /// False until the first read of the logs finishes.
    private(set) var indexed = false
    var query = "" {
        didSet { if query != oldValue { chosenDelivery = nil } }
    }
    var kind: Artifact.Kind?
    /// nil shows every project.
    var project: String?
    var selection: Artifact.ID? {
        didSet { if selection != oldValue { chosenDelivery = nil; comparison = nil } }
    }
    /// Set when the person picks a delivery; otherwise the delivery the search matched.
    var chosenDelivery: Delivery.ID?
    /// Two exact versions shown in place of the preview, older first.
    var comparison: (from: Comparison.End, to: Comparison.End)?
    var progress: (done: Int, total: Int)?
    var status = "Starting…"
    var observations: [String: FileObservation] = [:]
    private(set) var staging: Staging = .idle
    /// Bumped when hand-off copies are cleared: the selection's copy is prepared again, and a
    /// preparation started before the clear is never shown after it.
    private(set) var stagingGeneration = 0

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
        siblings = Artifact.deliveredWith(artifacts)
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

    /// Shows `delivery` itself, not just its file, clearing filters that would hide it. A delivery's
    /// path is its artifact's id.
    func select(_ delivery: Delivery) {
        if !results.contains(where: { $0.id == delivery.path }) { clearFilters() }
        selection = delivery.path
        chosenDelivery = delivery.id
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
        // A log folder that appeared since launch is watched from now on.
        watcher?.refresh()
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
                    let count = report.sources.values.reduce(0) { $0 + $1.failures.count }
                    let failures = count == 0 ? "" : " · \(count) logs unreadable"
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

    /// A delivery's bytes as a comparison end: its saved copy, or the file on disk while that still
    /// hashes to the delivery.
    func compareEnd(_ delivery: Delivery, artifact: Artifact) -> Comparison.End? {
        guard let sha = delivery.sha256 else { return nil }
        if hasSaved(sha) {
            return Comparison.End(title: "Delivery \(delivery.number)", source: "saved copy", sha: sha,
                                  url: indexer.store.objectURL(sha))
        }
        if observations[artifact.path]?.state.sha256 == sha {
            return Comparison.End(title: "Delivery \(delivery.number)", source: "file on disk", sha: sha,
                                  url: URL(fileURLWithPath: artifact.path))
        }
        return nil
    }

    /// The file on disk now, as checked.
    func currentEnd(_ artifact: Artifact) -> Comparison.End? {
        guard let observation = observations[artifact.path], observation.state.kind == .file,
              let sha = observation.state.sha256 else { return nil }
        return Comparison.End(title: "File on disk", source: "checked \(observation.checkedAt.formatted(date: .omitted, time: .shortened))",
                              sha: sha, url: URL(fileURLWithPath: artifact.path))
    }

    // MARK: Actions shared by buttons, menus and the right-click menu

    /// The file the Quick Look panel shows; nil closes it.
    var quickLookURL: URL?

    func toggleQuickLook() {
        quickLookURL = quickLookURL == nil ? selectedHandoffURL : nil
    }

    /// Opens the selection's verified copy (or folder) in its app.
    func openSelected() {
        if let url = selectedHandoffURL { NSWorkspace.shared.open(url) }
    }

    /// Shows the original in Finder, or the folder it was in when it is gone.
    func reveal(_ artifact: Artifact) {
        let source = URL(fileURLWithPath: artifact.path)
        if FileManager.default.fileExists(atPath: source.path) {
            NSWorkspace.shared.activateFileViewerSelecting([source])
        } else {
            NSWorkspace.shared.open(source.deletingLastPathComponent())
        }
    }

    func copyPath(_ artifact: Artifact) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(artifact.path, forType: .string)
    }

    /// A drag from a result row: the matched delivery's bytes, staged and verified only when the
    /// receiving app asks for them.
    func dragItem(for result: SearchResult) -> NSItemProvider {
        let delivery = result.artifact.deliveries[result.deliveryIndex]
        guard let sha = delivery.sha256, result.artifact.kind != .folder else { return NSItemProvider() }
        let store = indexer.store, name = result.artifact.name, source = result.artifact.path
        let provider = NSItemProvider()
        provider.suggestedName = name
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { done in
            DispatchQueue.global(qos: .userInitiated).async {
                do { done(try store.stage(sha: sha, name: name, source: source), false, nil) } catch { done(nil, false, error) }
            }
            return nil
        }
        return provider
    }

    /// Bytes Gleaner keeps: saved copies, and disposable hand-off copies.
    func storageUsage() -> (saved: Int64, handoff: Int64) {
        (Self.size(of: indexer.store.objects), Self.size(of: indexer.store.staging))
    }

    func clearHandoffCopies() {
        clearStaging()
        try? indexer.store.clearStaging()
        stagingGeneration += 1
    }

    private static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        return files.reduce(Int64(0)) { total, item in
            total + Int64((try? (item as? URL)?.resourceValues(forKeys: Set(keys)).totalFileAllocatedSize) ?? 0)
        }
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
        let generation = stagingGeneration
        staging = .preparing(sha: sha)
        let store = indexer.store
        let name = artifact.name
        let source = artifact.path
        let result = await Task.detached(priority: .userInitiated) {
            Swift.Result { try store.stage(sha: sha, name: name, source: source) }
        }.value
        // The selection moved on, another version is being prepared, or the copies were cleared:
        // this result is stale.
        guard !Task.isCancelled, generation == stagingGeneration, staging == .preparing(sha: sha) else { return }
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
