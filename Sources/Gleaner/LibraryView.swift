import GleanerCore
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            ResultsList()
                .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 420)
        } detail: {
            if let result = model.selected {
                DetailView(result: result)
            } else {
                ContentUnavailableView(
                    "Pick a delivery",
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
                    .help("Read new agent replies now (⌘R). Gleaner also watches the log folders.")
            }
        }
    }
}

struct ResultsList: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let results = model.results
        List(selection: $model.selection) {
            ForEach(results) { result in
                ResultRow(result: result).tag(result.id)
            }
        }
        .safeAreaInset(edge: .top) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .overlay {
            if results.isEmpty && !model.artifacts.isEmpty {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }
}

struct TypeBadge: View {
    var artifact: Artifact

    var body: some View {
        Text(Wording.kindLabel(artifact.kind, path: artifact.path))
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .frame(minWidth: 40, minHeight: 18)
            .padding(.horizontal, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct ResultRow: View {
    var result: SearchResult

    var body: some View {
        let artifact = result.artifact
        let hit = artifact.deliveries[result.deliveryIndex]
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                TypeBadge(artifact: artifact)
                Text(artifact.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            }
            Text("\(artifact.project) · \(artifact.place) · \(artifact.folder)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if let request = hit.request {
                Text("“\(request)”").font(.callout).lineLimit(2)
            }
            HStack(spacing: 10) {
                if !FileManager.default.fileExists(atPath: artifact.path) {
                    StatusLabel(mark: .dashed, text: "Not on disk")
                }
                Text("Delivered \(hit.deliveredAt?.formatted(date: .abbreviated, time: .omitted) ?? "—")")
                    .foregroundStyle(.secondary)
                if result.deliveryIndex > 0 {
                    Text("Matched delivery \(hit.number) of \(artifact.latest.number)").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 6)
    }
}
