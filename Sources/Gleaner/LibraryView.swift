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

    var body: some View {
        @Bindable var model = model
        // Read here so the view follows every change to what the selection hands over.
        let quickLookURL = model.quickLookURL
        NavigationSplitView {
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
        .alert("Gleaner couldn’t open this link",
               isPresented: Binding(get: { model.linkFailure != nil }, set: { if !$0 { model.linkFailure = nil } })) {
        } message: {
            Text(model.linkFailure ?? "")
        }
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
        case let place: model.place = place
        }
        model.kind = kind
    }

    static func encode(_ place: Place) -> String {
        switch place {
        case .all: ""
        case .sources: "sources"
        case .project(let key): "project:" + key
        }
    }

    static func decode(_ text: String) -> Place {
        if text == "sources" { return .sources }
        if text.hasPrefix("project:") { return .project(String(text.dropFirst("project:".count))) }
        return .all
    }
}

/// Every delivery, each project, and the sources Gleaner reads.
struct Sidebar: View {
    @Environment(LibraryModel.self) private var model
    @State private var renaming: Organization.Project?
    @State private var newName = ""
    @State private var removing: Organization.Project?

    var body: some View {
        let place = Binding<Place?>(get: { model.place }, set: { if let place = $0 { model.place = place } })
        List(selection: place) {
            GlyphLabel(title: "All Deliveries", glyph: .artifact)
                .tag(Place.all)
            Section("Projects") {
                ForEach(model.projects) { project in
                    Label { Text(project.name).lineLimit(1).truncationMode(.middle) } icon: {
                        RowGlyph(glyph: Wording.projectGlyph(project.origin))
                    }
                        .accessibilityLabel("\(project.name), \(Wording.projectOrigin(project.origin)), \(Wording.count(project.works.count, "work"))")
                        .badge(project.works.count)
                        .tag(Place.project(project.key))
                        .help("\(Wording.projectOrigin(project.origin)) · \(Wording.projectCounts(project))")
                        .contextMenu { menu(project) }
                }
            }
            Section("Library") {
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
            Text("Its work goes back where Gleaner found it. No file changes.")
        }
    }

    @ViewBuilder func menu(_ project: Organization.Project) -> some View {
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

/// What the place holds: search results, a project's outline, or the sources.
struct ContentColumn: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        switch model.place {
        case .sources:
            SourcesList()
        case .project(let key):
            if model.query.isEmpty, let project = model.organization.project(key) {
                ProjectOutline(project: project)
            } else {
                ResultsList()
            }
        case .all:
            ResultsList()
        }
    }
}

struct DetailColumn: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        if model.place == .sources {
            SourcePageView()
        } else if let result = model.selected {
            DetailView(result: result)
        } else if !model.artifacts.isEmpty {
            NoSelection()
        }
    }
}

/// Handing over and opening the selection from a list, shared by the results and the outline.
struct ListHandoff: ViewModifier {
    @Environment(LibraryModel.self) private var model

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: OutlineRow.self) { rows in
                if let row = rows.first, let work = model.organization.work(containing: row.work),
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
            List(selection: $model.outlineSelection) {
                ForEach(results) { result in
                    WorkEntry(result: result,
                              project: model.currentProject == nil ? model.organization.project(result.work.project) : nil,
                              showFolder: repeated.contains(result.work.name))
                }
            }
            .modifier(ListHandoff())
            .modifier(FollowsSelection())
            .overlay { emptyState(results) }
            TroubleBar()
        }
    }

    @ViewBuilder
    func emptyState(_ results: [SearchResult]) -> some View {
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
        } else if results.isEmpty && model.query.isEmpty {
            NoKind()
        } else if results.isEmpty {
            ContentUnavailableView {
                Label("No Results", systemImage: "magnifyingglass")
            } actions: {
                Button("Clear Search") { model.clearFilters() }
                if model.currentProject != nil { Button("Search All Deliveries") { model.place = .all } }
            }
        }
    }
}

/// The project shown, and the kind filter, above a list. A project's outline names its project in
/// its own head, so the bar leaves it out there.
struct FilterBar: View {
    @Environment(LibraryModel.self) private var model
    var named = true

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            if named, let project = model.currentProject {
                GlyphLabel(title: project.name, glyph: Wording.projectGlyph(project.origin), size: 14)
                    .font(.callout.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
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
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
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
                }
                if project != nil || !context.isEmpty || status.mark != nil || number != nil {
                    HStack(spacing: Space.s) {
                        if let mark = status.mark { StatusLabel(mark: mark.0, text: mark.1, size: 11) }
                        // A project is named by its mark and name, wherever it is named.
                        if let project {
                            HStack(spacing: 3) {
                                GlyphView(glyph: Wording.projectGlyph(project.origin), size: 11)
                                Text(project.name).lineLimit(1)
                            }
                            .foregroundStyle(.secondary)
                            .help(Wording.projectOrigin(project.origin))
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
        parts += context
        if let mark = status.mark { parts.append(mark.1.lowercased()) }
        parts.append("delivered " + (delivery.deliveredAt?.formatted(date: .abbreviated, time: .shortened) ?? "at an unknown time"))
        parts.append("by " + Wording.provider(delivery.provider))
        if let number = status.number { parts.append("delivery " + number) }
        if let request = delivery.request { parts.append("you asked: \(request.prefix(160))") }
        return parts.joined(separator: ", ")
    }
}
