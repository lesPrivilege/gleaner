import GleanerCore
import SwiftUI

/// What Gleaner reads and what it keeps. Nothing here changes how deliveries are found.
struct SettingsView: View {
    @Environment(LibraryModel.self) private var model
    @State private var usage: (saved: Int64, handoff: Int64)?

    var body: some View {
        Form {
            Section("Reads") {
                ForEach(model.indexer.sources.watchedDirectories, id: \.self) { path in
                    LabeledContent((path as NSString).abbreviatingWithTildeInPath) {
                        Text(FileManager.default.fileExists(atPath: path) ? "Found" : "Not found").foregroundStyle(.secondary)
                    }
                }
                Text("Gleaner watches these agent log folders while it is open, and reads only the files their replies name.")
                    .font(.caption).foregroundStyle(.secondary)
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
