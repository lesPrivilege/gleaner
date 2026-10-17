import GleanerCore
import QuickLook
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryModel.self) private var model
    // Search and filters survive relaunch; selection does not, since results may have changed.
    @SceneStorage("query") private var savedQuery = ""
    @SceneStorage("kind") private var savedKind = ""
    @SceneStorage("project") private var savedProject = ""

    var body: some View {
        @Bindable var model = model
        // Read here so the view follows every change to what the selection hands over.
        let quickLookURL = model.quickLookURL
        NavigationSplitView {
            ResultsList()
                .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 460)
        } detail: {
            if let result = model.selected {
                DetailView(result: result)
            } else if !model.artifacts.isEmpty {
                ContentUnavailableView(
                    "Pick a delivered file",
                    systemImage: "tray.full",
                    description: Text("Search for what you asked an agent to make. Gleaner lists only files an agent named in a reply to you."))
            }
        }
        .searchable(text: $model.query, placement: .sidebar, prompt: "What you asked for, file name, project…")
        .quickLookPreview(Binding(get: { quickLookURL }, set: { model.isQuickLookOpen = $0 != nil }))
        .onChange(of: model.selectedHandoffURL) { if model.selectedHandoffURL == nil { model.isQuickLookOpen = false } }
        .onAppear {
            model.query = savedQuery
            model.kind = Artifact.Kind(rawValue: savedKind)
            model.project = model.projects.contains { $0.projectFolder == savedProject } ? savedProject : nil
        }
        .onChange(of: model.query) { savedQuery = model.query }
        .onChange(of: model.kind) { savedKind = model.kind?.rawValue ?? "" }
        .onChange(of: model.project) { savedProject = model.project ?? "" }
        .navigationSubtitle(model.progress.map { "Reading logs… \($0.done) of \($0.total)" } ?? model.status)
        .toolbar {
            ToolbarItem {
                Button("Check for New Deliveries", systemImage: "arrow.clockwise") { model.reindex() }
                    .help("Read new agent replies now (⌘R). Gleaner also watches the log folders while it is open.")
            }
        }
    }
}

struct ResultsList: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let results = model.results
        let repeated = Set(Dictionary(grouping: results, by: \.artifact.name).filter { $0.value.count > 1 }.keys)
        // Filters sit above the list, not over it: rows never scroll under the glass controls.
        VStack(spacing: 0) {
            filters
            List(selection: $model.selection) {
                ForEach(results) { result in
                    ResultRow(result: result, project: model.project == nil ? model.projectName(result.artifact) : nil,
                              showFolder: repeated.contains(result.artifact.name),
                              onDisk: !model.missing.contains(result.artifact.path))
                        .tag(result.id)
                        .onDrag { model.dragItem(for: result) }
                }
            }
            .contextMenu(forSelectionType: Artifact.ID.self) { ids in
                if let id = ids.first, let artifact = model.artifacts.first(where: { $0.id == id }) {
                    if id == model.selection {
                        Button("Open Verified Copy") { model.openSelected() }.disabled(model.selectedHandoffURL == nil)
                        Button("Quick Look") { model.toggleQuickLook() }.disabled(model.selectedHandoffURL == nil)
                        Divider()
                    }
                    Button(model.missing.contains(artifact.path) ? "Show Folder in Finder" : "Show in Finder") { model.reveal(artifact) }
                    Button("Copy Path") { model.copyPath(artifact) }
                    Divider()
                    Button("Show Only \(model.projectName(artifact))") { model.project = artifact.projectFolder }
                }
            }
            .onKeyPress(.space) {
                guard model.selectedHandoffURL != nil || model.isQuickLookOpen else { return .ignored }
                model.toggleQuickLook()
                return .handled
            }
            .onCopyCommand {
                guard let url = model.selectedHandoffURL, let provider = NSItemProvider(contentsOf: url) else { return [] }
                return [provider]
            }
            .overlay { emptyState(results) }
        }
    }

    var filters: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Picker("Project", selection: $model.project) {
                Text("All projects").tag(String?.none)
                Divider()
                ForEach(model.projects) { Text(model.projectName($0)).tag(String?.some($0.projectFolder)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
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

    @ViewBuilder
    func emptyState(_ results: [SearchResult]) -> some View {
        if model.artifacts.isEmpty {
            let folders = model.logFolders
            if !model.indexed {
                ContentUnavailableView("Reading agent logs…", systemImage: "hourglass",
                                       description: Text("The first read takes a moment. Results appear when it finishes."))
            } else if folders.found.isEmpty {
                ContentUnavailableView {
                    Label("No agent logs found", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Gleaner reads Claude Code and Codex logs. It looked in:\n"
                         + folders.missing.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n"))
                }
            } else {
                ContentUnavailableView("No delivered files yet", systemImage: "tray",
                                       description: Text("When an agent names a file in a reply to you, it appears here."))
            }
        } else if results.isEmpty {
            ContentUnavailableView {
                Label("No matches", systemImage: "magnifyingglass")
            } description: {
                Text("Every word has to appear in one delivery: your request, the reply, the file name, or the project.")
            } actions: {
                Button("Clear Search and Filters") { model.clearFilters() }
            }
        }
    }
}

struct TypeBadge: View {
    var artifact: Artifact

    var body: some View {
        Text(Wording.kindLabel(artifact.kind, path: artifact.path))
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .frame(minWidth: 40, minHeight: 18)
            .padding(.horizontal, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct ResultRow: View {
    var result: SearchResult
    /// The project as shown, or nil when the list is filtered to one.
    var project: String?
    var showFolder: Bool
    var onDisk: Bool

    var body: some View {
        let artifact = result.artifact
        let hit = artifact.deliveries[result.deliveryIndex]
        let context = [project,
                       artifact.inWorktree ? artifact.place : nil,
                       showFolder ? artifact.folder : nil].compactMap { $0 }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TypeBadge(artifact: artifact)
                Text(artifact.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            }
            if !context.isEmpty {
                Text(context.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if let request = hit.request {
                Text("“\(request)”").font(.callout).lineLimit(2)
            }
            HStack(spacing: 10) {
                if !onDisk {
                    StatusLabel(mark: .dashed, text: "Not on disk")
                }
                Text(hit.deliveredAt?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date")
                    .foregroundStyle(.secondary)
                if artifact.deliveries.count > 1 {
                    Text("Delivery \(hit.number) of \(artifact.latest.number)").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(context: context, hit: hit))
    }

    /// One sentence VoiceOver reads for the row, in the order the eye reads it.
    func spoken(context: [String], hit: Delivery) -> String {
        let artifact = result.artifact
        var parts = [artifact.name] + context
        if !onDisk { parts.append("not on disk") }
        parts.append("delivered " + (hit.deliveredAt?.formatted(date: .abbreviated, time: .omitted) ?? "on an unknown date"))
        if artifact.deliveries.count > 1 { parts.append("delivery \(hit.number) of \(artifact.latest.number)") }
        if let request = hit.request { parts.append("you asked: \(request.prefix(160))") }
        return parts.joined(separator: ", ")
    }
}
