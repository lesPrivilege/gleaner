import GleanerCore
import QuickLook
import SwiftUI

/// The library window: where you are (every delivery, a project, or the sources), what is there,
/// and the selected work.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var model
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
        .searchable(text: $model.query, placement: .toolbar, prompt: "What you asked for, file name, project…")
        .quickLookPreview(Binding(get: { quickLookURL }, set: { model.isQuickLookOpen = $0 != nil }))
        .onChange(of: model.selectedHandoffURL) { if model.selectedHandoffURL == nil { model.isQuickLookOpen = false } }
        .onAppear(perform: restore)
        .onChange(of: model.query) { savedQuery = model.query }
        .onChange(of: model.kind) { savedKind = model.kind?.rawValue ?? "" }
        .onChange(of: model.place) { savedPlace = Self.encode(model.place) }
        .navigationSubtitle(model.progress.map { "Reading logs… \($0.done) of \($0.total)" } ?? model.status)
        .toolbar {
            ToolbarItem {
                Button("Check for New Deliveries", systemImage: "arrow.clockwise") { model.reindex() }
                    .help("Read new agent replies now (⌘R). Gleaner also watches the log folders while it is open.")
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
            Label("All Deliveries", systemImage: "tray.full")
                .badge(model.organization.works.count)
                .tag(Place.all)
            Section("Projects") {
                ForEach(model.projects) { project in
                    Label { Text(project.name).lineLimit(1).truncationMode(.middle) } icon: { Image(systemName: Wording.projectIcon(project.origin)) }
                        .badge(project.works.count)
                        .tag(Place.project(project.key))
                        .help(Wording.projectSummary(project))
                        .contextMenu { menu(project) }
                }
            }
            Section("Library") {
                Label {
                    Text("Sources")
                } icon: {
                    Image(systemName: model.logTrouble == nil ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle")
                        .foregroundStyle(model.logTrouble == nil ? Color.secondary : Palette.attention)
                }
                .tag(Place.sources)
                .help(model.logTrouble ?? "What Gleaner reads, your corrections, and what it keeps")
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
            Text("Its work goes back to the projects Gleaner found it in. No file is touched.")
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
            ContentUnavailableView(
                "Pick a delivered file",
                systemImage: "tray.full",
                description: Text("Search for what you asked an agent to make, or open a project. Gleaner lists only files an agent named in a reply to you."))
        }
    }
}

/// Handing over and opening the selection from a list, shared by the results and the outline.
struct ListHandoff: ViewModifier {
    @Environment(LibraryModel.self) private var model

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: Work.ID.self) { ids in
                if let id = ids.first, let work = model.organization.work(containing: id) {
                    // The file the row shows and drags, which may be an earlier one of the work's.
                    let artifact = model.result(for: work).map(model.file(in:)) ?? work.latest
                    if id == model.selection {
                        Button("Open Verified Copy") { model.openSelected() }.disabled(model.selectedHandoffURL == nil)
                        Button("Quick Look") { model.toggleQuickLook() }.disabled(model.selectedHandoffURL == nil)
                        Divider()
                    }
                    Button(model.missing.contains(artifact.path) ? "Show Folder in Finder" : "Show in Finder") { model.reveal(artifact) }
                    Button("Copy Path") { model.copyPath(artifact) }
                    Divider()
                    Button("Go to \(model.projectName(work))") { model.place = .project(work.project); model.selection = work.id }
                }
            }
            .onKeyPress(.space) {
                guard model.selectedHandoffURL != nil || model.isQuickLookOpen else { return .ignored }
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
            List(selection: $model.selection) {
                ForEach(results) { result in
                    let file = model.file(in: result)
                    let row = ResultRow(result: result, file: file, delivery: model.delivery(in: result),
                                        project: model.currentProject == nil ? model.projectName(result.work) : nil,
                                        showFolder: repeated.contains(result.work.name), status: model.rowStatus(result))
                        .tag(result.id)
                    // A row with nothing to hand over starts no drag, rather than one that fails at drop.
                    if model.rowHandoff(result) != nil {
                        row.onDrag { model.dragItem(for: result) ?? NSItemProvider() }
                    } else {
                        row
                    }
                }
            }
            .modifier(ListHandoff())
            .overlay { emptyState(results) }
            TroubleBar()
        }
    }

    @ViewBuilder
    func emptyState(_ results: [SearchResult]) -> some View {
        if model.artifacts.isEmpty {
            if !model.indexed {
                ContentUnavailableView("Reading agent logs…", systemImage: "hourglass",
                                       description: Text("The first read takes a moment. Results appear when it finishes."))
            } else if model.canReadAgain, let trouble = model.logTrouble {
                ContentUnavailableView {
                    Label("Gleaner couldn’t read every agent log", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(trouble)
                } actions: {
                    Button("Try Again") { model.reindex() }
                }
            } else if model.sources?.values.allSatisfy({ $0.folder == .absent }) == true {
                ContentUnavailableView {
                    Label("No agent logs found", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Gleaner reads Claude Code and Codex logs. It looked in:\n"
                         + model.indexer.sources.watchedDirectories.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n"))
                }
            } else {
                ContentUnavailableView("No delivered files yet", systemImage: "tray",
                                       description: Text("When an agent names a file in a reply to you, it appears here."
                                                         + (model.logTrouble.map { "\n\n" + $0 } ?? "")))
            }
        } else if results.isEmpty {
            ContentUnavailableView {
                Label("No matches", systemImage: "magnifyingglass")
            } description: {
                Text(model.currentProject == nil
                     ? "Every word has to appear in one delivery: your request, the reply, the file name, or the project."
                     : "Every word has to appear in one delivery of this project: your request, the reply, the file name.")
            } actions: {
                Button("Clear Search and Filters") { model.clearFilters() }
                if model.currentProject != nil { Button("Search All Deliveries") { model.place = .all } }
            }
        }
    }
}

/// The project shown, and the kind filter, above a list.
struct FilterBar: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            if let project = model.currentProject {
                Label(project.name, systemImage: Wording.projectIcon(project.origin))
                    .font(.callout.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Picker("Kind", selection: $model.kind) {
                Text("All kinds").tag(Artifact.Kind?.none)
                Divider()
                ForEach(Artifact.Kind.allCases, id: \.self) { kind in
                    Text(Wording.kindName(kind)).tag(Artifact.Kind?.some(kind))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                Spacer(minLength: 8)
                if model.canReadAgain {
                    Button("Try Again") { model.reindex() }
                        .controlSize(.small)
                        .help("Read the agent logs again. Sources shows each one.")
                }
                Button("Sources") { model.place = .sources }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct TypeBadge: View {
    var artifact: Artifact

    var body: some View {
        // Widens for a long extension rather than cutting it.
        Text(Wording.kindLabel(artifact.kind, path: artifact.path))
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .fixedSize()
            .frame(minWidth: 40, minHeight: 18)
            .padding(.horizontal, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct ResultRow: View {
    var result: SearchResult
    /// The file the row shows and hands over: the one holding `delivery`.
    var file: Artifact
    /// The delivery the row shows and hands over: the one chosen in the detail for the selected
    /// row, the matched one for any other.
    var delivery: Delivery
    /// The project as shown, or nil when the list is one project's.
    var project: String?
    var showFolder: Bool
    /// What the row says beside the date (`LibraryModel.rowStatus`).
    var status: (mark: (Mark, String)?, number: String?)

    var body: some View {
        let work = result.work
        // The work by its newest file's name; the context says when the row shows another of its files.
        let context = [project,
                       file.inWorktree ? file.place : nil,
                       showFolder ? file.folder : nil,
                       work.files.count > 1 ? "\(work.files.count) files" + (file.path == work.latest.path ? "" : ", showing \(file.name)") : nil,
        ].compactMap { $0 }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TypeBadge(artifact: work.latest)
                Text(work.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            }
            if !context.isEmpty {
                Text(context.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if let request = delivery.request {
                Text("“\(request)”").font(.callout).lineLimit(2)
            }
            HStack(spacing: 10) {
                if let mark = status.mark {
                    StatusLabel(mark: mark.0, text: mark.1)
                }
                Text(delivery.deliveredAt?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date")
                    .foregroundStyle(.secondary)
                if let number = status.number {
                    Text(number).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(context: context))
    }

    /// One sentence VoiceOver reads for the row, in the order the eye reads it.
    func spoken(context: [String]) -> String {
        var parts = [result.work.name] + context
        if let mark = status.mark { parts.append(mark.1.lowercased()) }
        parts.append("delivered " + (delivery.deliveredAt?.formatted(date: .abbreviated, time: .omitted) ?? "on an unknown date"))
        if let number = status.number { parts.append(number.lowercased()) }
        if let request = delivery.request { parts.append("you asked: \(request.prefix(160))") }
        return parts.joined(separator: ", ")
    }
}
