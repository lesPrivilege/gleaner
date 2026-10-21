import GleanerCore
import QuickLook
import GleanerUI
import SwiftUI

/// The library window: where you are (every delivery, a project, or the sources), what is there,
/// and the selected work.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    // Search, filters and place survive relaunch; selection does not, since results may have changed.
    @SceneStorage("query") private var savedQuery = ""
    @SceneStorage("kind") private var savedKind = ""
    @SceneStorage("place") private var savedPlace = ""
    @SceneStorage("arrangement") private var savedArrangement = ""
    @State private var columns = NavigationSplitViewVisibility.automatic

    var body: some View {
        @Bindable var model = model
        // Read here so the view follows every change to what the selection hands over.
        let quickLookURL = model.quickLookURL
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } content: {
            ContentColumn()
                .navigationSplitViewColumnWidth(min: 330, ideal: 380, max: 480)
        } detail: {
            DetailColumn()
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search Deliveries")
        .quickLookPreview(Binding(get: { quickLookURL }, set: { model.isQuickLookOpen = $0 != nil }))
        .onChange(of: model.selectedHandoffURL) { if model.selectedHandoffURL == nil { model.isQuickLookOpen = false } }
        .onAppear(perform: restore)
        // Decisions go on the window's Edit › Undo, as a Mac app's edits do.
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { model.undoManager = undoManager }
        .onChange(of: model.query) { savedQuery = model.query }
        .onChange(of: model.kind) { savedKind = model.kind?.rawValue ?? "" }
        .onChange(of: model.place) { savedPlace = Self.encode(model.place) }
        .onChange(of: model.arrangement) { savedArrangement = model.arrangement.rawValue }
        .alert("Gleaner couldn’t open this link",
               isPresented: Binding(get: { model.linkFailure != nil }, set: { if !$0 { model.linkFailure = nil } })) {
        } message: {
            Text(model.linkFailure ?? "")
        }
        // A collection is named in place in the sidebar, so the sidebar shows while it is.
        .onChange(of: model.naming) { if model.naming != nil { columns = .all } }
        .navigationSubtitle(model.progress.map { "Reading logs… \($0.done) of \($0.total)" } ?? model.status)
        .toolbar {
            ToolbarItem {
                ConnectionsButton()
            }
            ToolbarItem {
                Button("Check for New Deliveries", systemImage: "arrow.clockwise") { model.reindex() }
                    .help("Check for New Deliveries (⌘R)")
            }
        }
    }

    /// The search first and the place after it, so a saved Sources page stays open; the kind
    /// last, since entering a project clears it.
    func restore() {
        let kind = Artifact.Kind(rawValue: savedKind)
        model.query = savedQuery
        switch Self.decode(savedPlace) {
        case .project(let key) where model.organization.project(key) == nil: model.place = .all
        case .unit(let key) where model.organization.unit(key) == nil: model.place = .all
        case let place: model.place = place
        }
        model.kind = kind
        model.arrangement = Arrangement(rawValue: savedArrangement) ?? .works
    }

    static func encode(_ place: Place) -> String {
        switch place {
        case .all: ""
        case .toReview: "review"
        case .sources: "sources"
        case .project(let key): "project:" + key
        case .unit(let key): key
        }
    }

    static func decode(_ text: String) -> Place {
        if text == "sources" { return .sources }
        if text == "review" { return .toReview }
        if text.hasPrefix("project:") { return .project(String(text.dropFirst("project:".count))) }
        // A collection's key names it: `unit:` and its id.
        if text.hasPrefix("unit:") { return .unit(text) }
        return .all
    }
}

/// Every delivery, what waits on the person's review, each project with its collections, and the
/// sources Gleaner reads.
struct Sidebar: View {
    /// Where a heading and a name begin: on the icons' edge, as in the rows with icons, rather than
    /// against the selection's edge. A collection keeps the outline's indent beneath its project.
    static let inset = Space.s

    @Environment(LibraryModel.self) private var model
    @State private var renaming: Organization.Project?
    @State private var newName = ""
    @State private var removing: Organization.Project?

    var body: some View {
        let place = Binding<Place?>(get: { model.place }, set: { if let place = $0 { model.place = place } })
        List(selection: place) {
            GlyphLabel(title: "All Deliveries", glyph: .artifact)
                .tag(Place.all)
            // What waits on the person, counted as Mail counts what is unread.
            let waiting = model.toReviewCount
            GlyphLabel(title: "To Review", glyph: .awaiting)
                .badge(waiting)
                .tag(Place.toReview)
                .accessibilityLabel("To Review, \(Wording.toReview(waiting))")
                .help(Wording.toReview(waiting))
            Section {
                ForEach(model.projects) { project in
                    let units = model.organization.units(in: project.key)
                    if units.isEmpty && !naming(project.key, inside: nil) {
                        projectRow(project)
                    } else {
                        // A project's collections under it, as Mail lists a mailbox's.
                        DisclosureGroup(isExpanded: open(project.key)) {
                            ForEach(units) { unit in
                                let inner = model.organization.units(inside: unit.key)
                                if inner.isEmpty && !naming(project.key, inside: unit.key) {
                                    UnitSidebarRow(unit: unit)
                                } else {
                                    DisclosureGroup(isExpanded: open(unit.key)) {
                                        ForEach(inner) { UnitSidebarRow(unit: $0) }
                                        if naming(project.key, inside: unit.key) { NamingField() }
                                    } label: {
                                        UnitSidebarRow(unit: unit)
                                    }
                                }
                            }
                            if naming(project.key, inside: nil) { NamingField() }
                        } label: {
                            projectRow(project)
                        }
                    }
                }
            } header: {
                ProjectsHeading()
            }
            Section {
                // A source that needs a look shows the triangle at the row's end, as Mail marks a
                // mailbox it couldn't read; the agent's mark stays the agent's.
                HStack {
                    GlyphLabel(title: "Sources", glyph: .agent)
                    Spacer(minLength: Space.xs)
                    if model.logTrouble != nil {
                        GlyphView(glyph: .warning, size: 14).foregroundStyle(Palette.attention)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(model.logTrouble.map { "Needs a look: " + $0 } ?? "")
                .tag(Place.sources)
                .help(model.logTrouble ?? "Agent logs, your corrections, and storage")
            } header: {
                Text("Library").padding(.leading, Self.inset)
            }
        }
        .alert("Rename Project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let renaming { Task { await model.rename(renaming, to: newName) } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(removing?.name ?? "")”?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Delete Project", role: .destructive) { if let removing { Task { await model.remove(removing) } } }
        } message: {
            Text(Wording.deletingProject(units: removing.map { model.unitsDeleted(with: $0.key) } ?? 0))
        }
    }

    func projectRow(_ project: Organization.Project) -> some View {
        // The name alone: what a project is made of is metadata, behind the help tag. Its works are
        // counted there too, never as a badge, which counts only what waits (To Review).
        Text(project.name).lineLimit(1).truncationMode(.middle)
        .padding(.leading, Self.inset)
        .accessibilityLabel("\(project.name), \(Wording.projectOrigin(project.origin)), \(Wording.count(project.works.count, "work"))")
        .tag(Place.project(project.key))
        .help("\(Wording.projectOrigin(project.origin)) · \(Wording.projectCounts(project))")
        .contextMenu { menu(project) }
    }

    /// Open unless the person closed it this session.
    func open(_ key: String) -> Binding<Bool> {
        Binding(get: { !model.sidebarClosed.contains(key) }, set: { open in
            if open { model.sidebarClosed.remove(key) } else { model.sidebarClosed.insert(key) }
        })
    }

    /// Whether a new collection is being named here.
    func naming(_ project: String, inside parent: String?) -> Bool {
        if case .new(project, parent, _, _)? = model.naming { true } else { false }
    }

    @ViewBuilder func menu(_ project: Organization.Project) -> some View {
        Button("New Collection") { model.startNewUnit(in: project.key) }
        Divider()
        if let folder = project.folder {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                .disabled(Locator.stat(folder).kind != .directory)
        }
        if project.origin != .yours {
            Menu("Show Inside") {
                ForEach(model.projects.filter { $0.key != project.key }) { other in
                    Button(other.name) { Task { await model.combine(project.key, into: other.key) } }
                }
            }
        } else {
            Button("Rename…") { newName = project.name; renaming = project }
            Button("Delete Project…") { removing = project }
        }
    }
}

/// The Projects heading, whose plus, shown under the pointer, makes a collection where New
/// Collection (⇧⌘N) would: in the collection or project shown, else the chosen work's project.
struct ProjectsHeading: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Space.xs) {
            Text("Projects")
            Spacer(minLength: Space.xs)
            Button(action: model.startNewUnitHere) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(model.newUnitPlace == nil)
            .opacity(hovering ? 1 : 0)
            .help(help)
            // A shortcut for the pointer: the keyboard and VoiceOver have File › New Collection.
            .accessibilityHidden(true)
        }
        .padding(.leading, Sidebar.inset)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(Motion.feedback(reduceMotion)) { self.hovering = hovering } }
    }

    var help: String {
        guard let place = model.newUnitPlace else { return "Choose a project to make a collection in it" }
        let name = place.parent.flatMap { model.organization.unit($0)?.name } ?? model.organization.project(place.project)?.name
        return "New Collection in \(name ?? "this project") (⇧⌘N)"
    }
}

/// What the place holds: search results, what waits on review, a project's outline, a
/// collection's works, or the sources; or, for every delivery and a project, their timeline.
struct ContentColumn: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        if model.showsTimeline {
            TimelineList()
        } else {
            places
        }
    }

    @ViewBuilder var places: some View {
        switch model.place {
        case .sources:
            SourcesList()
        case .project(let key):
            if model.query.isEmpty, let project = model.organization.project(key) {
                ProjectOutline(project: project)
            } else {
                ResultsList()
            }
        case .unit(let key):
            if model.query.isEmpty, let unit = model.organization.unit(key) {
                UnitList(unit: unit)
            } else {
                ResultsList()
            }
        case .toReview:
            if model.query.isEmpty { ToReviewList() } else { ResultsList() }
        case .all:
            ResultsList()
        }
    }
}

/// The selected work, a conversation opened from it, a collection's review page, or the next step.
struct DetailColumn: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        if model.place == .sources {
            SourcePageView()
        } else if let thread = model.thread {
            ThreadView(page: thread).id(thread.logPath)
        } else if model.selectedWorks.count > 1 {
            SeveralSelected(works: model.selectedWorks)
        } else if let result = model.selected {
            DetailView(result: result)
        } else if let unit = model.currentUnit {
            ReviewPage(unit: unit).id(unit.key)
        } else if !model.artifacts.isEmpty {
            NoSelection()
        }
    }
}

/// Handing over and opening the selection from a list, shared by the results and the outline,
/// and the selection's collection: added to one, or taken out.
struct ListHandoff: ViewModifier {
    @Environment(LibraryModel.self) private var model

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: OutlineRow.self) { rows in
                let works = rows.compactMap(\.work).compactMap { model.organization.work(containing: $0) }
                if rows.count == 1, let row = rows.first, let id = row.work, let work = model.organization.work(containing: id),
                   let (artifact, delivery) = model.target(row) {
                    // The file the row names and drags, and its delivery: a revision's own, or the one its work's row shows.
                    if row == model.outlineSelection {
                        Button("Open") { model.openSelected() }.disabled(!model.canHandOver)
                        Button("Quick Look") { model.toggleQuickLook() }.disabled(!model.canHandOver)
                        Divider()
                    }
                    Button(model.missing.contains(artifact.path) ? "Show Folder in Finder" : "Show in Finder") { model.reveal(artifact) }
                    Button("Show in Log") { model.revealLog(delivery) }
                    Button("Copy Path") { model.copyPath(artifact) }
                    Button("Copy Reference") { Task { await model.copyReference(delivery) } }
                    Divider()
                    Button("Go to \(model.projectName(work))") { model.place = .project(work.project); model.selection = work.id }
                }
                if !works.isEmpty {
                    Divider()
                    CollectionCommands(works: works)
                }
                if rows.count == 1, case .unit(let key)? = rows.first, let unit = model.organization.unit(key) {
                    UnitCommands(unit: unit)
                }
                // The list itself, while it holds what a search found.
                if rows.isEmpty, !model.query.isEmpty, !model.results.isEmpty {
                    NewCollectionFromThese(works: model.results.map(\.work))
                }
            }
            .onKeyPress(.space) {
                guard model.canHandOver || model.isQuickLookOpen else { return .ignored }
                model.toggleQuickLook()
                return .handled
            }
            .onCopyCommand { model.copyItem().map { [$0] } ?? [] }
    }
}

struct ResultsList: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let results = model.results
        let repeated = Set(Dictionary(grouping: results, by: \.work.name).filter { $0.value.count > 1 }.keys)
        // Filters sit above the list, not over it: rows never scroll under the glass controls.
        VStack(spacing: 0) {
            FilterBar()
            List(selection: $model.selectedRows) {
                // What a search found, which the person may keep together: the list's first row, as a
                // project's head is in its outline, so it begins below the band the filters sit in,
                // where a header pinned to the list's top would sit under it.
                if !model.query.isEmpty, !results.isEmpty {
                    FoundLine(works: results.map(\.work)).listRowSeparator(.hidden)
                }
                ForEach(results) { result in
                    WorkEntry(result: result,
                              project: model.currentProject == nil ? model.organization.project(result.work.project) : nil,
                              showFolder: repeated.contains(result.work.name), namesCollection: true)
                }
            }
            .modifier(ListHandoff())
            .modifier(FollowsSelection())
            .overlay { if results.isEmpty { ResultsEmptyState() } }
            TroubleBar()
        }
    }
}

/// What an empty list of works says: the logs still being read or not found, nothing of the kind
/// chosen, or no results, each with its next step.
struct ResultsEmptyState: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        if model.artifacts.isEmpty {
            if !model.indexed {
                EmptyState(title: "Reading Agent Logs…", glyph: .running)
            } else if model.canReadAgain, let trouble = model.logTrouble {
                ContentUnavailableView {
                    Label("Some Logs Couldn’t Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(trouble)
                } actions: {
                    Button("Try Again") { model.reindex() }
                }
            } else if model.sources?.values.allSatisfy({ $0.folder == .absent }) == true {
                ContentUnavailableView {
                    Label("No Agent Logs", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Gleaner looked in:\n"
                         + model.indexer.sources.watchedDirectories.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n"))
                } actions: {
                    Button("Sources") { model.place = .sources }
                }
            } else {
                EmptyState(title: "No Deliveries Yet", glyph: .artifact,
                           description: model.indexer.sources.watchedDirectories.map(Wording.tilde).joined(separator: "\n")
                               + (model.logTrouble.map { "\n\n" + $0 } ?? "")) {
                    Button("Sources") { model.place = .sources }
                }
            }
        } else if model.query.isEmpty {
            NoKind()
        } else {
            ContentUnavailableView {
                Label("No Results", systemImage: "magnifyingglass")
            } actions: {
                Button("Clear Search") { model.clearFilters() }
                if model.currentProject != nil { Button("Search All Deliveries") { model.place = .all } }
            }
        }
    }
}

/// What a search found, as the header of its results: how many works, in how many projects when
/// more than one, and New Collection from These, which a group spanning projects can't take.
struct FoundLine: View {
    var works: [Work]

    var body: some View {
        HStack(spacing: Space.s) {
            Text(Wording.found(works.count, projects: Set(works.map(\.project)).count))
                .foregroundStyle(.secondary).monospacedDigit()
            Spacer(minLength: Space.s)
            NewCollectionFromThese(works: works)
                .controlRole(.inline)
                .fixedSize()
        }
        .font(.callout)
    }
}

/// The project shown, and the kind filter, above a list. A project's outline names its project in
/// its own head, so the bar leaves it out there. A name too long to sit whole beside the filters goes
/// above them: it says where a search looks.
struct FilterBar: View {
    @Environment(LibraryModel.self) private var model
    var named = true

    var body: some View {
        Group {
            if named, let project = model.currentProject {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        name(project)
                        Spacer(minLength: 0)
                        filters
                    }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        name(project)
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            filters
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    filters
                }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }

    func name(_ project: Organization.Project) -> some View {
        Text(project.name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
            .help(Wording.projectOrigin(project.origin))
    }

    @ViewBuilder var filters: some View {
        @Bindable var model = model
        if model.offersTimeline {
            Picker("Show", selection: $model.arrangement) {
                Text("Works").tag(Arrangement.works)
                Text("Timeline").tag(Arrangement.timeline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Show the works, or the replies that handed them over, by day")
        }
        Picker("Kind", selection: $model.kind) {
            Text("All Kinds").tag(Artifact.Kind?.none)
            Divider()
            ForEach(Artifact.Kind.allCases, id: \.self) { kind in
                Text(Wording.kindName(kind)).tag(Artifact.Kind?.some(kind))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

/// One line about the agents' logs when something needs a look, under a list.
struct TroubleBar: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        if !model.artifacts.isEmpty, let trouble = model.logTrouble {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StatusLabel(mark: .attention, text: trouble).font(.caption).lineLimit(2)
                    .help(trouble)
                Spacer(minLength: Space.s)
                if model.canReadAgain {
                    Button("Try Again") { model.reindex() }
                        .controlRole(.inline)
                        .help("Read the agent logs again")
                }
                Button("Sources") { model.place = .sources }
                    .controlRole(.inline)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
        }
    }
}

/// One delivered work in a list, read as Mail reads a message: the file and its date, what you
/// asked for, then where it is and anything that needs a look. Open on its revisions, as Mail opens
/// a conversation, it leaves the request to them.
struct ResultRow: View {
    var result: SearchResult
    /// The file the row shows and hands over: the one holding `delivery`.
    var file: Artifact
    /// The delivery the row shows and hands over: the one chosen in the detail for the selected
    /// row, the matched one for any other.
    var delivery: Delivery
    /// The project as shown, by its mark and name, or nil when the list is one project's.
    var project: Organization.Project?
    var showFolder: Bool
    /// What the row says beside the date (`LibraryModel.rowStatus`).
    var status: (mark: (Mark, String)?, number: String?)
    /// Who put the work in the project the outline shows, when not Gleaner.
    var placement: Organization.Placement?
    /// Its revisions are listed under it.
    var open = false
    /// What waits on the person's review (`LibraryModel.waits`).
    var waiting: (Mark, String)? = nil
    /// The collection holding the work, as a list names it: in its help tag, and on the row with
    /// `namesCollection`.
    var collection: String? = nil
    var namesCollection = false

    var body: some View {
        let work = result.work
        // The work by its newest file's name; the context says when the row shows another of its
        // files. Open, the revision chosen under it says that, and which delivery it is.
        let context = [file.inWorktree ? file.place : nil,
                       showFolder ? Wording.folder(file.folder) : nil,
                       work.files.count > 1 ? "\(work.files.count) files" + (open || file.path == work.latest.path ? "" : ", showing \(file.name)") : nil,
                       placed,
        ].compactMap { $0 }
        let number = open ? nil : status.number
        HStack(alignment: .top, spacing: Space.s + 2) {
            FileIcon(path: work.latest.path, folder: work.latest.kind == .folder, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(work.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Space.xs)
                    // How many revisions it has, said once, as Mail counts a conversation's messages.
                    if work.deliveries.count > 1 {
                        Text("\(work.deliveries.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .help(Wording.count(work.deliveries.count, "delivery", "deliveries"))
                    }
                    // Open, its revisions each carry their agent and date.
                    if !open {
                        AgentMark(provider: delivery.provider, size: 12).foregroundStyle(.secondary)
                        Text(Wording.shortDate(delivery.deliveredAt)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .help(Wording.date(delivery.deliveredAt))
                    }
                }
                if !open, let request = delivery.request {
                    Text(request).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                } else if !open, delivery.kept != nil {
                    // No reply handed it over: the person kept it, as a session left it.
                    Text(Wording.generated(delivery).title).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                let named = namesCollection ? collection : nil
                if project != nil || !context.isEmpty || status.mark != nil || number != nil || waiting != nil || named != nil {
                    HStack(spacing: Space.s) {
                        if let waiting { StatusLabel(mark: waiting.0, text: waiting.1, size: 11) }
                        if let mark = status.mark { StatusLabel(mark: mark.0, text: mark.1, size: 11) }
                        // Where it is, by name alone: the project, then its collection, as a path.
                        let place = [project?.name, named].compactMap { $0 }
                        if !place.isEmpty {
                            Text(place.joined(separator: " › ")).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                .help(project.map { Wording.projectOrigin($0.origin) } ?? "")
                        }
                        if !context.isEmpty {
                            Text(context.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        if let number { Text(number).foregroundStyle(.secondary).monospacedDigit() }
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .help(collection.map { "In \($0)" } ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(context: context))
    }

    var placed: String? {
        switch placement {
        case .moved?: "moved here by you"
        case .combined?: "shown inside"
        default: nil
        }
    }

    /// One sentence VoiceOver reads for the row, in the order the eye reads it.
    func spoken(context: [String]) -> String {
        let work = result.work
        var parts = [work.name, Wording.kindLabel(work.latest.kind, path: work.latest.path) + " file"]
        if work.deliveries.count > 1 { parts.append(Wording.count(work.deliveries.count, "delivery", "deliveries")) }
        if let project { parts.append("\(project.name), \(Wording.projectOrigin(project.origin).lowercased())") }
        if let collection { parts.append("in \(collection)") }
        parts += context
        if let waiting { parts.append(waiting.1.lowercased()) }
        if let mark = status.mark { parts.append(mark.1.lowercased()) }
        if delivery.kept != nil {
            parts.append(Wording.generated(delivery).title.lowercased())
        } else {
            parts.append("delivered " + (delivery.deliveredAt?.formatted(date: .abbreviated, time: .shortened) ?? "at an unknown time"))
            parts.append("by " + Wording.provider(delivery.provider))
        }
        if let number = status.number { parts.append("delivery " + number) }
        if let request = delivery.request { parts.append("you asked: \(request.prefix(160))") }
        return parts.joined(separator: ", ")
    }
}
