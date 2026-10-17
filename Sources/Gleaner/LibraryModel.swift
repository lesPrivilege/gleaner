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
            projectNames = Projects.names(artifacts.map(\.projectFolder))
        }
    }
    /// Paths not on disk, checked once per load and refreshed when a file is observed, so list
    /// rows never touch the disk while drawing.
    private(set) var missing: Set<String> = []
    /// The other files named in the same reply, as their deliveries from it, keyed by delivery id.
    private(set) var siblings: [Delivery.ID: [Delivery]] = [:]
    /// What each project folder is shown as; a name two projects share carries its parent folder.
    private(set) var projectNames: [String: String] = [:]
    /// False until the first read of the logs finishes.
    private(set) var indexed = false
    /// How each agent's log folder read in the latest run; nil until a run finishes, and after one
    /// that failed.
    private(set) var sources: [Provider: Indexer.Report.Source]?
    /// Why the latest run stopped before reading the logs, or why the library couldn't be read
    /// after it. What the library already showed stays.
    private(set) var indexFailure: String?
    var query = "" {
        didSet { if query != oldValue { chosenDelivery = nil } }
    }
    var kind: Artifact.Kind?
    /// The project folder shown, which tells apart projects with the same name; nil shows every project.
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

    /// The library in its standard places: Application Support, and Caches for hand-off copies.
    /// Launched with `-GleanerHome <folder>`, the app takes that folder for the home directory, so an
    /// acceptance run on synthetic logs never touches the person's own library or agent history.
    convenience init() throws {
        let fm = FileManager.default
        let home = UserDefaults.standard.string(forKey: "GleanerHome").map { URL(fileURLWithPath: $0, isDirectory: true) }
        let library = home.map { $0.appendingPathComponent("Library") }
        let support = (library?.appendingPathComponent("Application Support")
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).appendingPathComponent("Gleaner")
        let caches = (library?.appendingPathComponent("Caches")
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]).appendingPathComponent("Gleaner")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        self.init(indexer: Indexer(
            registry: try Registry(path: support.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: support.appendingPathComponent("objects"), staging: caches.appendingPathComponent("handoff")),
            sources: home.map {
                LogSources(claudeProjects: $0.appendingPathComponent(".claude/projects"), codexHome: $0.appendingPathComponent(".codex"))
            } ?? .standard))
    }

    init(indexer: Indexer) {
        self.indexer = indexer
        artifacts = (try? indexer.registry.artifacts()) ?? []
        siblings = Artifact.deliveredWith(artifacts)
        missing = Self.missing(artifacts)
        projectNames = Projects.names(artifacts.map(\.projectFolder))
    }

    /// Only what is shown to be gone: a file Gleaner can't reach is unreadable, not missing.
    private static func missing(_ artifacts: [Artifact]) -> Set<String> {
        Set(artifacts.lazy.map(\.path).filter { Locator.stat($0).kind == .missing })
    }

    /// One line about the agents' logs when something needs a look: a run that failed, or a
    /// source that can't be read or was read with problems. What the library holds stays shown.
    var logTrouble: String? {
        indexFailure ?? sources.flatMap(Wording.sourcesLine)
    }

    /// True when reading the logs again may help: a run failed, or a source wasn't read whole.
    /// Unknown record types are reported, but a reread can't change them.
    var canReadAgain: Bool {
        indexFailure != nil || sources?.values.contains(where: \.isIncomplete) == true
    }

    /// Each project once, by its most recently delivered file, most recent first.
    var projects: [Artifact] {
        var seen = Set<String>()
        return artifacts.filter { seen.insert($0.projectFolder).inserted }
    }

    /// The project `artifact` belongs to, as shown.
    func projectName(_ artifact: Artifact) -> String {
        Wording.project(projectNames[artifact.projectFolder] ?? artifact.project, inRepository: artifact.inRepository)
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
            let library = Swift.Result { try indexer.registry.artifacts() }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .success(let artifacts) = library { self.artifacts = artifacts }
                self.progress = nil
                self.indexed = true
                switch outcome {
                case .success(let report):
                    self.sources = report.sources
                case .failure:
                    self.sources = nil
                }
                self.indexFailure = switch (outcome, library) {
                case (.failure(let error), _): "Indexing failed: \(error)"
                case (_, .failure(let error)): "Gleaner couldn’t read its library: \(error)"
                default: nil
                }
                self.status = "\(self.artifacts.count) delivered files"
                self.indexing = false
                if self.pending { self.pending = false; self.reindex() }
            }
        }
    }

    var tokens: [String] { query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init) }

    var results: [SearchResult] {
        let tokens = tokens
        return artifacts.compactMap { artifact in
            guard kind == nil || artifact.kind == kind, project == nil || artifact.projectFolder == project,
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

    /// Over the save limit, so its bytes are kept only when the person asks.
    func isLarge(_ delivery: Delivery) -> Bool { delivery.capture.map(indexer.isLarge) ?? false }

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
    /// hashes to the delivery. Bytes first seen after the delivery say so.
    func compareEnd(_ delivery: Delivery, artifact: Artifact) -> Comparison.End? {
        guard let sha = delivery.sha256 else { return nil }
        let title = Wording.compareTitle(delivery)
        if hasSaved(sha) {
            return Comparison.End(title: title, source: "saved copy", sha: sha, url: indexer.store.objectURL(sha))
        }
        if observations[artifact.path]?.state.sha256 == sha {
            return Comparison.End(title: title, source: "file on disk", sha: sha, url: URL(fileURLWithPath: artifact.path))
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

    /// The last Open or Save a Copy that failed, with the delivery it was pressed on.
    private var actionFailure: (artifact: Artifact.ID, delivery: Delivery.ID, message: String)?

    /// Why the last Open or Save a Copy on this delivery failed, shown where it was pressed.
    func actionFailure(_ artifact: Artifact, _ delivery: Delivery) -> String? {
        guard let failure = actionFailure, failure.artifact == artifact.id, failure.delivery == delivery.id else { return nil }
        return failure.message
    }

    /// True while the Quick Look panel is open. The library closes it when the selection has no
    /// copy ready, so it never shows a delivery other than the selected one.
    var isQuickLookOpen = false

    /// What the Quick Look panel shows: always the selected delivery's prepared copy (or delivered
    /// folder). It stays on a delivery with the same bytes, and is nil while other bytes are being
    /// prepared, which closes the panel.
    var quickLookURL: URL? { isQuickLookOpen ? selectedHandoffURL : nil }

    func toggleQuickLook() {
        isQuickLookOpen = !isQuickLookOpen && selectedHandoffURL != nil
    }

    /// Opens the selection's verified copy (or folder) in its app, or says why it couldn't.
    func openSelected() {
        guard let (artifact, delivery, _) = selectedHandoff, let url = selectedHandoffURL else { return }
        actionFailure = nil
        Task {
            do {
                _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            } catch CocoaError.userCancelled {
                // The person said no: nothing failed.
            } catch {
                actionFailure = (artifact.id, delivery.id, Wording.openFailed(error))
            }
        }
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
    /// receiving app asks for them. Decided by that delivery's capture: a file delivery has a hash,
    /// whatever else the artifact's other deliveries were; a folder delivery has none.
    func dragItem(for result: SearchResult) -> NSItemProvider {
        let delivery = result.artifact.deliveries[result.deliveryIndex]
        guard let sha = delivery.sha256 else { return NSItemProvider() }
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

    /// Checks the file now (hash and git), off the main thread. When it is Gleaner's first read of
    /// a file whose bytes a delivery never had, the library is read again with them.
    func observe(_ artifact: Artifact) async {
        let path = artifact.path, checkout = artifact.checkout
        let indexer = indexer
        let (state, completed) = await Task.detached(priority: .userInitiated) {
            (Locator.observe(path, checkout: checkout), (try? indexer.completeCaptures(of: path, now: Date())) == true)
        }.value
        observations[path] = FileObservation(state: state, checkedAt: Date())
        if completed { artifacts = (try? indexer.registry.artifacts()) ?? artifacts }
        if state.kind == .missing { missing.insert(path) } else { missing.remove(path) }
    }

    /// Prepares a verified, immutable copy of `sha` to drag. A copy already prepared for these
    /// bytes stays shown while it is checked again, so Quick Look stays on it.
    func stage(sha: String, artifact: Artifact) async {
        let generation = stagingGeneration
        switch staging {
        case .ready(_, sha: sha): break
        default: staging = .preparing(sha: sha)
        }
        let store = indexer.store
        let name = artifact.name
        let source = artifact.path
        let result = await Task.detached(priority: .userInitiated) {
            Swift.Result { try store.stage(sha: sha, name: name, source: source) }
        }.value
        // The selection moved on, another version is being prepared, or the copies were cleared:
        // this result is stale.
        guard !Task.isCancelled, generation == stagingGeneration, staging.sha == sha else { return }
        switch result {
        case .success(let url): staging = .ready(url, sha: sha)
        case .failure(ContentStore.Failure.changed):
            staging = .failed("The file changed while Gleaner was copying it. Check again.", sha: sha)
        case .failure: staging = .failed("Gleaner couldn’t read these bytes.", sha: sha)
        }
    }

    /// Saves a copy of a delivery whose bytes are still on disk, after checking they match, or
    /// says why it couldn't.
    func saveCopy(of delivery: Delivery, artifact: Artifact) async {
        actionFailure = nil
        let indexer = indexer
        let result = await Task.detached { Result { try indexer.saveCopy(of: delivery, at: Date()) } }.value
        switch result {
        case .success: artifacts = (try? indexer.registry.artifacts()) ?? artifacts
        case .failure(let error): actionFailure = (artifact.id, delivery.id, Wording.saveFailed(error, delivery: delivery.number))
        }
        await observe(artifact)
    }
}
