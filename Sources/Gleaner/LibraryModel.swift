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

/// A row of a list: a work, one of its revisions (a delivery) listed under it, or a collection,
/// whose review page the detail shows.
enum OutlineRow: Hashable {
    case work(Work.ID)
    case revision(Work.ID, Delivery.ID)
    case unit(String)

    /// The work it names; nil for a collection.
    var work: Work.ID? {
        switch self {
        case .work(let id), .revision(let id, _): id
        case .unit: nil
        }
    }
}

/// A row under a folder's heading in a project's outline: a work, or the works of one kind that no
/// reply named itself, folded into one row when there are many (`Listing.rows`).
enum FolderItem: Identifiable {
    case work(SearchResult)
    case folded(key: String, kind: Artifact.Kind, results: [SearchResult])

    /// The works the row lists: its own, or those folded into it.
    var works: [Work] {
        switch self {
        case .work(let result): [result.work]
        case .folded(_, _, let results): results.map(\.work)
        }
    }

    var id: String {
        switch self {
        case .work(let result): result.id
        case .folded(let key, _, _): "folded\n" + key
        }
    }
}

/// Where the library window is: every delivery, what waits on the person's review, one project,
/// one collection, or what Gleaner reads and keeps.
enum Place: Hashable {
    case all
    case toReview
    case project(String)
    /// A collection (a work unit), by its key: its works and the collections inside it.
    case unit(String)
    case sources
}

/// A collection being named in place in the sidebar: a new one, in a project or inside another
/// collection, to hold the works or observed files at `adding` once named; or one being renamed.
enum Naming: Equatable {
    /// `command` names the command that asked, for Edit › Undo.
    case new(project: String, parent: String?, adding: [String], command: String = "New Collection")
    case rename(String)
}

/// Verdicts or marks the person asked for together that weren't all made: how many were, and each
/// file refused with why, said where they were asked for.
struct ReviewRefusal: Equatable {
    struct Refused: Equatable {
        var path: String
        var reason: String
    }

    /// Where they were asked for: a collection's key, for its review page, or a work's id, for its
    /// detail.
    var place: String?
    var kind: Review.Kind
    var made: Int
    /// In the order asked.
    var refused: [Refused]

    /// Why the file at `path` was refused, if it was.
    func reason(_ path: String) -> String? { refused.first { $0.path == path }?.reason }
}

/// A session's files observed in a project and handed over in none, newest first: what a project's
/// Observed section lists under the session (docs/design/review.md, Keeping an observed file).
struct ObservedSession: Identifiable {
    var logPath: String
    var candidates: [Candidate]
    /// Its rows, as `Listing` lays them out.
    var items: [ObservedItem]

    init(logPath: String, candidates: [Candidate]) {
        self.logPath = logPath
        self.candidates = candidates
        items = ObservedItem.items(candidates)
    }

    var id: String { logPath }
    /// The session as its newest observation names it.
    var title: String? { candidates[0].latest.sessionTitle }
    var provider: Provider { candidates[0].latest.provider }
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
    private(set) var reviews = Reviews([]) {
        didSet { reviewsVersion += 1 }
    }
    /// Why the last correction couldn't be recorded.
    private(set) var correctionFailure: String?
    /// The verdicts or marks last asked for that weren't all made, said where they were asked for
    /// until the person goes elsewhere, looks again or decides again.
    private(set) var reviewRefusal: ReviewRefusal?
    /// The size, dates and inode of each file a review state is shown for (the current file of each
    /// work in a unit or with a verdict or mark), nil when no regular file is there: taken with each
    /// organization, never by reading bytes, so the review states never touch the disk while they
    /// are drawn.
    private var listed: [String: FileStat?] = [:] { didSet { reviewsVersion += 1 } }
    /// The bytes read of a file this session, on select or for a verdict, with the file as it was
    /// then: they stand for the file while it is still so. A read of a file no review state is
    /// shown for leaves the queue as it was (`noteRead`).
    private var reads: [String: (sha256: String, file: FileStat)] = [:]
    /// What Gleaner last saw this session of each file a review state is shown for, and when: its
    /// bytes, read, or its size, dates and inode. Once the file is gone, this decides, unless the
    /// work's newest delivery was recorded since: a file seen changed and then deleted stays
    /// changed, never back to the verdict made before (A16). A relaunch starts without it.
    private var seen: [String: (now: Present, at: Date)] = [:]
    /// What is at each of those paths when no regular file Gleaner can read is: gone, a folder, not
    /// a regular file or unreadable, taken with `listed`, from the file's metadata.
    private var absent: [String: LocatorState.Kind] = [:]
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
        didSet {
            guard place != oldValue else { return }
            if case .project = place { kind = nil }
            alsoSelected = []
            reviewRefusal = nil
            // A collection opens on its review page; elsewhere no collection's page is shown.
            if case .unit(let key) = place {
                selection = nil
                shownUnit = key
            } else {
                shownUnit = nil
            }
        }
    }
    var sourcePage: SourcePage = .agent(.claudeCode)
    /// The work shown: its id, or any of its files' paths.
    var selection: Work.ID? {
        didSet {
            if selection != oldValue { chosenDelivery = nil; comparison = nil; alsoSelected = []; reviewRefusal = nil }
            if selection != nil { shownUnit = nil }
        }
    }
    /// The collection whose review page the detail shows, when its row is chosen rather than a work.
    var shownUnit: String?
    /// The rows chosen with the selected one (⌘-click, ⇧-click), for decisions on several works at
    /// once; the detail then says how many.
    var alsoSelected: Set<OutlineRow> = []
    /// A collection being named in place in the sidebar.
    var naming: Naming?
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

    /// The library in its standard places (`LibraryFolders`), where the `gleaner` command reads it.
    /// Launched with `-GleanerHome <folder>`, the app takes that folder for the home directory, so an
    /// acceptance run on synthetic logs never touches the person's own library or agent history.
    convenience init() throws {
        let home = UserDefaults.standard.string(forKey: "GleanerHome").map { URL(fileURLWithPath: $0, isDirectory: true) }
        // A session working in the home folder has no workspace walked, the synthetic one included.
        let indexer = try Indexer(folders: LibraryFolders(home: home))
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
        artifacts = Artifact.shown(library, without: sourcesOff)
        siblings = Artifact.deliveredWith(artifacts)
        missing = Artifact.missing(artifacts)
        saved = Self.saved(artifacts, in: indexer.store).union(reviews.hashes.filter(indexer.store.has))
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
        guard let shown = Artifact.shown([artifact], without: sourcesOff).first,
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
        organization = Organization(artifacts: artifacts, observed: Candidate.shown(observed, without: sourcesOff), corrections: corrections,
                                    projects: userProjects, units: units, missing: missing)
        organizationVersion += 1
        statReviewed()
        if indexed { updateStatus() }
        // A collection deleted, or taken back, while shown: its project is shown instead.
        if case .unit(let key) = place, organization.unit(key) == nil {
            let project = units.first { $0.key == key }.flatMap { organization.project($0.project) }
            place = project.map { .project($0.key) } ?? .all
        }
        if let shown = shownUnit, organization.unit(shown) == nil { shownUnit = nil }
    }

    /// The subtitle: what the library holds, as organized now.
    private func updateStatus() {
        status = Wording.library(works: organization.works.count, deliveries: artifacts.map(\.deliveries.count).reduce(0, +))
    }

    /// Bumped with each organization rebuilt or changed in a way that moves what lists or groups a
    /// work, so a listing made before is never reused after.
    @ObservationIgnored private(set) var organizationVersion = 0

    /// Only what is shown to be gone: a file Gleaner can't reach is unreadable, not missing.
    /// The store is shared by content: a copy saved for one file serves every file with its bytes,
    /// and the bytes a verdict was made on.
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
        switch place {
        case .sources: place = .all
        case .project, .unit, .toReview: if !holds(place, work) { place = .project(work.project) }
        case .all: break
        }
        if !results.contains(where: { $0.id == work.id }) { clearFilters() }
        selection = work.id
        chosenDelivery = delivery.id
    }

    /// Why the last `gleaner://` link showed nothing, until the person dismisses it.
    var linkFailure: String?

    /// The delivery id a `gleaner://delivery/<id>` link names; nil for any other URL, and for one
    /// whose id isn't shaped as Gleaner makes them, so words a link carries are never shown as Gleaner's.
    static func deliveryID(in link: URL) -> String? {
        guard link.scheme?.lowercased() == "gleaner", link.host()?.lowercased() == "delivery",
              link.pathComponents.count == 2, Delivery.isID(link.pathComponents[1]) else { return nil }
        return link.pathComponents[1]
    }

    /// Opens a `gleaner://delivery/<id>` link, as an extension or another tool sends it: shows that
    /// delivery as `select` does, or says why it can't, naming the agent when it is turned off.
    func open(_ link: URL) {
        guard let id = Self.deliveryID(in: link) else { linkFailure = Wording.notADeliveryLink(link); return }
        guard let delivery = artifacts.lazy.flatMap(\.deliveries).first(where: { $0.id == id }) else {
            let hidden = library.lazy.flatMap(\.deliveries).first { $0.id == id }
            linkFailure = hidden.map { Wording.deliveryOff($0.provider) } ?? Wording.noDelivery(id)
            return
        }
        linkFailure = nil
        select(delivery)
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

    var tokens: [String] { Search.tokens(query) }

    /// The works the window lists, newest first: in the project shown, of the kind chosen, matching the search.
    var results: [SearchResult] {
        let tokens = tokens
        let key = resultsKey
        if let cached = resultsCache, cached.key == key { return cached.results }
        // To Review's works are what it holds: the queue is worked out once, not once for each.
        let results = place == .toReview
            ? toReview.flatMap(\.works).compactMap { result(for: $0, tokens: tokens, anywhere: true) }
            : organization.search(tokens, kind: kind) { holds(place, $0) }.map { SearchResult(work: $0.work, matched: $0.matched) }
        resultsCache = (key, results)
        return results
    }

    /// What the list depends on: it is listed again only when one of these changes, not each time
    /// a view asks for it. To Review also follows the verdicts, and what is known of each file.
    private struct ResultsKey: Equatable {
        var tokens: [String], kind: Artifact.Kind?, place: Place, organization: Int, reviews: Int
    }

    private var resultsKey: ResultsKey {
        ResultsKey(tokens: tokens, kind: kind, place: place, organization: organizationVersion,
                   reviews: place == .toReview ? reviewsVersion : 0)
    }

    /// Bumped with each change to the verdicts and marks, or to what is known of a reviewed file
    /// (its size and dates, or a read of it), so To Review is listed again.
    @ObservationIgnored private(set) var reviewsVersion = 0
    @ObservationIgnored private var resultsCache: (key: ResultsKey, results: [SearchResult])?

    /// The work as the list shows it, or nil when the place, kind or search leaves it out.
    func result(for work: Work) -> SearchResult? { result(for: work, tokens: tokens) }

    private func result(for work: Work, tokens: [String], anywhere: Bool = false) -> SearchResult? {
        guard anywhere || holds(place, work), kind == nil || work.kind == kind,
              let matched = organization.match(work, tokens) else { return nil }
        return SearchResult(work: work, matched: matched)
    }

    /// The selected work, as the list shows it: looked up, not found by listing every work, since
    /// the detail asks for it many times each time it is drawn.
    var selected: SearchResult? {
        // The Sources page hides the selection: menus and Quick Look don't act on what isn't shown.
        guard place != .sources, let selection, let work = organization.work(containing: selection) else { return nil }
        // A work reviewed in To Review stays shown, as Mail keeps a message read in Unread.
        return result(for: work, tokens: tokens, anywhere: place == .toReview)
    }

    /// Whether the place lists the work: a project its own, a collection its works and those of the
    /// collections inside it, To Review what waits on the person.
    func holds(_ place: Place, _ work: Work) -> Bool {
        switch place {
        case .all, .sources: true
        case .project(let key): work.project == key
        case .unit(let key): work.unit.map { $0 == key || organization.unit($0)?.parent == key } ?? false
        case .toReview: toReview.contains { $0.works.contains { $0.id == work.id } }
        }
    }

    /// The delivery the detail pane shows.
    var selectedDelivery: Delivery? { selected.map(delivery(in:)) }

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

    /// The selected row: the revision shown, while its work is open; otherwise the work; with no
    /// work, the collection whose page is shown. Choosing a row shows what it names, as choosing a
    /// delivery under Versions does; choosing the row already selected changes nothing.
    var outlineSelection: OutlineRow? {
        get {
            guard let selection else { return shownUnit.map(OutlineRow.unit) }
            guard let work = organization.work(containing: selection) else { return .work(selection) }
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
                shownUnit = nil
            case .work(let id):
                selection = id
                chosenDelivery = nil
            case .revision(let id, let delivery):
                selection = id
                chosenDelivery = delivery
            case .unit(let key):
                selection = nil
                shownUnit = key
            }
        }
    }

    /// Every row chosen: the selected one, and those chosen with it. Choosing several keeps the
    /// one shown while it stays chosen, else shows one just added.
    var selectedRows: Set<OutlineRow> {
        get { outlineSelection.map { alsoSelected.union([$0]) } ?? alsoSelected }
        set {
            let shown = outlineSelection.flatMap { newValue.contains($0) ? $0 : nil }
                ?? newValue.subtracting(selectedRows).first ?? newValue.first
            outlineSelection = shown
            alsoSelected = newValue.subtracting(shown.map { [$0] } ?? [])
        }
    }

    /// The works the chosen rows name, the shown one first, each once.
    var selectedWorks: [Work] {
        let rows = (outlineSelection.map { [$0] } ?? []) + alsoSelected.filter { $0 != outlineSelection }
        var seen = Set<Work.ID>(), works: [Work] = []
        for row in rows {
            guard let id = row.work, let work = organization.work(containing: id), seen.insert(work.id).inserted else { continue }
            works.append(work)
        }
        return works
    }

    /// A project's outline below its head: each folder its works are in (`outlineFolder`), in the
    /// project's own layout, with how many works it holds and its rows (`outlineItems`). Made again
    /// only when what the window lists changes, not each time the outline is drawn.
    func outline(of project: Organization.Project) -> [(folder: String, count: Int, items: [FolderItem])] {
        let key = resultsKey
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
        guard let id = row.work, let work = organization.work(containing: id) else { return nil }
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

    /// Undoes decisions made together, such as moving every file of a work. Undoing a keep takes
    /// back with it what was decided since about the file, while it is a work only because it was
    /// kept: its collection and project would otherwise stay listed with nothing to act on, and
    /// come back with the next keep. With `following`, the window follows the selected work to
    /// where it now is.
    func undo(_ corrections: [Correction], following: Bool = true) async {
        let ids = (corrections + decidedSince(keeping: corrections)).map(\.id), before = (place, selection)
        await correcting { try $0.undo(ids) }
        if following, let selected = before.1 { follow(selected, from: before) }
        said("Undone")
    }

    /// The decisions about each file kept in `corrections` made after it was kept, while no reply
    /// handed the file over: its collection and its project.
    private func decidedSince(keeping corrections: [Correction]) -> [Correction] {
        let undone = Set(corrections.map(\.id))
        return corrections.filter { $0.kind == .kept }.flatMap { keep -> [Correction] in
            guard let file = organization.work(containing: keep.subject)?.files.first(where: { $0.path == keep.subject }),
                  file.deliveries.allSatisfy({ $0.kept != nil }) else { return [] }
            return self.corrections.filter {
                [.unit, .outOfUnit, .project].contains($0.kind) && $0.subject == keep.subject && !undone.contains($0.id)
                    && ($0.madeAt, $0.id) > (keep.madeAt, keep.id)
            }
        }
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

    /// Removes a project the person made: each of its works goes back to the project it was in
    /// before it was moved there, the moves into it being taken back.
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
    /// file named, then the others. Observed files kept to go in a collection are said once, as
    /// kept and added, with the sessions they were observed during.
    func describe(_ group: [Correction]) -> String {
        guard group.count > 1 else { return group.first.map(describe) ?? "" }
        var ordered = group.sorted { $0.id < $1.id }
        var parts: [String] = [], said = Set<String>()
        let name = { (c: Correction) in (c.subject as NSString).lastPathComponent }
        let kept = ordered.filter { $0.kind == .kept }, added = ordered.filter { $0.kind == .unit }
        if !kept.isEmpty, let unit = added.first?.target, added.allSatisfy({ $0.target == unit }),
           Set(kept.map(\.subject)).isSubset(of: added.map(\.subject)) {
            var sessions: [String] = []
            for c in kept where !sessions.contains(sessionName(c.target)) { sessions.append(sessionName(c.target)) }
            parts.append("Kept and added \(added.map(name).joined(separator: ", ")) to \(organization.unitName(unit)), "
                         + "observed during \(sessions.joined(separator: " and "))")
            ordered.removeAll { $0.kind == .kept || $0.kind == .unit }
        }
        for c in ordered where said.insert(c.kind.rawValue + "\n" + c.target).inserted {
            let same = ordered.filter { $0.kind == c.kind && $0.target == c.target }
            let names = same.map(name).joined(separator: ", ")
            switch c.kind {
            case .project: parts.append("Moved \(names) to \(organization.projectName(c.target))")
            case .kept: parts.append("Kept \(names), observed during \(sessionName(c.target))")
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

    /// A unit made to hold works and observed files, for chosen rows or from a group the window
    /// shows (docs/design/review.md, New Collection from These): it holds exactly `works` and
    /// `candidates`, kept as adding keeps them, as one decision; a work in another unit leaves it,
    /// since a work is in one at most. Edit › Undo takes back the making and the adding together,
    /// under `command`, the name of the command that asked; the result is said in the words
    /// Corrections lists it by, with what it took out of other units.
    @discardableResult
    func newUnit(named name: String, in project: String, inside parent: String? = nil, holding works: [Work],
                 _ candidates: [Candidate] = [], as command: String = "New Collection") async -> WorkUnit? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines), before = Set(corrections.map(\.id))
        guard !name.isEmpty else { return nil }
        let out = Wording.takenOut(unitsHolding(works), of: works.count + candidates.count)
        guard let unit = await correcting({ try $0.addUnit(named: name, in: project, inside: parent, at: Date()) }) else { return nil }
        let decisions = decisions(adding: works, candidates, to: unit)
        if !decisions.isEmpty { await correcting { try $0.correct(decisions, at: Date()) } }
        let made = corrections.filter { !before.contains($0.id) }
        undoManager?.registerUndo(withTarget: self) { model in Task { await model.unmake(unit, with: made) } }
        undoManager?.setActionName(command)
        said([made.isEmpty ? "Made \(name)" : describe(made), out.map { "Took \($0)" }].compactMap { $0 }.joined(separator: ". "))
        return unit
    }

    /// The units holding any of `works`, by name, with how many of them each holds, in their order:
    /// what a unit made of them takes them out of.
    func unitsHolding(_ works: [Work]) -> [(name: String, count: Int)] {
        var order: [String] = [], counts: [String: Int] = [:]
        for key in works.compactMap(\.unit) {
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        return order.map { (organization.unitName($0), counts[$0]!) }
    }

    /// Takes back making the unit: it goes with what was decided about it, and with `made`, the
    /// decisions made with it: the observed files it kept are candidates again, and works it brought
    /// from another project go back there.
    func unmake(_ unit: WorkUnit, with made: [Correction] = []) async {
        let key = unit.key, ids = made.map(\.id)
        await correcting { registry in
            try registry.undo(ids)
            try registry.removeUnit(key)
        }
        said("Undone")
    }

    /// The project works and observed files share, where a collection of exactly them is made; nil
    /// when they are in several, since a collection holds one project's works, and adding the others
    /// would move them.
    func project(of works: [Work], _ candidates: [Candidate] = []) -> String? {
        let projects = Set(works.map(\.project) + candidates.map(\.project))
        return projects.count == 1 ? projects.first : nil
    }

    /// New Collection from These, for a group the window shows (a folder, a session's observed
    /// files, a folded row, files shown together, what a reply delivered together, what a search
    /// found): names a new collection in place, in their project or inside `parent`, to hold exactly
    /// them once named. Nothing is inferred: the group is the person's choice.
    func newCollection(from works: [Work], _ candidates: [Candidate] = [], inside parent: String? = nil) {
        guard let project = project(of: works, candidates) else { return }
        startNewUnit(in: project, inside: parent, adding: works.map(\.id) + candidates.map(\.path), as: "New Collection from These")
    }

    func rename(_ unit: WorkUnit, to name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines), key = unit.key, made = Set(corrections.map(\.id))
        guard !name.isEmpty, name != organization.unitName(key) else { return }
        await correcting { try $0.correct(.unitName, subject: key, target: name, at: Date()) }
        undoable("Rename Collection", since: made)
        said("Renamed \(unit.name) to \(name)")
    }

    /// Deletes the unit and the units inside it: their works go back to the project. Edit › Undo,
    /// or Undo in Sources › Corrections, brings them back as they were.
    func delete(_ unit: WorkUnit) async {
        let key = unit.key, made = Set(corrections.map(\.id))
        await correcting { try $0.correct(.unitDeleted, subject: key, target: "", at: Date()) }
        undoable("Delete Collection", since: made)
        said("Deleted \(unit.name)")
    }

    /// Puts the works, every file of each, in the unit; a work shown in another project is moved
    /// to the unit's with it, as one decision. A work already in it stays as it is: nothing is
    /// decided again.
    func add(_ works: [Work], to unit: WorkUnit) async {
        let works = works.filter { $0.unit != unit.key }
        // A work is in one collection at most: one in another is taken out of it, and said so.
        let out = Wording.takenOut(unitsHolding(works), of: works.count)
        await decide(decisions(adding: works, [], to: unit), as: Wording.collectionCommand(works),
                     saying: ["\(out == nil ? "Added" : "Moved") \(names(works.map(\.name))) to \(unit.name)", out.map { "Took \($0)" }]
                        .compactMap { $0 }.joined(separator: ". "))
    }

    /// The newest revision of the work whose bytes Gleaner keeps a saved copy of: what can still be
    /// read when no file is at its path. Nil when it keeps none.
    func savedVersion(of work: Work) -> Delivery? {
        work.deliveries.first { $0.sha256.map(hasSaved) == true }
    }

    /// Keeps the observed files and puts them in the unit, as one decision.
    func add(_ candidates: [Candidate], to unit: WorkUnit) async {
        await decide(decisions(adding: [], candidates, to: unit), as: "Add to Collection",
                     saying: "Kept and added \(names(candidates.map(\.name), "file")) to \(unit.name)")
    }

    /// The decisions that put works, every file of each, and observed files, kept, in the unit; a
    /// work or file shown in another project moves to the unit's with them. A work already in it is
    /// left as it is.
    private func decisions(adding works: [Work], _ candidates: [Candidate], to unit: WorkUnit)
        -> [(kind: Correction.Kind, subject: String, target: String)] {
        works.filter { $0.unit != unit.key }.flatMap { work in
            work.files.map { (kind: Correction.Kind.unit, subject: $0.path, target: unit.key) }
                + (work.project == unit.project ? [] : work.files.map { (kind: .project, subject: $0.path, target: unit.project) })
        } + candidates.flatMap { candidate in
            [(kind: Correction.Kind.kept, subject: candidate.path, target: candidate.latest.logPath),
             (kind: .unit, subject: candidate.path, target: unit.key)]
                + (candidate.project == unit.project ? [] : [(kind: .project, subject: candidate.path, target: unit.project)])
        }
    }

    /// Takes the works out of the units they are in, one or several, as one decision.
    func remove(_ works: [Work]) async {
        let works = works.filter { $0.unit != nil }
        let units = Set(works.compactMap(\.unit))
        guard let unit = units.first else { return }
        let decisions = works.flatMap { work in work.files.map { (kind: Correction.Kind.outOfUnit, subject: $0.path, target: work.unit!) } }
        let from = units.count == 1 ? organization.unitName(unit) : Wording.count(units.count, "collection")
        await decide(decisions, as: "Remove from Collection", saying: "Removed \(names(works.map(\.name))) from \(from)")
    }

    /// Keeps the observed files, as one decision: each a work whose one revision is the file as its
    /// latest session saw it.
    func keep(_ candidates: [Candidate]) async {
        guard let first = candidates.first else { return }
        let text = candidates.count == 1
            ? "Kept \(first.name), observed during \(Wording.session(first.latest.sessionTitle))"
            : "Kept \(Wording.count(candidates.count, "file"))"
        await decide(candidates.map { (.kept, $0.path, $0.latest.logPath) }, as: "Keep", saying: text)
    }

    /// Records decisions made as one, puts them on Edit › Undo as `name`, and says `text`.
    private func decide(_ decisions: [(kind: Correction.Kind, subject: String, target: String)], as name: String, saying text: String) async {
        guard !decisions.isEmpty else { return }
        let made = Set(corrections.map(\.id))
        await correcting { try $0.correct(decisions, at: Date()) }
        undoable(name, since: made)
        said(text)
    }

    private func names(_ names: [String], _ noun: String = "work") -> String {
        names.count == 1 ? names[0] : Wording.count(names.count, noun)
    }

    /// Makes a verdict or a published mark on each work's current file, on the bytes there now,
    /// read then. `shown` holds each file as the person was shown it, by path: a file no longer so
    /// is left, since they may not have judged those bytes. With `save`, the bytes each was made on
    /// are then kept as Save a Copy keeps them, checked by hash; a copy that couldn't be saved is
    /// said with the result, and its Not kept label says why (`unsaved`). Edit › Undo takes back
    /// all of them. Those refused are said `from` where the person asked: a collection's key, or a
    /// work's id.
    @discardableResult
    func review(_ works: [Work], as kind: Review.Kind, note: String? = nil, shown: [String: FileStat] = [:], save: Bool = false,
                from place: String? = nil) async -> [Review] {
        let indexer = indexer, paths = works.map(\.latest.path), date = Date()
        let (outcomes, held, failed) = await Task.detached(priority: .userInitiated) {
            var failed: [(Review, any Error)] = []
            let outcomes = paths.map { path in
                let outcome = Result { try indexer.review(path, as: kind, note: note, shown: shown[path], at: date) }
                if save, case .success(let review) = outcome, !indexer.store.has(review.sha256) {
                    do { try indexer.saveCopy(of: review) } catch { failed.append((review, error)) }
                }
                return (path, outcome)
            }
            return (outcomes, Set(outcomes.compactMap { try? $0.1.get().sha256 }.filter(indexer.store.has)), failed)
        }.value
        saved.formUnion(held)
        for (review, error) in failed { unsaved[review.sha256] = error }
        let made = outcomes.compactMap { try? $0.1.get() }
        let refused = outcomes.compactMap { path, outcome -> ReviewRefusal.Refused? in
            guard case .failure(let error) = outcome else { return nil }
            return .init(path: path, reason: Wording.reviewFailed(error, name: (path as NSString).lastPathComponent))
        }
        reviewRefusal = refused.isEmpty ? nil : ReviewRefusal(place: place, kind: kind, made: made.count, refused: refused)
        for review in made { noteRead(review.path, sha256: review.sha256, file: review.file, judged: true) }
        reviews = Reviews((try? indexer.registry.reviews()) ?? [])
        // The read may have completed a listed capture: its file's revisions are read again.
        for path in Set(made.map(\.path)) { await reread(path) }
        if !made.isEmpty, let undoManager {
            undoManager.registerUndo(withTarget: self) { model in Task { await model.undo(made) } }
            undoManager.setActionName(Wording.reviewAction(kind))
        }
        // What was recorded and what wasn't, both, and any copy asked for that couldn't be saved.
        let result = reviewRefusal.map { Wording.refusal($0).title + ". " + Wording.refusal($0).detail } ?? Wording.reviewed(kind, count: made.count)
        let failures = failed.map { Wording.copyFailed($1, name: ($0.path as NSString).lastPathComponent) }
        announce(failures.isEmpty ? result : ([result.hasSuffix(".") ? result : result + "."] + failures).joined(separator: " "))
        return made
    }

    /// Clears what was refused, once the person looks again.
    func lookAgain() {
        reviewRefusal = nil
    }

    /// Takes back verdicts and marks; those made before or after them stay.
    func undo(_ reviews: [Review]) async {
        let ids = reviews.map(\.id), indexer = indexer
        let outcome = await Task.detached { Result { try indexer.registry.undoReviews(ids); return try indexer.registry.reviews() } }.value
        switch outcome {
        case .success(let all):
            self.reviews = Reviews(all)
            reviewRefusal = nil
            announce("Undone")
        case .failure(let error):
            correctionFailure = "Couldn’t undo that: \(error.localizedDescription)"
        }
    }

    /// What is at the work's current file now, from this session's read of it while the file is
    /// still as read, else its size and dates when the library was organized. Reads nothing.
    func present(_ work: Work) -> Present {
        let path = work.latest.path
        guard let entry = listed[path], let file = entry else { return absent(work) }
        if let read = reads[path], read.file == file { return .read(read.sha256) }
        return .listed(file)
    }

    /// No regular file Gleaner can read is at the work's current file: what Gleaner last saw of it
    /// this session decides as a delivery's recorded bytes do (`seen`), unless Gleaner recorded the
    /// work's newest delivery since. Bytes read decide by their hash; a size and dates by the bytes
    /// recorded of the file so (`recordedBytes`), and otherwise they may have been other bytes.
    private func absent(_ work: Work) -> Present {
        let newest = work.deliveries[0], recorded = newest.capture?.observedAt ?? newest.deliveredAt ?? .distantPast
        guard let (last, at) = seen[work.latest.path], at > recorded else { return .absent(work) }
        switch last {
        case .read(let sha): return .absent(sha256: sha, deliveredAt: at)
        case .listed(let file): return .absent(sha256: recordedBytes(of: work, as: file), deliveredAt: at)
        case .absent: return .absent(work)
        }
    }

    /// The bytes recorded of the work's current file while it was as `file`, as far as Gleaner
    /// knows without reading it: those a verdict or mark was made on with that size, those dates
    /// and that inode, else those a revision recorded with that size and modification date, as a
    /// listed file is matched (SPEC §5.4). Nil when none was.
    private func recordedBytes(of work: Work, as file: FileStat) -> String? {
        if let review = reviews.history(of: work).first(where: { $0.file == file }) { return review.sha256 }
        return work.latest.deliveries.first { delivery in
            guard delivery.sha256 != nil, let capture = delivery.capture else { return false }
            return capture.size == file.size && capture.modifiedAt?.timeIntervalSince1970 == file.modifiedAt.timeIntervalSince1970
        }?.sha256
    }

    /// Records what Gleaner saw of the file at `path` now, a regular file: its bytes, when this
    /// session read it as it is, else its size, dates and inode.
    private func see(_ path: String, _ file: FileStat) {
        let read = reads[path].flatMap { $0.file == file ? $0.sha256 : nil }
        seen[path] = (read.map(Present.read) ?? .listed(file), Date())
    }

    /// The Reviewed state of the work's current file.
    func verdict(of work: Work) -> Standing {
        Review.standing(reviews.verdicts(of: work), now: present(work))
    }

    /// The Published state of the work's current file.
    func published(of work: Work) -> Standing {
        Review.standing(reviews.published(of: work), now: present(work))
    }

    /// What waits on the person's review, grouped by unit (`Organization.toReview`). Worked out
    /// again only when the organization, the verdicts or what is known of a file changed: the
    /// sidebar asks for it on every collection's row.
    var toReview: [Organization.ReviewGroup] {
        // Read for the views that ask, so they follow every change the queue follows: a read that
        // moves it also writes `listed` (`noteRead`).
        _ = (organization.works.count, reviews, listed.count)
        let key = [organizationVersion, reviewsVersion]
        if let cached = queueCache, cached.key == key { return cached.groups }
        let groups = organization.toReview(reviews, present: present)
        queueCache = (key, groups)
        return groups
    }
    @ObservationIgnored private var queueCache: (key: [Int], groups: [Organization.ReviewGroup])?

    /// How many works wait on the person's review.
    var toReviewCount: Int { toReview.reduce(0) { $0 + $1.works.count } }

    /// How many works in the collection, and in the collections inside it, wait on the person.
    func waiting(in key: String) -> Int {
        toReview.lazy.filter { group in group.unit.map { $0 == key || self.organization.unit($0)?.parent == key } ?? false }
            .reduce(0) { $0 + $1.works.count }
    }

    /// What waits on the person about the work, on its row: none in a collection yet, or a verdict
    /// on other bytes. A folder has no bytes to judge, so nothing waits on one.
    func waits(_ work: Work) -> (Mark, String)? {
        guard work.kind != .folder else { return nil }
        return Wording.waiting(verdict(of: work), inUnit: work.unit != nil, noFile: hasNoFile(work))
    }

    /// Whether no regular file Gleaner can read was found at the current file of a work a review
    /// state is shown for, when its size and dates were last taken: there are no bytes there to
    /// judge.
    func hasNoFile(_ work: Work) -> Bool {
        if case .some(.none) = listed[work.latest.path] { true } else { false }
    }

    /// The On this Mac state of the work's current file, as the library knows it without reading
    /// it: a regular file there when its size and dates were taken, else this session's check or
    /// what the library found gone.
    func onThisMac(_ work: Work) -> Statement {
        let file = work.latest, now = rowNow(file)
        // A file a review state is shown for: as its size and dates were last taken, when the
        // library was organized, the file selected or its review page drawn.
        if let entry = listed[file.path] {
            guard entry != nil else { return Wording.onThisMac(absent[file.path] ?? .missing, changed: false) }
            return Wording.onThisMac(.file, changed: now.kind == .file && now.changed)
        }
        if let kind = now.kind { return Wording.onThisMac(kind, changed: now.changed) }
        return Wording.onThisMac(file.kind == .folder ? .directory : .file, changed: false)
    }

    /// The file as the person was last shown it in the detail, while it is still as read: what a
    /// verdict made there binds to (A17). Nil when the detail shows other bytes than the file's.
    func shownFile(_ work: Work, sha: String?) -> FileStat? {
        guard let sha, let read = reads[work.latest.path], read.sha256 == sha else { return nil }
        return read.file
    }

    /// What Git said of each file a Not kept label names, with the file as it was when Git was
    /// asked: asked when the label is shown, and again whenever the file is selected.
    private var gitStates: [String: (file: FileStat, state: GitState)] = [:]

    /// What Git said of the file at `path` while it was `file`: nil once its size, dates or identity
    /// differ, so Git's word about other bytes is never repeated about these.
    func gitState(of path: String, as file: FileStat) -> GitState? {
        gitStates[path].flatMap { $0.file == file ? $0.state : nil }
    }

    /// Asks Git, off the main thread, about the files at `paths` it wasn't asked about as they are now.
    func lookUpGit(_ paths: [String]) async {
        let known = gitStates
        let found = await Task.detached(priority: .utility) {
            Set(paths).compactMap { path -> (String, FileStat, GitState)? in
                guard let file = FileStat(path), known[path]?.file != file else { return nil }
                let state = Locator.gitState(of: path)
                return FileStat(path) == file ? (path, file, state) : nil
            }
        }.value
        for (path, file, state) in found { gitStates[path] = (file, state) }
    }

    /// Whether the file at `path` is in a worktree of its own, where its folder may be removed.
    private func inWorktree(_ path: String) -> Bool {
        organization.work(containing: path)?.files.first { $0.path == path }?.inWorktree ?? false
    }

    /// That Gleaner keeps no copy of the bytes `review` was made on (docs/design/review.md, Keeping
    /// what was judged): over the save limit and not saved, a copy the person asked for that
    /// couldn't be saved (`unsaved`), or a first read's save that failed. What Git holds of the file
    /// is said only while the file may still hold those bytes: then it speaks of them, and once the
    /// file holds others, of those. Nil while Gleaner holds them.
    func notKept(_ review: Review) -> Statement? {
        guard !hasSaved(review.sha256) else { return nil }
        let held = mayStillHold(review)
        return Wording.notKept(review.kind, size: review.file.size, overLimit: review.file.size > indexer.saveLimit,
                               failed: unsaved[review.sha256], git: held ? gitState(of: review.path, as: review.file) : nil,
                               worktree: held && inWorktree(review.path))
    }

    /// Copies the person asked for, by the hash of the bytes, that couldn't be saved this session,
    /// with why.
    private var unsaved: [String: any Error] = [:]

    /// Of `works` about to be judged, those whose bytes the verdict won't keep unless the person
    /// asks, with their size: over the save limit, as shown, and not bytes Gleaner holds, as far as
    /// it knows without reading them: read this session, or with the size and dates recorded of a
    /// revision or verdict whose bytes it saved.
    func wouldNotKeep(_ works: [Work], shown: [String: FileStat]) -> [(work: Work, size: Int64, file: FileStat)] {
        works.compactMap { work in
            let path = work.latest.path
            guard let file = shown[path] ?? (listed[path] ?? nil), file.size > indexer.saveLimit else { return nil }
            let bytes = reads[path].flatMap { $0.file == file ? $0.sha256 : nil } ?? recordedBytes(of: work, as: file)
            return bytes.map(hasSaved) == true ? nil : (work, file.size, file)
        }
    }

    /// Whether the file a verdict or mark was made on may still hold its bytes, as far as Gleaner
    /// knows without reading it: read since as those bytes, or as it was when they were judged.
    func mayStillHold(_ review: Review) -> Bool {
        guard let work = organization.work(containing: review.path), work.latest.path == review.path else { return false }
        return switch present(work) {
        case .read(let sha): sha == review.sha256
        case .listed(let file): file == review.file
        case .absent: false
        }
    }

    /// Saves a copy of the bytes `review` was made on while the file still holds them, as a
    /// delivery's Save a Copy does; nil when it did, otherwise why not.
    func saveCopy(of review: Review) async -> String? {
        let indexer = indexer
        let result = await Task.detached(priority: .userInitiated) { Result { try indexer.saveCopy(of: review) } }.value
        switch result {
        case .success:
            saved.insert(review.sha256)
            unsaved[review.sha256] = nil
            announce("Saved a copy of \((review.path as NSString).lastPathComponent)")
            return nil
        case .failure(let error):
            unsaved[review.sha256] = error
            return Wording.saveFailed(error)
        }
    }

    /// The bytes a verdict or mark was made on, as one end of a comparison, from Gleaner's saved
    /// copy; nil while it holds none.
    func reviewEnd(_ review: Review) -> Comparison.End? {
        guard hasSaved(review.sha256) else { return nil }
        return Comparison.End(title: "\(Wording.reviewName(review.kind)) \(Wording.shortDate(review.madeAt))", source: "saved copy",
                              sha: review.sha256, url: indexer.store.objectURL(review.sha256))
    }

    /// The bytes a verdict or mark was made on beside the file on disk, as checked, when Gleaner
    /// keeps them and the file holds others now: what was judged beside what is there, whether or
    /// not a delivery also recorded those bytes.
    func reviewComparison(_ review: Review) -> (from: Comparison.End, to: Comparison.End)? {
        guard let judged = reviewEnd(review), let work = organization.work(containing: review.path),
              let artifact = work.files.first(where: { $0.path == review.path }),
              let now = currentEnd(artifact), now.sha != review.sha256 else { return nil }
        return (judged, now)
    }

    /// The bytes a verdict or mark was made on, for another app, while Gleaner keeps them: staged
    /// and hashed when the receiver asks, as any version is.
    func reviewItem(_ review: Review) -> NSItemProvider? {
        guard hasSaved(review.sha256), let artifact = organization.work(containing: review.path)?.files.first(where: { $0.path == review.path })
        else { return nil }
        return handoffItem(sha: review.sha256, artifact: artifact)
    }

    /// The collection holding the work, as a list names it ("Launch › Assets"); nil in none.
    func collectionPath(_ work: Work) -> String? {
        organization.unit(of: work).map { Wording.unitPath($0.unit, in: organization) }
    }

    /// The collection to make a new one in from the File menu, or to rename or delete: the one
    /// shown, else the one whose page is shown.
    var currentUnit: WorkUnit? {
        if let key = shownUnit, let unit = organization.unit(key) { return unit }
        if case .unit(let key) = place { return organization.unit(key) }
        return nil
    }

    /// Where New Collection makes one: inside the collection shown (beside it, when it is itself
    /// inside another, since collections nest one level deep), else in the project shown, else in
    /// the selected work's project.
    var newUnitPlace: (project: String, parent: String?)? {
        if case .unit(let key) = place, let unit = organization.unit(key) { return (unit.project, unit.parent ?? unit.key) }
        if let project = currentProject { return (project.key, nil) }
        return selectedWorks.first.map { ($0.project, nil) }
    }

    /// Starts naming a new collection in place in the sidebar; once named, `adding` (works' or
    /// observed files' paths) go in it, as one step on Edit › Undo named `command`.
    func startNewUnit(in project: String, inside parent: String? = nil, adding: [String] = [], as command: String = "New Collection") {
        sidebarClosed.remove(project)
        if let parent { sidebarClosed.remove(parent) }
        naming = .new(project: project, parent: parent, adding: adding, command: command)
    }

    /// Starts naming the collection in place in the sidebar, with its project and the collection
    /// it is inside opened to show it.
    func startRenaming(_ unit: WorkUnit) {
        sidebarClosed.remove(unit.project)
        if let parent = unit.parent { sidebarClosed.remove(parent) }
        naming = .rename(unit.key)
    }

    /// How many collections deleting the person's project `key` deletes with it: those made in it,
    /// and those inside them, while they are shown.
    func unitsDeleted(with key: String) -> Int {
        let made = Set(units.filter { $0.project == key }.map(\.key))
        return organization.units.filter { made.contains($0.key) || $0.parent.map(made.contains) == true }.count
    }

    /// Ends naming in place with `name`: makes the collection, or renames it. An empty name makes
    /// nothing. A new one is shown, unless it was made to hold what the person was adding.
    func commitNaming(_ name: String) async {
        guard let naming else { return }
        self.naming = nil
        await commit(naming, name: name)
    }

    func commit(_ naming: Naming, name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch naming {
        case .new(let project, let parent, let adding, let command):
            let works = adding.compactMap { organization.work(containing: $0) }
            let candidates = adding.compactMap { organization.candidate($0) }
            if works.isEmpty && candidates.isEmpty {
                if let made = await newUnit(named: name, in: project, inside: parent) { place = .unit(made.key) }
            } else {
                await newUnit(named: name, in: project, inside: parent, holding: works, candidates, as: command)
            }
        case .rename(let key):
            if let unit = organization.unit(key) { await rename(unit, to: name) }
        }
    }

    /// The projects and collections closed in the sidebar this session; the rest are open.
    var sidebarClosed: Set<String> = []

    /// A project's observed files, by the session each was last observed during, newest first,
    /// of the kind chosen (docs/design/review.md, Keeping an observed file).
    /// Made again only when the organization or the kind changes, not each time the outline is drawn.
    func observedSessions(in project: Organization.Project) -> [ObservedSession] {
        let key = ObservedKey(project: project.key, kind: kind, organization: organizationVersion)
        if let cached = observedCache, cached.key == key { return cached.sessions }
        var order: [String] = [], groups: [String: [Candidate]] = [:]
        for candidate in organization.candidates(in: project.key) where kind == nil || candidate.kind == kind {
            let log = candidate.latest.logPath
            if groups[log] == nil { order.append(log) }
            groups[log, default: []].append(candidate)
        }
        let sessions = order.map { ObservedSession(logPath: $0, candidates: groups[$0]!) }
        observedCache = (key, sessions)
        return sessions
    }

    private struct ObservedKey: Equatable {
        var project: String, kind: Artifact.Kind?, organization: Int
    }
    @ObservationIgnored private var observedCache: (key: ObservedKey, sessions: [ObservedSession])?

    /// Whether a session's observed files are shown: as the person left it, else open where a
    /// project's works open (`opensByDefault`).
    func isOpen(_ session: ObservedSession) -> Bool {
        unfolded["observed\n" + session.logPath] ?? opensByDefault
    }

    /// The decisions about a selection of rows dropped on a collection: the works the rows name,
    /// or, when a row of a multiple selection was dragged, every work chosen.
    func dropped(_ paths: [String]) -> [Work] {
        let works = paths.compactMap { organization.work(containing: $0) }
        let chosen = selectedWorks
        return works.contains(where: { work in chosen.contains { $0.id == work.id } }) ? chosen : works
    }

    /// Takes the size and dates of each file a review state is shown for: the current file of each
    /// work in a unit or with a verdict or mark. Metadata only.
    private func statReviewed() {
        var listed: [String: FileStat?] = [:], absent: [String: LocatorState.Kind] = [:]
        for work in organization.works where work.unit != nil || reviews.any(work) {
            let path = work.latest.path, file = FileStat(path)
            listed[path] = .some(file)
            if let file { see(path, file) } else { absent[path] = Self.absence(path) }
        }
        self.listed = listed
        self.absent = absent
    }

    /// What is at `path` when no regular file Gleaner can read is: a regular file it may not read
    /// is unreadable, never gone (A20).
    private static func absence(_ path: String) -> LocatorState.Kind {
        let kind = Locator.stat(path).kind
        return kind == .file ? .unreadable : kind
    }

    /// Records a read of the file at `path` this session: its bytes stand for the file while it is
    /// still as `file`. Without bytes or a file, the read stands for nothing. The review states and
    /// the queue follow it for a file they are shown for, or one a verdict or mark was just made on
    /// (`judged`); a read of any other file leaves them as they were.
    private func noteRead(_ path: String, sha256: String?, file: FileStat?, judged: Bool = false) {
        let read = sha256.flatMap { sha in file.map { (sha256: sha, file: $0) } }
        reads[path] = read
        guard judged || listed[path] != nil else { return }
        let now = read?.file ?? FileStat(path)
        if let now { see(path, now) }
        listed[path] = .some(now)
        absent[path] = now == nil ? Self.absence(path) : nil
        reviewsVersion += 1
    }

    /// Takes what a review page found at `path` as it drew the file: its size, dates and inode, or
    /// nil when no regular file Gleaner can read is there. The marks, To Review and Review All then
    /// say what the page drew, even of a file rewritten outside any session. Metadata only.
    func noteShown(_ path: String, _ file: FileStat?) {
        guard let entry = listed[path], entry != file else { return }
        if let file { see(path, file) }
        listed[path] = .some(file)
        absent[path] = file == nil ? Self.absence(path) : nil
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

    /// Puts `delivery`'s reference on `pasteboard` as text, for a composer that takes only text:
    /// the JSON `gleaner resolve` writes, its identity fields kept apart (query-core "In the app").
    /// The file is checked off the main thread, as `resolve` checks it on each call.
    func copyReference(_ delivery: Delivery, to pasteboard: NSPasteboard = .general) async {
        actionFailure = nil
        var catalog = Catalog(registry: indexer.registry, store: indexer.store)
        catalog.saveLimit = indexer.saveLimit
        let result = await Task.detached(priority: .userInitiated) { [catalog] in
            Result { String(decoding: try Catalog.encoder.encode(catalog.resolve(delivery.id)), as: UTF8.self) }
        }.value
        switch result {
        case .success(let reference):
            pasteboard.clearContents()
            pasteboard.setString(reference, forType: .string)
        case .failure(let error):
            fail(delivery, Wording.referenceFailed(error))
        }
    }

    /// Shows the log of the session that delivered `delivery` in Finder: the reply that named the
    /// file is at the line More Info gives (`Wording.logLine`). The log is not the conversation;
    /// going back to that is `resume`. When the agent has removed the log, the delivery's panel says so.
    func revealLog(_ delivery: Delivery) {
        actionFailure = nil
        if !isLogGone(delivery) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: delivery.logPath)])
        } else {
            fail(delivery, Wording.logGone(delivery.logPath))
        }
    }

    /// True when the agent has removed the log of the session that delivered `delivery`, checked now:
    /// Show in Log has nothing to show, and the detail says so where it would be.
    func isLogGone(_ delivery: Delivery) -> Bool {
        Locator.stat(delivery.logPath).kind == .missing
    }

    /// Says why an action on `delivery` did nothing, in its hand-off panel, and shows the delivery
    /// so the panel is on screen.
    private func fail(_ delivery: Delivery, _ message: String) {
        select(delivery)
        actionFailure = (delivery.path, delivery.id, message)
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

    /// What dragging a row of `work` hands over: what `dragItem` hands another app, when there is
    /// something, and the work itself, which only Gleaner reads, to drop on a collection.
    func rowDragItem(_ work: Work, _ artifact: Artifact, _ delivery: Delivery) -> NSItemProvider {
        let provider = dragItem(artifact, delivery) ?? NSItemProvider()
        let id = work.id
        provider.registerDataRepresentation(forTypeIdentifier: UTType.gleanerWork.identifier, visibility: .ownProcess) { done in
            done(Data(id.utf8), nil)
            return nil
        }
        return provider
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
        if state.kind == .file, let file { gitStates[path] = (file, state.git) }
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

    /// Prepares the bytes the detail shows for `plan`: the version's, or, when its bytes are gone,
    /// the file on disk now, while Gleaner can read it. The file can still be read and judged; only
    /// that version can't be shown. Nothing, for a plan with no bytes to show.
    func show(_ plan: Handoff?, artifact: Artifact) async {
        if let sha = plan?.sha {
            await stage(sha: sha, artifact: artifact)
        } else {
            clearStaging()
        }
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

extension UTType {
    /// A work dragged from a list to a collection in the sidebar: its id, read only by Gleaner.
    static let gleanerWork = UTType(exportedAs: "app.gleaner.work")
}
