import GleanerCore
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
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
        .toolbar {
            ToolbarItem(placement: .status) {
                HStack(spacing: 8) {
                    if let progress = model.progress {
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                            .frame(width: 120)
                        Text("Reading \(progress.total) logs…")
                    } else {
                        Text(model.status)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
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
        List(selection: $model.selection) {
            ForEach(results) { result in
                ResultRow(result: result, showProject: model.project == nil,
                          showFolder: repeated.contains(result.artifact.name))
                    .tag(result.id)
            }
        }
        .onCopyCommand {
            guard let url = model.selectedHandoffURL, let provider = NSItemProvider(contentsOf: url) else { return [] }
            return [provider]
        }
        .safeAreaInset(edge: .top) { filters }
        .overlay { emptyState(results) }
    }

    var filters: some View {
        @Bindable var model = model
        return VStack(spacing: 8) {
            Picker("Project", selection: $model.project) {
                Text("All projects").tag(String?.none)
                Divider()
                ForEach(model.projects, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Kind", selection: $model.kind) {
                Text("All").tag(Artifact.Kind?.none)
                Text("Video").tag(Artifact.Kind?.some(.video))
                Text("Web").tag(Artifact.Kind?.some(.web))
                Text("Docs").tag(Artifact.Kind?.some(.document))
                Text("Images").tag(Artifact.Kind?.some(.image))
                Text("Builds").tag(Artifact.Kind?.some(.build))
                Text("Folders").tag(Artifact.Kind?.some(.folder))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
    var showProject: Bool
    var showFolder: Bool

    var body: some View {
        let artifact = result.artifact
        let hit = artifact.deliveries[result.deliveryIndex]
        let context = [showProject ? artifact.project : nil,
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
                if !FileManager.default.fileExists(atPath: artifact.path) {
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
    }
}
