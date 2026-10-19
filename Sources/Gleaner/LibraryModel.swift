import AppKit
import GleanerCore
import GleanerUI
import Observation
import UniformTypeIdentifiers

/// One search result: the work, and the delivery the search matched in it.
struct SearchResult: Identifiable {
    var work: Work
    var matched: Delivery
    var id: Work.ID { work.id }
}

/// A row of a list: a work, or one of its revisions (a delivery) listed under it.
enum OutlineRow: Hashable {
    case work(Work.ID)
    case revision(Work.ID, Delivery.ID)

    var work: Work.ID {
        switch self {
        case .work(let id), .revision(let id, _): id
        }
    }
}

/// A row under a folder's heading in a project's outline: a work, or the works of one kind that no
/// reply named itself, folded into one row when there are many (`Listing.rows`).
enum FolderItem: Identifiable {
    case work(SearchResult)
    case folded(key: String, kind: Artifact.Kind, results: [SearchResult])

    var id: String {
        switch self {
        case .work(let result): result.id
        case .folded(let key, _, _): "folded\n" + key
        }
    }
}

/// Where the library window is: every delivery, one project, or what Gleaner reads and keeps.
enum Place: Hashable {
    case all
    case project(String)
    case sources
}

/// A page of what Gleaner reads and keeps.
enum SourcePage: Hashable {
    case agent(Provider)
    case corrections
    case storage
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
    /// Every delivery the library holds, whichever agent's.
    private var library: [Artifact] = []
    /// The agents whose logs the person turned off: not read, not watched, not shown.
    private(set) var sourcesOff: Set<Provider> = []
    /// What the window shows: the library without the deliveries of the agents turned off.
    private(set) var artifacts: [Artifact] = []
    /// Each file Gleaner observed appearing or changing during sessions, whichever agent's, with its
    /// observations: candidates beside the deliveries, never deliveries (docs/design/capture.md).
    /// Grouped by file once per load, off the main thread after a run.
    private var observed: [Candidate] = []
    /// Projects and works as the person sees them: what Gleaner found, with their corrections.
    private(set) var organization = Organization(artifacts: [])
    /// The person's corrections and projects, read from the library; kept apart from what Gleaner found.
    private(set) var corrections: [Correction] = []
    private(set) var userProjects: [UserProject] = []
    /// The work units the person made, as made; `organization` shows them as named last.
    private(set) var units: [WorkUnit] = []
    /// Every verdict and published mark, by the file each was made on.
    private(set) var reviews = Reviews([])
    /// Why the last correction couldn't be recorded.
    private(set) var correctionFailure: String?
    /// Why the last verdict or mark couldn't be made.
    private(set) var reviewFailure: String?
    /// The size, dates and inode of each file a review state is shown for (the current file of each
    /// work in a unit or with a verdict or mark), nil when no regular file is there: taken with each
    /// organization, never by reading bytes, so the review states never touch the disk while they
    /// are drawn.
    private var listed: [String: FileStat?] = [:]
    /// The bytes read of a file this session, on select or for a verdict, with the file as it was
    /// then: they stand for the file while it is still so.
    private var reads: [String: (sha256: String, file: FileStat)] = [:]
    /// Paths not on disk, checked once per load and refreshed when a file is observed, so list
    /// rows never touch the disk while drawing.
    private(set) var missing: Set<String> = []
    /// The versions whose saved copies the store holds, checked as `missing` is, so the detail and
    /// the list rows agree on what can be handed over.
    private(set) var saved: Set<String> = []
    /// The other files named in the same reply, as their deliveries from it, keyed by delivery id.
    private(set) var siblings: [Delivery.ID: [Delivery]] = [:]
    /// False until the first read of the logs finishes.
    private(set) var indexed = false
    /// How each agent's log folder read in the latest run; nil until a run finishes, and after one
    /// that failed.
    private(set) var sources: [Provider: Indexer.Report.Source]?
    /// Why the latest run stopped before reading the logs, or why the library couldn't be read
    /// after it. What the library already showed stays.
    private(set) var indexFailure: String?
    /// When the latest run finished.
    private(set) var lastRead: Date?
    var query = "" {
        didSet {
            if query != oldValue { chosenDelivery = nil }
            // A search looks through deliveries, not through the sources.
            if !query.isEmpty, place == .sources { place = .all }
        }
    }
    var kind: Artifact.Kind?
    var place: Place = .all {
        didSet { if place != oldValue, case .project = place { kind = nil } }
    }
    var sourcePage: SourcePage = .agent(.claudeCode)
    /// The work shown: its id, or any of its files' paths.
    var selection: Work.ID? {
        didSet { if selection != oldValue { chosenDelivery = nil; comparison = nil } }
    }
    /// Set when the person picks a delivery; otherwise the delivery the search matched.
    var chosenDelivery: Delivery.ID?
    /// Works the person opened or closed in a list this session, wherever it is listed; the rest
    /// follow `opensByDefault`.
    var disclosed: [Work.ID: Bool] = [:]
    /// Folded rows of an outline the person opened or closed this session, by folder and kind; the
    /// rest stay folded unless they hold the selection.
    var unfolded: [String: Bool] = [:]
    /// Two exact versions shown in place of the preview, older first.
    var comparison: (from: Comparison.End, to: Comparison.End)?
    var progress: (done: Int, total: Int)?
    var status = "Starting…"
    var observations: [String: FileObservation] = [:]
    private(set) var staging: Staging = .idle
    /// The prepared copy's text, read once it was verified, for the preview: never read again from
    /// the copy while it is shown, so the preview stays the bytes that were checked.
    private(set) var preparedText: (sha: String, text: String, truncated: Bool)?
    /// The copy `staging` names as ready, with what tells whether it is still the file hashed.
    private var prepared: ContentStore.Prepared?
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
        let indexer = Indexer(
            registry: try Registry(path: support.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: support.appendingPathComponent("objects"), staging: caches.appendingPathComponent("handoff")),
            sources: home.map {
                LogSources(claudeProjects: $0.appendingPathComponent(".claude/projects"), codexHome: $0.appendingPathComponent(".codex"))
            } ?? .standard)
        // A session working in the home folder has no workspace walked, the synthetic one included.
        if let home { indexer.home = home.path }
        self.init(indexer: indexer, loads: false)
    }

    /// With `loads`, the library is read at once, on the caller's thread; the app opens its window
    /// first and reads it when it starts, off the main thread.
    init(indexer: Indexer, loads: Bool = true) {
        self.indexer = indexer
        corrections = (try? indexer.registry.corrections()) ?? []
        userProjects = (try? indexer.registry.userProjects()) ?? []
        units = (try? indexer.registry.units()) ?? []
        reviews = Reviews((try? indexer.registry.reviews()) ?? [])
        sourcesOff = (try? indexer.registry.sourcesOff()) ?? []
        if loads {
            observed = Candidate.files((try? indexer.registry.observations()) ?? [])
            show((try? indexer.registry.artifacts()) ?? [])
        }
    }

    /// Shows the library as just read, and what the window works out from it: what each file was
    /// delivered with, what is gone, which versions are saved, and the organization.
    private func show(_ library: [Artifact]) {
        self.library = library
        showArtifacts()
    }

    private func showArtifacts() {
        artifacts = Self.shown(library, without: sourcesOff)
        siblings = Artifact.deliveredWith(artifacts)
        missing = Self.missing(artifacts)
        saved = Self.saved(artifacts, in: indexer.store)
        reorganize()
    }

    /// Puts `artifact` in place of the file at its path, after Gleaner first read the file or saved
    /// a copy of it: only that file's deliveries changed, so nothing else is read or worked out
    /// again, however large the library (SPEC §5.4). Its work takes it in place, wherever it is
    /// listed; joins suggested from its new hash wait for the next read of the library. When only
    /// its captures changed, as a first read or a saved copy changes them, nothing that lists or
    /// groups works moved: the lists already made keep their rows, with the work as it is now, and
    /// the files its replies named with it list its deliveries as they are now.
    private func replace(_ artifact: Artifact) {
        guard let index = library.firstIndex(where: { $0.path == artifact.path }) else { return }
        library[index] = artifact
        guard let shown = Self.shown([artifact], without: sourcesOff).first,
              let place = artifacts.firstIndex(where: { $0.path == artifact.path }) else { return }
        let before = artifacts[place]
        artifacts[place] = shown
        saved.formUnion(shown.deliveries.compactMap(\.sha256).filter(indexer.store.has))
        organization = organization.replacing(shown)
        guard Self.capturesOnly(before, shown), let work = organization.work(containing: shown.path) else {
            // A delivered folder's files aren't among the files a reply named with others.
            if shown.deliveries.contains(where: { $0.member == nil }) { siblings = Artifact.deliveredWith(artifacts) }
            organizationVersion += 1
            return
        }
        for delivery in shown.deliveries where delivery.member == nil {
            for other in siblings[delivery.id] ?? [] {
                siblings[other.id] = siblings[other.id]?.map { $0.id == delivery.id ? delivery : $0 }
            }
        }
        refreshLists(work)
    }

    /// Whether `new` differs from `old` only in what was recorded of its bytes: the same deliveries,
    /// at the same times, named or handed over in folders as before, folders as before, in the same
    /// place. What lists, orders, folds and finds a work is then the same.
    private static func capturesOnly(_ old: Artifact, _ new: Artifact) -> Bool {
        old.projectFolder == new.projectFolder && old.inRepository == new.inRepository && old.checkout == new.checkout
            && old.deliveries.count == new.deliveries.count
            && zip(old.deliveries, new.deliveries).allSatisfy { a, b in
                a.id == b.id && a.deliveredAt == b.deliveredAt && a.member == b.member && a.capture?.isDirectory == b.capture?.isDirectory
            }
    }

    /// Puts `work`, as it is now, in place of itself in the results and the outline already made,
    /// which keep their rows and order, each result keeping the delivery it matched.
    private func refreshLists(_ work: Work) {
        let id = work.id
        func refreshed(_ result: SearchResult) -> SearchResult {
            guard result.work.id == id else { return result }
            return SearchResult(work: work, matched: work.deliveries.first { $0.id == result.matched.id } ?? work.deliveries[0])
        }
        // Changed in place: a copy of either list held meanwhile would copy every row.
        if let at = resultsCache?.results.firstIndex(where: { $0.id == id }), let result = resultsCache?.results[at] {
            resultsCache?.results[at] = refreshed(result)
        }
        guard var cached = outlineCache, let project = organization.project(cached.project) else { return }
        let name = outlineFolder(work, in: project)
        guard let folder = cached.outline.firstIndex(where: { $0.folder == name }),
              let at = cached.outline[folder].items.firstIndex(where: {
                  switch $0 {
                  case .work(let result): result.id == id
                  case .folded(_, _, let results): results.contains { $0.id == id }
                  }
              }) else { return }
        outlineCache = nil
        cached.outline[folder].items[at] = switch cached.outline[folder].items[at] {
        case .work(let result): .work(refreshed(result))
        case .folded(let key, let kind, let results): .folded(key: key, kind: kind, results: results.map(refreshed))
        }
        outlineCache = cached
    }

    /// Reads the deliveries of the file at `path` again, off the main thread, after Gleaner first
    /// read it or saved a copy of it, and puts them in place.
    private func reread(_ path: String) async {
        let registry = indexer.registry
        if let artifact = await Task.detached(priority: .userInitiated, operation: { try? registry.artifact(at: path) }).value {
            replace(artifact)
        }
    }

    private func reorganize() {
        // An agent turned off has its observations hidden with its deliveries.
        let observed = sourcesOff.isEmpty ? observed : observed.compactMap { $0.keeping { !sourcesOff.contains($0.provider) } }
        organization = Organization(artifacts: artifacts, observed: observed, corrections: corrections,
                                    projects: userProjects, units: units, missing: missing)
        organizationVersion += 1
        statReviewed()
        if indexed { updateStatus() }
    }

    /// The subtitle: what the library holds, as organized now.
    private func updateStatus() {
        status = Wording.library(works: organization.works.count, deliveries: artifacts.map(\.deliveries.count).reduce(0, +))
    }

    /// Bumped with each organization rebuilt or changed in a way that moves what lists or groups a
    /// work, so a listing made before is never reused after.
    @ObservationIgnored private(set) var organizationVersion = 0

    /// Only what is shown to be gone: a file Gleaner can't reach is unreadable, not missing.
    private static func missing(_ artifacts: [Artifact]) -> Set<String> {
        Set(artifacts.lazy.map(\.path).filter { Locator.stat($0).kind == .missing })
    }

    /// The store is shared by content: a copy saved for one file serves every file with its bytes.
    private static func saved(_ artifacts: [Artifact], in store: ContentStore) -> Set<String> {
        Set(artifacts.lazy.flatMap(\.deliveries).compactMap(\.sha256).filter(store.has))
    }

    /// One line about the agents' logs when something needs a look: a run that failed, or a
    /// source that can't be read or was read with problems. What the library holds stays shown.
    var logTrouble: String? {
        indexFailure ?? sources.flatMap { Wording.sourcesLine($0.filter { !sourcesOff.contains($0.key) }) }
    }

    /// True when reading the logs again may help: a run failed, or a source wasn't read whole.
    /// Unknown record types are reported, but a reread can't change them.
    var canReadAgain: Bool {
        indexFailure != nil || sources?.contains(where: { !sourcesOff.contains($0.key) && $0.value.isIncomplete }) == true
    }

    /// Projects, newest activity first.
    var projects: [Organization.Project] { organization.projects }

    /// The project a work is shown in, as shown.
    func projectName(_ work: Work) -> String {
        let name = organization.projectName(work.project)
        return organization.project(work.project)?.origin == .folder ? Wording.project(name, inRepository: false) : name
    }

    /// The folder a work is listed under in a project's outline: where its newest file is, from the
    /// checkout or folder holding it, with the worktree named; outside it, the folder itself. In a
    /// project the person made, the project Gleaner found it in comes first. Empty at the top level.
    func outlineFolder(_ work: Work, in project: Organization.Project) -> String {
        let file = work.latest
        return outlineFolder(file.path, checkout: file.checkout, projectFolder: file.projectFolder, inRepository: file.inRepository, in: project)
    }

    /// The folder an observed file is listed under, as a work there is: beside what was handed over.
    func outlineFolder(_ candidate: Candidate, in project: Organization.Project) -> String {
        outlineFolder(candidate.path, checkout: candidate.checkout, projectFolder: candidate.projectFolder,
                      inRepository: candidate.inRepository, in: project)
    }

    private func outlineFolder(_ path: String, checkout: Checkout?, projectFolder: String, inRepository: Bool,
                               in project: Organization.Project) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        let base = checkout?.folder ?? project.folder ?? projectFolder
        var folder = directory == base ? ""
            : directory.hasPrefix(base + "/") ? String(directory.dropFirst(base.count + 1))
            : (inRepository ? "Outside the repository: " : "Elsewhere: ") + (directory as NSString).abbreviatingWithTildeInPath
        if let checkout, checkout.folder != checkout.repository {
            folder = "worktree " + (checkout.folder as NSString).lastPathComponent + (folder.isEmpty ? "" : " › " + folder)
        }
        if project.origin == .yours || projectFolder != project.key && project.folder != base {
            let found = organization.projectName(projectFolder)
            folder = found + (folder.isEmpty ? "" : " › " + folder)
        }
        return folder
    }

    /// The project shown, when the window is on one.
    var currentProject: Organization.Project? {
        if case .project(let key) = place { organization.project(key) } else { nil }
    }

    func clearFilters() {
        query = ""
        kind = nil
    }

    /// Shows `delivery` itself, not just its file, clearing filters that would hide it, and
    /// going to its work's project when the window shows another.
    func select(_ delivery: Delivery) {
        guard let work = organization.work(containing: delivery.path) else { return }
        if case .project(let key) = place, key != work.project { place = .project(work.project) }
        if place == .sources { place = .all }
        if !results.contains(where: { $0.id == work.id }) { clearFilters() }
        selection = work.id
        chosenDelivery = delivery.id
    }

    /// Watches the logs, shows the library as it was while they are read, then reads them. The
    /// library is read off the main thread, and never shown over what a finished run showed.
    func start() {
        watch()
        let indexer = indexer
        work.async {
            let artifacts = try? indexer.registry.artifacts(), observed = Candidate.files((try? indexer.registry.observations()) ?? [])
            Task { @MainActor [weak self] in
                guard let self, !self.indexed, let artifacts else { return }
                self.observed = observed
                self.show(artifacts)
            }
        }
        reindex()
    }

    /// Watches the log folders of the agents that are on.
    private func watch() {
        let folders = Provider.allCases.filter { !sourcesOff.contains($0) }.map { indexer.sources.folder($0).path }
        watcher = folders.isEmpty ? nil : LogWatcher(directories: folders, queue: work) { [weak self] in
            Task { @MainActor in self?.reindex() }
        }
    }

    /// The library without `off`'s deliveries, and without the files left with none.
    private static func shown(_ library: [Artifact], without off: Set<Provider>) -> [Artifact] {
        guard !off.isEmpty else { return library }
        return library.compactMap { $0.keeping { !off.contains($0.provider) } }
    }

    /// Turns an agent's logs on or off (`Registry.setSource`). On again, they are read at once.
    func setSource(_ provider: Provider, on: Bool) async {
        let registry: Registry
        do { registry = try correctionsStore() } catch { return }
        let queue = correctionQueue
        let stored = await withCheckedContinuation { done in
            queue.async { done.resume(returning: Result { try registry.setSource(provider, on: on, at: Date()); return try registry.sourcesOff() }) }
        }
        guard case .success(let off) = stored else { return }
        sourcesOff = off
        showArtifacts()
        if watcher != nil || on { watch() }
        if on { reindex() }
        announce("\(Wording.provider(provider)) \(on ? "on" : "off")")
    }

    /// Every delivery the library holds from `provider`, shown or not.
    func deliveries(of provider: Provider) -> [Delivery] {
        library.flatMap(\.deliveries).filter { $0.provider == provider }
    }

    /// What each model wrote, for one agent: the provider it went through, the model, and how many
    /// deliveries, the most first. Turned off, the agent's are still counted from the library.
    func models(of provider: Provider) -> [(provider: String?, model: String?, deliveries: Int)] {
        let deliveries = deliveries(of: provider)
        let counts = Dictionary(grouping: deliveries) { [$0.modelProvider ?? "", $0.model ?? ""] }
        return counts.map { key, list in (key[0].isEmpty ? nil : key[0], key[1].isEmpty ? nil : key[1], list.count) }
            .sorted { $0.deliveries != $1.deliveries ? $0.deliveries > $1.deliveries : ($0.model ?? "") < ($1.model ?? "") }
    }

    func reindex() {
        guard !indexing else { pending = true; return }
        indexing = true
        // A log folder that appeared since launch is watched from now on.
        watcher?.refresh()
        let indexer = indexer, on = Set(Provider.allCases).subtracting(sourcesOff)
        work.async {
            let outcome = Swift.Result {
                try indexer.run(providers: on, progress: { done, total in
                    Task { @MainActor [weak self] in self?.progress = total > 0 && done < total ? (done, total) : nil }
                })
            }
            // The library loads on every run, which looks again at what is on disk; the observations
            // only when the run recorded one, since nothing else changes them.
            let recorded = (try? outcome.get()).map { $0.newObservations > 0 } ?? true
            let library = Swift.Result { (try indexer.registry.artifacts(), recorded ? Candidate.files(try indexer.registry.observations()) : nil) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .success(let (artifacts, observed)) = library {
                    // Set first: the library's change reorganizes with them.
                    if let observed { self.observed = observed }
                    self.show(artifacts)
                }
                self.progress = nil
                self.indexed = true
                self.lastRead = Date()
                self.updateStatus()
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
                self.indexing = false
                if self.pending { self.pending = false; self.reindex() }
            }
        }
    }

    var tokens: [String] { query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init) }

    /// The works the window lists, newest first: in the project shown, of the kind chosen, matching the search.
    var results: [SearchResult] {
        let tokens = tokens
        let key = ResultsKey(tokens: tokens, kind: kind, place: place, organization: organizationVersion)
        if let cached = resultsCache, cached.key == key { return cached.results }
        let results = organization.works.compactMap { result(for: $0, tokens: tokens) }
        resultsCache = (key, results)
        return results
    }

    /// What the list depends on: it is listed again only when one of these changes, not each time
    /// a view asks for it.
    private struct ResultsKey: Equatable {
        var tokens: [String], kind: Artifact.Kind?, place: Place, organization: Int
    }
    @ObservationIgnored private var resultsCache: (key: ResultsKey, results: [SearchResult])?

    /// The work as the list shows it, or nil when the place, kind or search leaves it out.
    func result(for work: Work) -> SearchResult? { result(for: work, tokens: tokens) }

    private func result(for work: Work, tokens: [String]) -> SearchResult? {
        if case .project(let key) = place, work.project != key { return nil }
        guard kind == nil || work.kind == kind,
              let matched = work.match(tokens, project: organization.projectName(work.project)) else { return nil }
        return SearchResult(work: work, matched: matched)
    }

    /// The selected work, as the list shows it: looked up, not found by listing every work, since
    /// the detail asks for it many times each time it is drawn.
    var selected: SearchResult? {
        // The Sources page hides the selection: menus and Quick Look don't act on what isn't shown.
        guard place != .sources, let selection, let work = organization.work(containing: selection) else { return nil }
        return result(for: work, tokens: tokens)
    }

    func delivery(in result: SearchResult) -> Delivery {
        if let chosen = chosenDelivery, let d = result.work.deliveries.first(where: { $0.id == chosen }) { return d }
        return result.matched
    }

    /// The file a result shows and hands over: the one holding the delivery it shows.
    func file(in result: SearchResult) -> Artifact {
        result.work.file(of: delivery(in: result))
    }

    // MARK: The outline

    /// Whether a list shows the work's revisions under it. A work with one has nothing to show.
    func isOpen(_ work: Work) -> Bool {
        work.deliveries.count > 1 && (disclosed[work.id] ?? opensByDefault)
    }

    /// A project's outline opens each work on its revisions, since each is a step the person may
    /// return to (a draft, a revision, the final), except in a git repository: agents revise code
    /// quickly, the newest revision is the one picked up, and the repository's folders already
    /// guide. Lists of what arrived, every delivery and search results, keep works closed.
    var opensByDefault: Bool {
        guard query.isEmpty, let project = currentProject else { return false }
        return project.origin != .repository
    }

    /// The selected row: the revision shown, while its work is open; otherwise the work. Choosing a
    /// row shows what it names, as choosing a delivery under Versions does; choosing the row
    /// already selected changes nothing.
    var outlineSelection: OutlineRow? {
        get {
            guard let selection, let work = organization.work(containing: selection) else { return selection.map(OutlineRow.work) }
            if let chosen = chosenDelivery, isOpen(work), work.deliveries.contains(where: { $0.id == chosen }) {
                return .revision(work.id, chosen)
            }
            return .work(work.id)
        }
        set {
            guard newValue != outlineSelection else { return }
            switch newValue {
            case nil:
                selection = nil
            case .work(let id):
                selection = id
                chosenDelivery = nil
            case .revision(let id, let delivery):
                selection = id
                chosenDelivery = delivery
            }
        }
    }

    /// A project's outline below its head: each folder its works are in (`outlineFolder`), in the
    /// project's own layout, with how many works it holds and its rows (`outlineItems`). Made again
    /// only when what the window lists changes, not each time the outline is drawn.
    func outline(of project: Organization.Project) -> [(folder: String, count: Int, items: [FolderItem])] {
        let key = ResultsKey(tokens: tokens, kind: kind, place: place, organization: organizationVersion)
        if let cached = outlineCache, cached.key == key, cached.project == project.key { return cached.outline }
        let folders = Dictionary(grouping: results) { outlineFolder($0.work, in: project) }
        let outline = folders.keys
            .sorted { a, b in a.isEmpty != b.isEmpty ? a.isEmpty : a.localizedStandardCompare(b) == .orderedAscending }
            .map { (folder: $0, count: folders[$0]!.count, items: outlineItems(folders[$0]!)) }
        outlineCache = (key, project.key, outline)
        return outline
    }
    @ObservationIgnored private var outlineCache: (key: ResultsKey, project: String, outline: [(folder: String, count: Int, items: [FolderItem])])?

    /// A folder's works as its outline lists them (docs/design/capture.md, "Order and grouping"):
    /// what a person opens before what a program reads, newest first, files sharing a stem side by
    /// side, and the files of one kind that no reply named itself folded when they crowd the folder.
    /// A file a reply named never folds.
    func outlineItems(_ results: [SearchResult]) -> [FolderItem] {
        let byID = Dictionary(results.map { ($0.work.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Listing.rows(results.map { .work($0.work) }).flatMap { row -> [FolderItem] in
            switch row {
            case .entry(let entry): [byID[entry.id]].compactMap { $0.map(FolderItem.work) }
            case .together(_, let entries): entries.compactMap { byID[$0.id].map(FolderItem.work) }
            case .folded(let folder, let kind, let entries):
                [.folded(key: folder + "\n" + kind.rawValue, kind: kind, results: entries.compactMap { byID[$0.id] })]
            }
        }
    }

    /// Whether a folded row of an outline shows its works: as the person left it, else open while
    /// it holds the selection, so a work chosen elsewhere is shown where it is listed.
    func isUnfolded(_ key: String, _ results: [SearchResult]) -> Bool {
        if let open = unfolded[key] { return open }
        guard let selection, let selected = organization.work(containing: selection) else { return false }
        return results.contains { $0.work.id == selected.id }
    }

    /// The delivery of the folder a file was handed over in, while the library shows it.
    func folderDelivery(_ member: Membership) -> Delivery? {
        organization.work(containing: member.folder)?.deliveries.first { $0.id == member.folderDelivery }
    }

    /// What a work's own row names. Closed, it stands for its revisions: the one chosen in the
    /// detail, else the one the search matched. Open, each revision's row stands for itself, and
    /// the work's row for the work: the matched one, whichever revision is chosen.
    func workDelivery(_ result: SearchResult) -> Delivery {
        isOpen(result.work) ? result.matched : delivery(in: result)
    }

    /// The file and delivery a row names: a revision's own, or what its work's row names.
    func target(_ row: OutlineRow) -> (artifact: Artifact, delivery: Delivery)? {
        guard let work = organization.work(containing: row.work) else { return nil }
        if case .revision(_, let id) = row, let delivery = work.deliveries.first(where: { $0.id == id }) {
            return (work.file(of: delivery), delivery)
        }
        let delivery = workDelivery(result(for: work) ?? SearchResult(work: work, matched: work.deliveries[0]))
        return (work.file(of: delivery), delivery)
    }

    func hasSaved(_ sha: String) -> Bool { saved.contains(sha) }

    /// Over the save limit, so its bytes are kept only when the person asks.
    func isLarge(_ delivery: Delivery) -> Bool { delivery.capture.map(indexer.isLarge) ?? false }

    /// What the selection would hand over now, once its file has been checked.
    var selectedHandoff: (artifact: Artifact, delivery: Delivery, plan: Handoff)? {
        guard let result = selected else { return nil }
        let artifact = file(in: result), delivery = delivery(in: result)
        guard let observation = observations[artifact.path] else { return nil }
        return (artifact, delivery, artifact.handoff(delivery, now: observation, hasSaved: hasSaved))
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
    /// `named` puts the file's name in the title, for a work of several files.
    func compareEnd(_ delivery: Delivery, artifact: Artifact, named: Bool = false) -> Comparison.End? {
        guard let sha = delivery.sha256 else { return nil }
        let title = (named ? artifact.name + " · " : "") + Wording.compareTitle(delivery)
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

    // MARK: Corrections

    /// Corrections are written over a connection of their own: the indexer's holds a transaction
    /// while it reads a log, and a write over it would join that transaction, or fail.
    @ObservationIgnored private var correctionsRegistry: Registry?

    private func correctionsStore() throws -> Registry {
        if let registry = correctionsRegistry { return registry }
        let registry = try Registry(path: indexer.registry.path)
        correctionsRegistry = registry
        return registry
    }

    /// Decisions are recorded one at a time, in the order they were made.
    private let correctionQueue = DispatchQueue(label: "gleaner.corrections", qos: .userInitiated)

    /// The window's undo manager: each decision goes on Edit › Undo under its own name.
    @ObservationIgnored weak var undoManager: UndoManager?

    /// Puts the decisions recorded since `before` on Edit › Undo, as `name`.
    private func undoable(_ name: String, since before: Set<Correction.ID>) {
        let made = corrections.filter { !before.contains($0.id) }
        guard !made.isEmpty, let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in Task { await model.undo(made) } }
        undoManager.setActionName(name)
    }

    /// Records a decision off the main thread, after the log being read if there is one, then
    /// shows the library with it; or says why it couldn't be recorded, and leaves the library as
    /// it was.
    @discardableResult
    private func correcting<T: Sendable>(_ change: @escaping @Sendable (Registry) throws -> T) async -> T? {
        let outcome: Result<(T, [Correction], [UserProject], [WorkUnit], [String: Artifact?]), Error>
        do {
            let registry = try correctionsStore(), queue = correctionQueue, keptBefore = Self.kept(corrections)
            outcome = await withCheckedContinuation { done in
                queue.async { done.resume(returning: Result {
                    let value = try change(registry), corrections = try registry.corrections()
                    // A file kept, or no longer kept, is read again: its revision comes or goes.
                    var kept: [String: Artifact?] = [:]
                    for path in Self.kept(corrections).symmetricDifference(keptBefore) { kept[path] = .some(try registry.artifact(at: path)) }
                    return (value, corrections, try registry.userProjects(), try registry.units(), kept)
                }) }
            }
        } catch {
            outcome = .failure(error)
        }
        switch outcome {
        case .success(let (value, corrections, projects, units, kept)):
            self.corrections = corrections
            userProjects = projects
            self.units = units
            correctionFailure = nil
            if kept.isEmpty {
                reorganize()
            } else {
                for (path, artifact) in kept {
                    library.removeAll { $0.path == path }
                    if let artifact { library.append(artifact) }
                }
                showArtifacts()
            }
            return value
        case .failure(let error):
            correctionFailure = "Couldn’t record that: \(error.localizedDescription)"
            return nil
        }
    }

    /// The files the person kept.
    nonisolated private static func kept(_ corrections: [Correction]) -> Set<String> {
        Set(corrections.filter { $0.kind == .kept }.map(\.subject))
    }

    /// Says a decision's result to VoiceOver once it is recorded; a failure is said where it shows.
    private func said(_ text: String) {
        announce(correctionFailure ?? text)
    }

    /// Shows the work holding `path` where it now is: selected, in its project when the window
    /// shows a project. Not when the person went elsewhere while the decision was recorded.
    private func follow(_ path: String, from before: (Place, Work.ID?)) {
        guard place == before.0, selection == before.1, let work = organization.work(containing: path) else { return }
        if case .project(let key) = place, key != work.project { place = .project(work.project) }
        selection = work.id
    }

    /// Puts the work, every one of its files, in the project `key`.
    func move(_ work: Work, to key: String) async {
        let paths = work.files.map(\.path), before = (place, selection), made = Set(corrections.map(\.id))
        await correcting { try $0.correct(.project, subjects: paths, target: key, at: Date()) }
        undoable("Move", since: made)
        follow(work.id, from: before)
        said("Moved \(work.name) to \(organization.projectName(key))")
    }

    /// Makes a project of the person's own and puts the work in it.
    func move(_ work: Work, toNewProject name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines), paths = work.files.map(\.path), before = (place, selection)
        guard !name.isEmpty else { return }
        let existing = Set(userProjects.map(\.key))
        await correcting { try $0.addProject(named: name, at: Date(), moving: paths) }
        if let made = userProjects.first(where: { !existing.contains($0.key) }), let undoManager {
            undoManager.registerUndo(withTarget: self) { model in
                Task { if let project = model.organization.project(made.key) { await model.remove(project) } }
            }
            undoManager.setActionName("Move")
        }
        follow(work.id, from: before)
        said("Moved \(work.name) to \(name)")
    }

    /// Gleaner puts the work back where it found it.
    func undoMove(_ work: Work) async {
        let moves = corrections.filter { $0.kind == .project && work.contains($0.subject) }.map(\.id), before = (place, selection)
        await correcting { try $0.undo(moves) }
        follow(work.id, from: before)
        said("Put \(work.name) back")
    }

    /// The two files are versions of one work, from now on and after every reread.
    func join(_ a: String, _ b: String) async {
        let before = (place, selection), made = Set(corrections.map(\.id))
        await correcting { try $0.correct(.sameWork, subject: a, target: b, at: Date()) }
        undoable("Join", since: made)
        follow(a, from: before)
        said("Joined \((a as NSString).lastPathComponent) and \((b as NSString).lastPathComponent)")
    }

    /// The two files are not one work: Gleaner stops suggesting it.
    func keepApart(_ a: String, _ b: String) async {
        let made = Set(corrections.map(\.id))
        await correcting { try $0.correct(.notSameWork, subject: a, target: b, at: Date()) }
        undoable("Keep Apart", since: made)
        said("Kept \((a as NSString).lastPathComponent) and \((b as NSString).lastPathComponent) apart")
    }

    /// The observed file at `path` isn't from the session whose log is `logPath`: its observation
    /// stays recorded, and isn't shown with that session.
    func detach(_ path: String, from logPath: String) async {
        let made = Set(corrections.map(\.id))
        await correcting { try $0.correct(.notFromSession, subject: path, target: logPath, at: Date()) }
        undoable("Detach", since: made)
        said("Detached \((path as NSString).lastPathComponent) from \(sessionName(logPath))")
    }

    /// The observed file at `path` goes with `work`: shown with it, never one of its versions.
    func relate(_ path: String, to work: Work) async {
        let made = Set(corrections.map(\.id)), target = work.latest.path
        await correcting { try $0.correct(.related, subject: path, target: target, at: Date()) }
        undoable("Relate", since: made)
        said("Related \((path as NSString).lastPathComponent) to \(work.name)")
    }

    /// The session whose log is `logPath`, as its observations name it.
    func sessionName(_ logPath: String) -> String {
        Wording.session(observed.lazy.flatMap(\.observations).first { $0.logPath == logPath }?.sessionTitle)
    }

    /// Undoes decisions made together, such as moving every file of a work. With `following`,
    /// the window follows the selected work to where it now is.
    func undo(_ corrections: [Correction], following: Bool = true) async {
        let ids = corrections.map(\.id), before = (place, selection)
        await correcting { try $0.undo(ids) }
        if following, let selected = before.1 { follow(selected, from: before) }
        said("Undone")
    }

    func undo(_ correction: Correction, following: Bool = true) async {
        await undo([correction], following: following)
    }

    func undoAllCorrections() async {
        await correcting { try $0.undoAllCorrections() }
        if case .project(let key) = place, organization.project(key) == nil { place = .all }
    }

    /// Shows the project `folder` inside the project `key`.
    func combine(_ folder: String, into key: String) async {
        let made = Set(corrections.map(\.id))
        await correcting { try $0.correct(.combine, subject: folder, target: key, at: Date()) }
        undoable("Show Inside", since: made)
        place = .project(key)
        said("Showed \(organization.projectName(folder)) inside \(organization.projectName(key))")
    }

    func rename(_ project: Organization.Project, to name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines), key = project.key
        guard project.origin == .yours, !name.isEmpty else { return }
        await correcting { try $0.renameProject(key, to: name) }
    }

    /// Removes a project the person made; its work goes back where Gleaner found it.
    func remove(_ project: Organization.Project) async {
        let key = project.key
        guard project.origin == .yours else { return }
        await correcting { try $0.removeProject(key) }
        if place == .project(key) { place = .all }
    }

    /// The corrections, newest first, decisions made together as one: a move of several files, a
    /// work of several files added to a unit, an observed file kept and added to one.
    var correctionGroups: [[Correction]] {
        var groups: [[Correction]] = []
        for correction in corrections.reversed() {
            if let last = groups.last?.last, last.madeAt == correction.madeAt {
                groups[groups.count - 1].append(correction)
            } else {
                groups.append([correction])
            }
        }
        return groups
    }

    /// What decisions made together did, in a sentence: those of one kind and target with every
    /// file named, then the others.
    func describe(_ group: [Correction]) -> String {
        guard group.count > 1 else { return group.first.map(describe) ?? "" }
        let ordered = group.sorted { $0.id < $1.id }
        var parts: [String] = [], said = Set<String>()
        for c in ordered where said.insert(c.kind.rawValue + "\n" + c.target).inserted {
            let same = ordered.filter { $0.kind == c.kind && $0.target == c.target }
            let names = same.map { ($0.subject as NSString).lastPathComponent }.joined(separator: ", ")
            switch c.kind {
            case .project: parts.append("Moved \(names) to \(organization.projectName(c.target))")
            case .unit: parts.append("Added \(names) to \(organization.unitName(c.target))")
            case .outOfUnit: parts.append("Removed \(names) from \(organization.unitName(c.target))")
            default: parts += same.map(describe)
            }
        }
        return parts.joined(separator: "; ")
    }

    /// What a correction did, in a sentence, for the list of corrections.
    func describe(_ correction: Correction) -> String {
        let name = { (path: String) in (path as NSString).lastPathComponent }
        return switch correction.kind {
        case .project: "Moved \(name(correction.subject)) to \(organization.projectName(correction.target))"
        case .combine: "Showed \(organization.projectName(correction.subject)) inside \(organization.projectName(correction.target))"
        case .sameWork: "Joined \(name(correction.subject)) and \(name(correction.target))"
        case .notSameWork: "Kept \(name(correction.subject)) and \(name(correction.target)) apart"
        case .notFromSession: "Detached \(name(correction.subject)) from \(sessionName(correction.target))"
        case .related: "Related \(name(correction.subject)) to \(organization.work(containing: correction.target)?.name ?? name(correction.target))"
        case .kept: "Kept \(name(correction.subject)), observed during \(sessionName(correction.target))"
        case .unit: "Added \(name(correction.subject)) to \(organization.unitName(correction.target))"
        case .outOfUnit: "Removed \(name(correction.subject)) from \(organization.unitName(correction.target))"
        case .unitName: "Renamed \(unitName(correction.subject, before: correction)) to \(correction.target)"
        case .unitDeleted: "Deleted \(organization.unitName(correction.subject))"
        }
    }

    /// The name the unit `key` had before `correction` renamed it.
    private func unitName(_ key: String, before correction: Correction) -> String {
        corrections.last { $0.kind == .unitName && $0.subject == key && ($0.madeAt, $0.id) < (correction.madeAt, correction.id) }?.target
            ?? units.first { $0.key == key }?.name ?? ""
    }

    // MARK: Work units, keeping and review (docs/design/review.md)

    /// Makes a work unit in the project `project`, or inside the unit `parent`; Edit › Undo takes
    /// it back. Nil when it couldn't be made, with why in `correctionFailure`.
    @discardableResult
    func newUnit(named name: String, in project: String, inside parent: String? = nil) async -> WorkUnit? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard let unit = await correcting({ try $0.addUnit(named: name, in: project, inside: parent, at: Date()) }) else { return nil }
        undoManager?.registerUndo(withTarget: self) { model in Task { await model.unmake(unit) } }
        undoManager?.setActionName("New Collection")
        said("Made \(name)")
        return unit
    }

    /// Takes back making the unit: it goes with what was decided about it.
    func unmake(_ unit: WorkUnit) async {
        let key = unit.key
        await correcting { try $0.removeUnit(key) }
        said("Undone")
    }

    func rename(_ unit: WorkUnit, to name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines), key = unit.key, made = Set(corrections.map(\.id))
        guard !name.isEmpty, name != organization.unitName(key) else { return }
        await correcting { try $0.correct(.unitName, subject: key, target: name, at: Date()) }
        undoable("Rename", since: made)
        said("Renamed \(unit.name) to \(name)")
    }

    /// Deletes the unit and the units inside it: their works go back to the project. Edit › Undo,
    /// or Undo in Sources › Corrections, brings them back as they were.
    func delete(_ unit: WorkUnit) async {
        let key = unit.key, made = Set(corrections.map(\.id))
        await correcting { try $0.correct(.unitDeleted, subject: key, target: "", at: Date()) }
        undoable("Delete", since: made)
        said("Deleted \(unit.name)")
    }

    /// Puts the works, every file of each, in the unit; a work shown in another project is moved
    /// to the unit's with it, as one decision.
    func add(_ works: [Work], to unit: WorkUnit) async {
        let decisions = works.flatMap { work in
            work.files.map { (kind: Correction.Kind.unit, subject: $0.path, target: unit.key) }
                + (work.project == unit.project ? [] : work.files.map { (kind: .project, subject: $0.path, target: unit.project) })
        }
        await decide(decisions, as: "Add to Collection", saying: "Added \(names(works.map(\.name))) to \(unit.name)")
    }

    /// Keeps the observed files and puts them in the unit, as one decision.
    func add(_ candidates: [Candidate], to unit: WorkUnit) async {
        let decisions = candidates.flatMap { candidate in
            [(kind: Correction.Kind.kept, subject: candidate.path, target: candidate.latest.logPath),
             (kind: .unit, subject: candidate.path, target: unit.key)]
                + (candidate.project == unit.project ? [] : [(kind: .project, subject: candidate.path, target: unit.project)])
        }
        await decide(decisions, as: "Add to Collection", saying: "Added \(names(candidates.map(\.name))) to \(unit.name)")
    }

    func remove(_ works: [Work], from unit: WorkUnit) async {
        let decisions = works.flatMap { $0.files.map { (kind: Correction.Kind.outOfUnit, subject: $0.path, target: unit.key) } }
        await decide(decisions, as: "Remove from Collection", saying: "Removed \(names(works.map(\.name))) from \(unit.name)")
    }

    /// Keeps the observed file: a work whose one revision is the file as its latest session saw it.
    func keep(_ candidate: Candidate) async {
        await decide([(.kept, candidate.path, candidate.latest.logPath)], as: "Keep",
                     saying: "Kept \(candidate.name), observed during \(Wording.session(candidate.latest.sessionTitle))")
    }

    /// Records decisions made as one, puts them on Edit › Undo as `name`, and says `text`.
    private func decide(_ decisions: [(kind: Correction.Kind, subject: String, target: String)], as name: String, saying text: String) async {
        guard !decisions.isEmpty else { return }
        let made = Set(corrections.map(\.id))
        await correcting { try $0.correct(decisions, at: Date()) }
        undoable(name, since: made)
        said(text)
    }

    private func names(_ names: [String]) -> String {
        names.count == 1 ? names[0] : Wording.count(names.count, "work")
    }

    /// Makes a verdict or a published mark on each work's current file, on the bytes there now,
    /// read then. `shown` holds each file as the person was shown it, by path: a file no longer so
    /// is left, since they may not have judged those bytes. Edit › Undo takes back all of them.
    @discardableResult
    func review(_ works: [Work], as kind: Review.Kind, note: String? = nil, shown: [String: FileStat] = [:]) async -> [Review] {
        let indexer = indexer, paths = works.map(\.latest.path), date = Date()
        let outcomes = await Task.detached(priority: .userInitiated) {
            paths.map { path in (path, Result { try indexer.review(path, as: kind, note: note, shown: shown[path], at: date) }) }
        }.value
        let made = outcomes.compactMap { try? $0.1.get() }
        reviewFailure = outcomes.lazy.compactMap { path, outcome in
            if case .failure(let error) = outcome { Wording.reviewFailed(error, name: (path as NSString).lastPathComponent) } else { nil }
        }.first
        for review in made { noteRead(review.path, sha256: review.sha256, file: review.file) }
        reviews = Reviews((try? indexer.registry.reviews()) ?? [])
        // The read may have completed a listed capture: its file's revisions are read again.
        for path in Set(made.map(\.path)) { await reread(path) }
        if !made.isEmpty, let undoManager {
            undoManager.registerUndo(withTarget: self) { model in Task { await model.undo(made) } }
            undoManager.setActionName(Wording.reviewAction(kind))
        }
        announce(reviewFailure ?? Wording.reviewed(kind, count: made.count))
        return made
    }

    /// Takes back verdicts and marks; those made before or after them stay.
    func undo(_ reviews: [Review]) async {
        let ids = reviews.map(\.id), indexer = indexer
        let outcome = await Task.detached { Result { try indexer.registry.undoReviews(ids); return try indexer.registry.reviews() } }.value
        switch outcome {
        case .success(let all):
            self.reviews = Reviews(all)
            reviewFailure = nil
            announce("Undone")
        case .failure(let error):
            reviewFailure = "Couldn’t undo that: \(error.localizedDescription)"
        }
    }

    /// What is at the work's current file now, from this session's read of it while the file is
    /// still as read, else its size and dates when the library was organized. Reads nothing.
    func present(_ work: Work) -> Present {
        let path = work.latest.path
        guard let entry = listed[path], let file = entry else { return .absent }
        if let read = reads[path], read.file == file { return .read(read.sha256) }
        return .listed(file)
    }

    /// The Reviewed state of the work's current file.
    func verdict(of work: Work) -> Standing {
        Review.standing(reviews.verdicts(of: work), now: present(work))
    }

    /// The Published state of the work's current file.
    func published(of work: Work) -> Standing {
        Review.standing(reviews.published(of: work), now: present(work))
    }

    /// What waits on the person's review, grouped by unit (`Organization.toReview`).
    var toReview: [Organization.ReviewGroup] {
        organization.toReview(reviews, present: present)
    }

    /// Takes the size and dates of each file a review state is shown for: the current file of each
    /// work in a unit or with a verdict or mark. Metadata only.
    private func statReviewed() {
        listed = [:]
        for work in organization.works where work.unit != nil || reviews.any(work) {
            listed[work.latest.path] = .some(FileStat(work.latest.path))
        }
    }

    /// Records a read of the file at `path` this session: its bytes stand for the file while it is
    /// still as `file`. Without bytes or a file, the read stands for nothing.
    private func noteRead(_ path: String, sha256: String?, file: FileStat?) {
        if let sha256, let file {
            reads[path] = (sha256, file)
            listed[path] = .some(file)
        } else {
            reads[path] = nil
            if listed[path] != nil { listed[path] = .some(FileStat(path)) }
        }
    }

    /// How to go back to the conversation that made `delivery`, checked now.
    func resume(_ delivery: Delivery) -> Resume {
        delivery.resume { path, kind in Locator.stat(path).kind == kind }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Actions shared by buttons, menus and the right-click menu

    /// The last action that failed, with the delivery it was pressed on; nil for one that acts on
    /// the file's location, whichever delivery is shown, which holds until a check finds the file.
    private var actionFailure: (artifact: Artifact.ID, delivery: Delivery.ID?, message: String)?

    /// Why the last Open, Save a Copy or Show Folder on this delivery failed, shown where it was pressed.
    func actionFailure(_ artifact: Artifact, _ delivery: Delivery) -> String? {
        guard let failure = actionFailure, failure.artifact == artifact.id, (failure.delivery ?? delivery.id) == delivery.id else { return nil }
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
        if !isQuickLookOpen, selectedHandoffURL == nil, let (artifact, delivery, _) = selectedHandoff {
            preparingAgain(artifact, delivery)
        }
        isQuickLookOpen = !isQuickLookOpen && selectedHandoffURL != nil
    }

    /// Opens the selection's verified copy (or folder) in its app, or says why it couldn't. A copy
    /// is opened only while it is the file Gleaner hashed (`selectedHandoffURL`).
    func openSelected() {
        guard let (artifact, delivery, _) = selectedHandoff else { return }
        guard let url = selectedHandoffURL else { return preparingAgain(artifact, delivery) }
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

    /// Shows the original in Finder, or the folder it was in when it is gone. When that folder is
    /// gone too, the file's hand-off panel says so, and the file is selected to show it.
    func reveal(_ artifact: Artifact) {
        let source = URL(fileURLWithPath: artifact.path), folder = source.deletingLastPathComponent()
        actionFailure = nil
        if Locator.stat(source.path).kind != .missing {
            NSWorkspace.shared.activateFileViewerSelecting([source])
        } else if Locator.stat(folder.path).kind != .missing {
            NSWorkspace.shared.open(folder)
        } else {
            selection = organization.work(containing: artifact.path)?.id ?? artifact.path
            actionFailure = (artifact.id, nil, Wording.folderGone(folder.path))
        }
    }

    func copyPath(_ artifact: Artifact) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(artifact.path, forType: .string)
    }

    /// What a list row hands over: the version the detail pane would, of the delivery the row
    /// shows (`delivery(in:)`: the chosen one for the selected row, the matched one for any other).
    enum RowHandoff: Equatable {
        case bytes(sha: String)
        /// A delivered folder, as it is now.
        case folder
        /// A file listed with its folder and not read yet: read at the drop, which completes its
        /// listing while the file is still as listed, and handed over only then (SPEC §5.4).
        case unread
    }

    /// What dragging `result`'s row hands over; nil when the library already knows there is
    /// nothing: the delivery's bytes were never read, or the store holds no copy of them and the
    /// file was found gone or changed. Decided from what the library holds and the newest check of
    /// the file, never by reading the disk, so a row can ask while it is drawn. The drop verifies
    /// what it hands over.
    func rowHandoff(_ result: SearchResult) -> RowHandoff? {
        rowHandoff(file(in: result), delivery(in: result))
    }

    /// What dragging a row naming `delivery` of `artifact` hands over, as `rowHandoff(_:)` decides it.
    func rowHandoff(_ artifact: Artifact, _ delivery: Delivery) -> RowHandoff? {
        if let observation = rowObservation(artifact.path) {
            switch artifact.handoff(delivery, now: observation, hasSaved: hasSaved) {
            case .ready(let sha, _, _): return .bytes(sha: sha)
            case .folder: return .folder
            default: return nil
            }
        }
        if delivery.capture?.isDirectory == true { return missing.contains(artifact.path) ? nil : .folder }
        if delivery.capture?.provenance == .listed { return missing.contains(artifact.path) ? nil : .unread }
        guard let sha = delivery.sha256, !missing.contains(artifact.path) || hasSaved(sha) else { return nil }
        return .bytes(sha: sha)
    }

    /// This session's check of `path`, unless the library has loaded since and found otherwise
    /// whether the file is on disk: rows go by the newer of the two.
    private func rowObservation(_ path: String) -> FileObservation? {
        observations[path].flatMap { ($0.state.kind == .missing) == missing.contains(path) ? $0 : nil }
    }

    /// What `result`'s row says beside its date, from what the library holds and the newest check
    /// of the file: rows never read the disk while they are drawn, so "changed" waits for a check.
    func rowStatus(_ result: SearchResult) -> (mark: (Mark, String)?, number: String?) {
        let artifact = file(in: result), now = rowNow(artifact)
        return Wording.row(delivery(in: result), latest: artifact.latest.number, now: now.kind, changed: now.changed,
                           available: rowHandoff(result) != nil)
    }

    /// What an open work's row says: only what is true of its file now, whichever delivery.
    func fileStatus(_ artifact: Artifact) -> (Mark, String)? {
        let now = rowNow(artifact)
        return Wording.fileState(now: now.kind, changed: now.changed)
    }

    /// What a revision's row says: only that it has nothing to hand over, in a few words and in a
    /// sentence. Its endpoint already says whether it was first seen later.
    func revisionStatus(_ artifact: Artifact, _ delivery: Delivery) -> (label: (Mark, String), reason: String)? {
        guard rowHandoff(artifact, delivery) == nil else { return nil }
        let now = rowNow(artifact)
        guard let label = Wording.row(delivery, latest: artifact.latest.number, now: now.kind, changed: now.changed, available: false).mark
        else { return nil }
        return (label, Wording.unavailableReason(delivery, now: now.kind, large: isLarge(delivery)))
    }

    /// What is at `artifact`'s path as far as the library knows without reading the disk (a check
    /// this session, or gone when the library loaded), and whether a check found bytes no delivery had.
    private func rowNow(_ artifact: Artifact) -> (kind: LocatorState.Kind?, changed: Bool) {
        let observation = rowObservation(artifact.path)
        let changed = observation.map { now in
            // No saved copy is asked about: only the missing case would, and it isn't "changed".
            if case .changed = artifact.onDisk(now, hasSaved: { _ in false }) { true } else { false }
        } ?? false
        return (observation?.state.kind ?? (missing.contains(artifact.path) ? .missing : nil), changed)
    }

    /// A drag from a result row, handing over what `rowHandoff` says, or nil when there is
    /// nothing. The receiver gets its own copy, never the original to open in place: a delivery's
    /// bytes staged and verified only when the receiving app asks for them, or a delivered folder
    /// as it is then, so a drop never moves a project's file or folder (SPEC §4).
    func dragItem(for result: SearchResult) -> NSItemProvider? {
        dragItem(file(in: result), delivery(in: result))
    }

    /// A drag from a row naming `delivery` of `artifact`: a revision's row hands over its own bytes.
    func dragItem(_ artifact: Artifact, _ delivery: Delivery) -> NSItemProvider? {
        switch rowHandoff(artifact, delivery) {
        case nil: nil
        case .folder: Self.folderItem(artifact.path)
        case .bytes(let sha): handoffItem(sha: sha, artifact: artifact)
        case .unread: unreadItem(delivery, artifact: artifact)
        }
    }

    /// A file listed with its folder, or kept from an observation, and not read yet, for another app:
    /// read when the receiver asks for it, which completes its listing while the file is still as
    /// listed, then staged and hashed as any version is. A file changed since it was listed isn't
    /// this revision, and the drop fails.
    func unreadItem(_ delivery: Delivery, artifact: Artifact) -> NSItemProvider {
        let indexer = indexer, store = indexer.store, name = artifact.name, source = artifact.path
        let provider = NSItemProvider()
        provider.suggestedName = name
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { done in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    _ = try indexer.completeCaptures(of: source, now: Date())
                    guard let sha = try indexer.registry.sha256(ofListed: delivery) else { throw ContentStore.Failure.unavailable }
                    done(try store.stage(sha: sha, name: name, source: source), false, nil)
                } catch {
                    done(nil, false, error)
                }
                Task { @MainActor [weak self] in await self?.reread(source) }
            }
            return nil
        }
        return provider
    }

    /// The version `sha` of `artifact`'s file for another app, under the file's own name: a
    /// hand-off copy staged and hashed when the receiver asks for it. A copy prepared earlier is
    /// handed over only while it still holds those bytes, else made again from the saved copy or
    /// the original (SPEC §6), however the drag started.
    func handoffItem(sha: String, artifact: Artifact) -> NSItemProvider {
        let store = indexer.store, name = artifact.name, source = artifact.path
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

    /// What ⌘C puts on the clipboard: the selection's hand-off copy as a file, while it is the file
    /// Gleaner hashed (`isPreparedIntact`), or a delivered folder as it is. A copy changed since is
    /// prepared again first, and nothing is copied meanwhile.
    func copyItem() -> NSItemProvider? {
        guard let (artifact, delivery, plan) = selectedHandoff else { return nil }
        if plan == .folder { return NSItemProvider(contentsOf: URL(fileURLWithPath: artifact.path)) }
        guard case .ready(let url, _) = staging(for: plan.sha) else {
            preparingAgain(artifact, delivery)
            return nil
        }
        return NSItemProvider(contentsOf: url)
    }

    /// What dragging the detail's tile hands over, decided when the drag starts: the copy as a file
    /// while it is the one Gleaner hashed, else the version's bytes staged and hashed when the
    /// receiver asks for them (`handoffItem`), with the copy prepared again meanwhile.
    func tileItem(_ plan: Handoff, artifact: Artifact) -> NSItemProvider {
        if plan == .folder { return Self.folderItem(artifact.path) }
        // The delivery's bytes, or the current file the person chose to hand over instead.
        guard let sha = plan.sha else { return NSItemProvider() }
        if case .ready(let url, _) = staging(for: sha) { return NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        prepareAgain()
        return handoffItem(sha: sha, artifact: artifact)
    }

    /// True when the selection has something to open, look at or copy now, or a copy that changed
    /// and is prepared again when asked: menus and keys stay on for it, and say why it waits.
    var canHandOver: Bool {
        if selectedHandoffURL != nil { return true }
        if case .ready = staging, selectedHandoff != nil { return true }
        return false
    }

    /// When the copy shown as ready was changed outside Gleaner: prepares it again, and says so where
    /// the person asked for it, since the action they pressed did nothing.
    private func preparingAgain(_ artifact: Artifact, _ delivery: Delivery) {
        guard case .ready = staging, !isPreparedIntact else { return }
        prepareAgain()
        actionFailure = (artifact.id, delivery.id, Wording.preparedCopyChanged)
    }

    /// False when the copy shown as ready is no longer the file Gleaner hashed: another app replaced,
    /// removed or wrote to it. Checked by its inode, so asking costs no read of its bytes.
    var isPreparedIntact: Bool {
        guard case .ready(_, let sha) = staging, let prepared, prepared.sha == sha else { return true }
        return indexer.store.isIntact(prepared)
    }

    /// Prepares the selection's copy again, from its saved copy or the original, when the one shown
    /// as ready was changed outside Gleaner.
    func prepareAgain() {
        guard !isPreparedIntact else { return }
        restage()
    }

    /// A delivered folder for a drag, as it is when the receiving app asks for it, and only while
    /// it is still a folder. The receiver gets a copy (no open-in-place), so a drop never moves it.
    static func folderItem(_ path: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = (path as NSString).lastPathComponent
        provider.registerFileRepresentation(forTypeIdentifier: UTType.folder.identifier, fileOptions: [], visibility: .all) { done in
            if Locator.stat(path).kind == .directory {
                done(URL(fileURLWithPath: path, isDirectory: true), false, nil)
            } else {
                done(nil, false, CocoaError(.fileNoSuchFile))
            }
            return nil
        }
        return provider
    }

    /// Bytes Gleaner keeps: saved copies, and disposable hand-off copies.
    nonisolated func storageUsage() -> (saved: Int64, handoff: Int64) {
        (Self.size(of: indexer.store.objects), Self.size(of: indexer.store.staging))
    }

    /// Removes the hand-off copies, but not one on `pasteboard`: ⌘C put it there as a file, and a
    /// paste reads it later. The selection's copy is prepared again.
    func clearHandoffCopies(keeping pasteboard: NSPasteboard) {
        let copied = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        try? indexer.store.clearStaging(keeping: copied)
        restage()
    }

    /// Drops what is staged and starts a new generation: the detail view prepares the selection's
    /// copy again, and a preparation started before is never shown after.
    private func restage() {
        clearStaging()
        stagingGeneration += 1
    }

    /// Check Again, wherever the app advises it: checks the file now, then prepares its copy again
    /// as clearing hand-off copies does. Both land together, so the copy is prepared once, for what
    /// the check found.
    func checkAgain(_ artifact: Artifact) async {
        await observe(artifact)
        restage()
    }

    nonisolated private static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        return files.reduce(Int64(0)) { total, item in
            total + Int64((try? (item as? URL)?.resourceValues(forKeys: Set(keys)).totalFileAllocatedSize) ?? 0)
        }
    }

    /// The text the preview shows for the version `sha`, when its copy is ready and is text.
    func preparedText(for sha: String?) -> (text: String, truncated: Bool)? {
        guard let sha, case .ready(_, sha) = staging, let prepared = preparedText, prepared.sha == sha else { return nil }
        return (prepared.text, prepared.truncated)
    }

    /// The hand-off state for the version `sha`; idle when what is staged belongs to another one,
    /// and preparing while a copy shown as ready is no longer the file hashed (`prepareAgain`).
    func staging(for sha: String?) -> Staging {
        guard let sha, staging.sha == sha else { return .idle }
        if case .ready = staging, !isPreparedIntact { return .preparing(sha: sha) }
        return staging
    }

    func clearStaging() {
        staging = .idle
        prepared = nil
    }

    /// Checks the file now (hash and git), and which of its versions the store holds, off the main
    /// thread. When it is Gleaner's first read of a file whose bytes a delivery never had, that
    /// file's deliveries are read again with them.
    func observe(_ artifact: Artifact) async {
        let path = artifact.path, checkout = artifact.checkout, versions = Set(artifact.deliveries.compactMap(\.sha256))
        let indexer = indexer
        let (state, held, completed, file) = await Task.detached(priority: .userInitiated) {
            let before = FileStat(path), state = Locator.observe(path, checkout: checkout), held = versions.filter(indexer.store.has)
            let file = FileStat(path)
            let completed = (try? indexer.completeCaptures(of: path, now: Date())) == true
            return (state, held, completed ? try? indexer.registry.artifact(at: path) : nil, before == file ? file : nil)
        }.value
        observations[path] = FileObservation(state: state, checkedAt: Date())
        noteRead(path, sha256: state.kind == .file ? state.sha256 : nil, file: file)
        saved.subtract(versions)
        saved.formUnion(held)
        if let completed { replace(completed) }
        // Whether a file is gone decides which joins Gleaner suggests.
        let goneChanged = (state.kind == .missing) != missing.contains(path)
        if state.kind == .missing {
            missing.insert(path)
        } else {
            missing.remove(path)
            // The file is there, so its folder is too.
            if let failure = actionFailure, failure.artifact == artifact.id, failure.delivery == nil { actionFailure = nil }
        }
        if goneChanged { reorganize() }
    }

    /// Prepares a verified, immutable copy of `sha` to drag. A copy already prepared for these
    /// bytes stays shown while it is checked again, so Quick Look stays on it.
    func stage(sha: String, artifact: Artifact) async {
        let generation = stagingGeneration
        switch staging {
        case .ready(_, sha: sha) where isPreparedIntact: break
        default: staging = .preparing(sha: sha)
        }
        let store = indexer.store
        let name = artifact.name
        let source = artifact.path
        let result = await Task.detached(priority: .userInitiated) {
            Swift.Result { () throws -> (ContentStore.Prepared, (text: String, truncated: Bool)?) in
                let prepared = try store.prepare(sha: sha, name: name, source: source)
                return (prepared, TextPreview.load(prepared.url))
            }
        }.value
        // The selection moved on, another version is being prepared, or the copies were cleared:
        // this result is stale.
        guard !Task.isCancelled, generation == stagingGeneration, staging.sha == sha else { return }
        switch result {
        case .success(let (prepared, text)):
            self.prepared = prepared
            staging = .ready(prepared.url, sha: sha)
            preparedText = text.map { (sha, $0.text, $0.truncated) }
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
        case .success: await reread(artifact.path)
        case .failure(let error): actionFailure = (artifact.id, delivery.id, Wording.saveFailed(error, delivery: delivery))
        }
        await observe(artifact)
    }
}
