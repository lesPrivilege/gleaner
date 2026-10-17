import GleanerCore
import SwiftUI

/// What Gleaner reads and what it keeps. Nothing here changes how deliveries are found.
struct SettingsView: View {
    @Environment(LibraryModel.self) private var model
    @State private var usage: (saved: Int64, handoff: Int64)?

    var body: some View {
        Form {
            Section("Reads") {
                ForEach(Provider.allCases, id: \.self) { provider in
                    let source = model.sources?[provider]
                    LabeledContent {
                        if let source {
                            let state = Wording.source(source)
                            StatusLabel(mark: state.0, text: state.1)
                        } else {
                            Text(model.indexed ? "Not read" : "Reading…").foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(Wording.provider(provider))
                        Text((model.indexer.sources.folder(provider).path as NSString).abbreviatingWithTildeInPath)
                        if let detail = source.flatMap(Wording.sourceDetail) {
                            Text(detail)
                        }
                    }
                }
                if let failure = model.indexFailure {
                    StatusLabel(mark: .attention, text: failure)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Gleaner watches these agent log folders while it is open, and reads only the files their replies name.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Read Again") { model.reindex() }
                }
            }
            Section("Keeps") {
                LabeledContent("Saved copies") {
                    HStack {
                        Text(size(usage?.saved))
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.indexer.store.objects]) }
                    }
                }
                Text("The delivered bytes Gleaner keeps so a version survives later edits. Kept until you remove them.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Hand-off copies") {
                    HStack {
                        Text(size(usage?.handoff))
                        Button("Clear") {
                            model.clearHandoffCopies()
                            refresh()
                        }
                    }
                }
                Text("Read-only copies prepared for dragging and opening. Safe to clear; Gleaner makes them again when needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .task { refresh() }
    }

    func refresh() {
        Task {
            let model = model
            usage = await Task.detached { await model.storageUsage() }.value
        }
    }

    func size(_ bytes: Int64?) -> String {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…"
    }
}
