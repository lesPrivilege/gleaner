import AppKit
import GleanerCore
import Observation
import UniformTypeIdentifiers

/// One search result: the work, and the delivery the search matched in it.
struct SearchResult: Identifiable {
    var work: Work
    var matched: Delivery
    var id: Work.ID { work.id }
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
    var artifacts: [Artifact] = [] {
        didSet {
            siblings = Artifact.deliveredWith(artifacts)
            missing = Self.missing(artifacts)
            saved = Self.saved(artifacts, in: indexer.store)
            reorganize()
        }
    }
    /// Projects and works as the person sees them: what Gleaner found, with their corrections.
    private(set) var organization = Organization(artifacts: [])
    /// The person's corrections and projects, read from the library; kept apart from what Gleaner found.
    private(set) var corrections: [Correction] = []
    private(set) var userProjects: [UserProject] = []
    /// Why the last correction couldn't be recorded.
    private(set) var correctionFailure: String?
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
        didSet { if query != oldValue { chosenDelivery = nil } }
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
        self.init(indexer: Indexer(
            registry: try Registry(path: support.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: support.appendingPathComponent("objects"), staging: caches.appendingPathComponent("handoff")),
            sources: home.map {
                LogSources(claudeProjects: $0.appendingPathComponent(".claude/projects"), codexHome: $0.appendingPathComponent(".codex"))
            } ?? .standard))
    }

    init(indexer: Indexer) {
        self.indexer = indexer
        corrections = (try? indexer.registry.corrections()) ?? []
        userProjects = (try? indexer.registry.userProjects()) ?? []
        artifacts = (try? indexer.registry.artifacts()) ?? []
        siblings = Artifact.deliveredWith(artifacts)
        missing = Self.missing(artifacts)
        saved = Self.saved(artifacts, in: indexer.store)
        reorganize()
    }

    private func reorganize() {
        organization = Organization(artifacts: artifacts, corrections: corrections, projects: userProjects, missing: missing)
    }

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
        indexFailure ?? sources.flatMap(Wording.sourcesLine)
    }

    /// True when reading the logs again may help: a run failed, or a source wasn't read whole.
    /// Unknown record types are reported, but a reread can't change them.
    var canReadAgain: Bool {
        indexFailure != nil || sources?.values.contains(where: \.isIncomplete) == true
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
        let directory = (file.path as NSString).deletingLastPathComponent
        let base = file.checkout?.folder ?? project.folder ?? file.projectFolder
        var folder = directory == base ? ""
            : directory.hasPrefix(base + "/") ? String(directory.dropFirst(base.count + 1))
            : (file.inRepository ? "Outside the repository: " : "Elsewhere: ") + (directory as NSString).abbreviatingWithTildeInPath
        if file.inWorktree { folder = file.place + (folder.isEmpty ? "" : " › " + folder) }
        if project.origin == .yours || file.projectFolder != project.key && project.folder != base {
            let found = organization.projectName(file.projectFolder)
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
                self.lastRead = Date()
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

    /// The works the window lists, newest first: in the project shown, of the kind chosen, matching the search.
    var results: [SearchResult] {
        let tokens = tokens
        return organization.works.compactMap { result(for: $0, tokens: tokens) }
    }

    /// The work as the list shows it, or nil when the place, kind or search leaves it out.
    private func result(for work: Work, tokens: [String]) -> SearchResult? {
        if case .project(let key) = place, work.project != key { return nil }
        guard kind == nil || work.kind == kind,
              let matched = work.match(tokens, project: organization.projectName(work.project)) else { return nil }
        return SearchResult(work: work, matched: matched)
    }

    /// The selected work, as the list shows it: looked up, not found by listing every work, since
    /// the detail asks for it many times each time it is drawn.
    var selected: SearchResult? {
        guard let selection, let work = organization.work(containing: selection) else { return nil }
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

    // MARK: Corrections

    /// Records a decision and shows the library with it; or says why it couldn't be recorded,
    /// and leaves the library as it was.
    private func correcting(_ change: (Registry) throws -> Void) {
        let registry = indexer.registry
        do {
            try change(registry)
            correctionFailure = nil
        } catch {
            correctionFailure = "Gleaner couldn’t record that: \(error)"
        }
        corrections = (try? registry.corrections()) ?? corrections
        userProjects = (try? registry.userProjects()) ?? userProjects
        reorganize()
    }

    /// Puts the work, every one of its files, in the project `key`.
    func move(_ work: Work, to key: String) {
        correcting { try $0.correct(.project, subjects: work.files.map(\.path), target: key, at: Date()) }
        if case .project = place { place = .project(key) }
        selection = work.id
    }

    /// Makes a project of the person's own and puts the work in it.
    func move(_ work: Work, toNewProject name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var created: UserProject?
        correcting { created = try $0.addProject(named: name, at: Date()) }
        if let created { move(work, to: created.key) }
    }

    /// Gleaner puts the work back where it found it.
    func undoMove(_ work: Work) {
        let moves = corrections.filter { $0.kind == .project && work.contains($0.subject) }
        correcting { try $0.undo(moves.map(\.id)) }
        selection = work.id
    }

    /// The two files are versions of one work, from now on and after every reread.
    func join(_ a: String, _ b: String) {
        correcting { try $0.correct(.sameWork, subject: a, target: b, at: Date()) }
        if let work = organization.work(containing: a) {
            selection = work.id
            if case .project(let key) = place, key != work.project { place = .project(work.project) }
        }
    }

    /// The two files are not one work: Gleaner stops suggesting it.
    func keepApart(_ a: String, _ b: String) {
        correcting { try $0.correct(.notSameWork, subject: a, target: b, at: Date()) }
    }

    /// Undoes one decision, whichever it was.
    func undo(_ correction: Correction) {
        correcting { try $0.undo(correction.id) }
    }

    func undoAllCorrections() {
        correcting { try $0.undoAllCorrections() }
        if case .project(let key) = place, organization.project(key) == nil { place = .all }
    }

    /// Shows the project `folder` inside the project `key`.
    func combine(_ folder: String, into key: String) {
        correcting { try $0.correct(.combine, subject: folder, target: key, at: Date()) }
        place = .project(key)
    }

    func rename(_ project: Organization.Project, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard project.origin == .yours, !name.isEmpty else { return }
        correcting { try $0.renameProject(project.key, to: name) }
    }

    /// Removes a project the person made; its work goes back where Gleaner found it.
    func remove(_ project: Organization.Project) {
        guard project.origin == .yours else { return }
        correcting { try $0.removeProject(project.key) }
        if place == .project(project.key) { place = .all }
    }

    /// What a correction did, in a sentence, for the list of corrections.
    func describe(_ correction: Correction) -> String {
        let name = { (path: String) in (path as NSString).lastPathComponent }
        return switch correction.kind {
        case .project: "\(name(correction.subject)) moved to \(organization.projectName(correction.target))"
        case .combine: "\(organization.projectName(correction.subject)) shown inside \(organization.projectName(correction.target))"
        case .sameWork: "\(name(correction.subject)) and \(name(correction.target)) are one work"
        case .notSameWork: "\(name(correction.subject)) and \(name(correction.target)) are not one work"
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
        isQuickLookOpen = !isQuickLookOpen && selectedHandoffURL != nil
    }

    /// Opens the selection's verified copy (or folder) in its app, or says why it couldn't. A copy
    /// is opened only while it is the file Gleaner hashed (`selectedHandoffURL`).
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
            selection = artifact.path
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
    }

    /// What dragging `result`'s row hands over; nil when the library already knows there is
    /// nothing: the delivery's bytes were never read, or the store holds no copy of them and the
    /// file was found gone or changed. Decided from what the library holds and the newest check of
    /// the file, never by reading the disk, so a row can ask while it is drawn. The drop verifies
    /// what it hands over.
    func rowHandoff(_ result: SearchResult) -> RowHandoff? {
        let artifact = file(in: result), delivery = delivery(in: result)
        if let observation = rowObservation(artifact.path) {
            switch artifact.handoff(delivery, now: observation, hasSaved: hasSaved) {
            case .ready(let sha, _, _): return .bytes(sha: sha)
            case .folder: return .folder
            default: return nil
            }
        }
        if delivery.capture?.isDirectory == true { return missing.contains(artifact.path) ? nil : .folder }
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
        let artifact = file(in: result), observation = rowObservation(artifact.path)
        let changed = observation.map { now in
            // No saved copy is asked about: only the missing case would, and it isn't "changed".
            if case .changed = artifact.onDisk(now, hasSaved: { _ in false }) { true } else { false }
        } ?? false
        return Wording.row(delivery(in: result), latest: artifact.latest.number,
                           now: observation?.state.kind ?? (missing.contains(artifact.path) ? .missing : nil),
                           changed: changed, available: rowHandoff(result) != nil)
    }

    /// A drag from a result row, handing over what `rowHandoff` says, or nil when there is
    /// nothing. The receiver gets its own copy, never the original to open in place: a delivery's
    /// bytes staged and verified only when the receiving app asks for them, or a delivered folder
    /// as it is then, so a drop never moves a project's file or folder (SPEC §4).
    func dragItem(for result: SearchResult) -> NSItemProvider? {
        switch rowHandoff(result) {
        case nil: nil
        case .folder: Self.folderItem(file(in: result).path)
        case .bytes(let sha): handoffItem(sha: sha, artifact: file(in: result))
        }
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
        guard let (artifact, _, plan) = selectedHandoff else { return nil }
        if plan == .folder { return NSItemProvider(contentsOf: URL(fileURLWithPath: artifact.path)) }
        guard case .ready(let url, _) = staging(for: plan.sha) else {
            if case .ready = staging { prepareAgain() }
            return nil
        }
        return NSItemProvider(contentsOf: url)
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
    /// thread. When it is Gleaner's first read of a file whose bytes a delivery never had, the
    /// library is read again with them.
    func observe(_ artifact: Artifact) async {
        let path = artifact.path, checkout = artifact.checkout, versions = Set(artifact.deliveries.compactMap(\.sha256))
        let indexer = indexer
        let (state, held, completed) = await Task.detached(priority: .userInitiated) {
            (Locator.observe(path, checkout: checkout), versions.filter(indexer.store.has),
             (try? indexer.completeCaptures(of: path, now: Date())) == true)
        }.value
        observations[path] = FileObservation(state: state, checkedAt: Date())
        saved.subtract(versions)
        saved.formUnion(held)
        if completed { artifacts = (try? indexer.registry.artifacts()) ?? artifacts }
        if state.kind == .missing {
            missing.insert(path)
        } else {
            missing.remove(path)
            // The file is there, so its folder is too.
            if let failure = actionFailure, failure.artifact == artifact.id, failure.delivery == nil { actionFailure = nil }
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
        case .success: artifacts = (try? indexer.registry.artifacts()) ?? artifacts
        case .failure(let error): actionFailure = (artifact.id, delivery.id, Wording.saveFailed(error, delivery: delivery))
        }
        await observe(artifact)
    }
}
