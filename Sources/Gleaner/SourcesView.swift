import GleanerCore
import SwiftUI

/// What Gleaner reads, the corrections the person made, and what it keeps: one place to see and
/// manage them, reached from the sidebar or ⌘,.
struct SourcesList: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        let page = Binding<SourcePage?>(get: { model.sourcePage }, set: { if let page = $0 { model.sourcePage = page } })
        List(selection: page) {
            Section("Agent logs") {
                ForEach(Provider.allCases, id: \.self) { provider in
                    let state = model.sources?[provider].map(Wording.source)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Wording.provider(provider)).fontWeight(.semibold)
                        if let state {
                            StatusLabel(mark: state.0, text: state.1).font(.caption)
                        } else {
                            Text(model.indexed ? "Not read" : "Reading…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(SourcePage.agent(provider))
                }
            }
            Section("Library") {
                Label("Your Corrections", systemImage: "arrow.uturn.backward")
                    .badge(model.correctionGroups.count + model.userProjects.count)
                    .tag(SourcePage.corrections)
                Label("Storage", systemImage: "internaldrive")
                    .tag(SourcePage.storage)
            }
        }
    }
}

struct SourcePageView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch model.sourcePage {
                case .agent(let provider): AgentSourcePage(provider: provider)
                case .corrections: CorrectionsPage()
                case .storage: StoragePage()
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

/// One agent's logs: where they are, how the last read went and why, what Gleaner takes from
/// them and what it leaves out.
struct AgentSourcePage: View {
    @Environment(LibraryModel.self) private var model
    var provider: Provider

    var body: some View {
        let folder = model.indexer.sources.folder(provider).path
        let source = model.sources?[provider]
        let deliveries = model.artifacts.flatMap(\.deliveries).filter { $0.provider == provider }
        let conversations = Set(deliveries.map(\.logPath)).count
        VStack(alignment: .leading, spacing: 6) {
            Text(Wording.provider(provider)).font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                Text((folder as NSString).abbreviatingWithTildeInPath).font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                    .controlSize(.small)
                    .disabled(Locator.stat(folder).kind != .directory)
            }
        }
        Panel(statement: Wording.sourceStatement(source, indexed: model.indexed, lastRead: model.lastRead)) {
            HStack {
                Button("Read Again") { model.reindex() }
                    .help("Read the logs again. Saved copies and your corrections stay.")
                if model.progress != nil { ProgressView().controlSize(.small) }
            }
        }
        Text("In the library: \(Wording.count(deliveries.count, "delivery", "deliveries")) from \(Wording.count(conversations, "conversation")).")
            .font(.callout)
        if let failure = model.indexFailure {
            StatusLabel(mark: .attention, text: failure).font(.callout)
        }
        if let source {
            ProblemList(title: "Logs with malformed lines", detail: "What they name was added and nothing was removed; they are read again next time.", paths: source.partialLogs)
            ProblemList(title: "Logs found shorter than before", detail: "They lost records, so nothing they no longer name is removed.", paths: source.shortenedLogs)
            ProblemList(title: "Logs that couldn’t be read", detail: "What they delivered stays as it was.", paths: source.failures)
            ProblemList(title: "Folders that couldn’t be listed", detail: "Their logs went unread; what they delivered stays.", paths: source.unlistedFolders)
            if !source.unknownRecordTypes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Record types Gleaner doesn’t know").font(.headline)
                    Text("The log format moved. Replies in these records may hold deliveries Gleaner doesn’t list, so an empty result isn’t proof there were none.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(source.unknownRecordTypes.sorted { $0.key < $1.key }.map { "\($0.key) (\($0.value))" }.joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("What Gleaner reads").font(.headline)
            ForEach(Wording.scope(provider), id: \.self) { line in
                Text("• " + line).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Text("What it leaves out").font(.headline).padding(.top, 6)
            ForEach(Wording.exclusions(provider), id: \.self) { line in
                Text("• " + line).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Paths behind one kind of read problem, each to look at in Finder.
struct ProblemList: View {
    var title: String
    var detail: String
    var paths: [String]

    var body: some View {
        if !paths.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) (\(paths.count))").font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                ForEach(paths, id: \.self) { entry in
                    // A failure reads "path: reason"; the path is what Finder can show.
                    let path = String(entry.split(separator: ":", maxSplits: 1).first ?? Substring(entry))
                    HStack(spacing: 6) {
                        Text((entry as NSString).abbreviatingWithTildeInPath).font(.system(.caption, design: .monospaced))
                            .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                            .controlSize(.mini)
                            .disabled(Locator.stat(path).kind == .missing)
                    }
                }
            }
        }
    }
}

/// Every decision the person made about how the library is organized, each to undo, and the
/// projects they made.
struct CorrectionsPage: View {
    @Environment(LibraryModel.self) private var model
    @State private var confirming = false
    @State private var removing: Organization.Project?

    var body: some View {
        Text("Your Corrections").font(.title2.weight(.semibold))
        Text("Where you moved work, which files you joined or kept apart, and which projects you combined. Gleaner keeps them apart from what it found in the logs: reading the logs again never undoes them, and undoing one never touches a file.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if model.corrections.isEmpty && model.userProjects.isEmpty {
            Text("No corrections yet. Gleaner shows the library as it found it.").font(.callout)
        }
        ForEach(model.correctionGroups, id: \.first!.id) { group in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.describe(group)).font(.callout)
                    Text(Wording.date(group[0].madeAt)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Undo") { Task { await model.undo(group) } }.controlSize(.small)
            }
            Divider()
        }
        if !model.userProjects.isEmpty {
            Text("Projects you made").font(.headline).padding(.top, 6)
            ForEach(model.userProjects) { project in
                let shown = model.organization.project(project.key)
                HStack {
                    Text(project.name).font(.callout)
                    Text(Wording.count(shown?.works.count ?? 0, "work")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let shown {
                        Button("Go to Project") { model.place = .project(shown.key) }.controlSize(.small)
                        Button("Delete…") { removing = shown }.controlSize(.small)
                    }
                }
            }
        }
        Color.clear.frame(height: 0)
            .confirmationDialog("Delete “\(removing?.name ?? "")”?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("Delete Project", role: .destructive) { if let removing { Task { await model.remove(removing) } } }
            } message: {
                Text("Its work goes back to the projects Gleaner found it in, and the moves into it are removed. No file is touched.")
            }
        if !model.corrections.isEmpty || !model.userProjects.isEmpty {
            Button("Undo All Corrections…", role: .destructive) { confirming = true }
                .padding(.top, 8)
                .confirmationDialog("Undo every correction?", isPresented: $confirming) {
                    Button("Undo All", role: .destructive) { Task { await model.undoAllCorrections() } }
                } message: {
                    Text("Gleaner shows the library as it found it, and removes the projects you made. Saved copies, deliveries and files are not touched.")
                }
        }
        if let failure = model.correctionFailure {
            StatusLabel(mark: .attention, text: failure).font(.callout)
        }
    }
}

/// What Gleaner keeps: saved copies, and disposable hand-off copies.
struct StoragePage: View {
    @Environment(LibraryModel.self) private var model
    @State private var usage: (saved: Int64, handoff: Int64)?

    var body: some View {
        Text("Storage").font(.title2.weight(.semibold))
        LabeledContent("Saved copies") {
            HStack {
                Text(size(usage?.saved))
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.indexer.store.objects]) }
            }
        }
        Text("The delivered bytes Gleaner keeps so a version survives later edits. Kept until you remove them; reading the logs again or clearing hand-off copies never does.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        LabeledContent("Hand-off copies") {
            HStack {
                Text(size(usage?.handoff))
                Button("Clear") {
                    model.clearHandoffCopies(keeping: .general)
                    refresh()
                }
                .help("Remove the read-only copies made for dragging and opening, except the one on the clipboard.")
            }
        }
        Text("Read-only copies prepared for dragging and opening. Safe to clear; Gleaner makes them again when needed.")
            .font(.caption).foregroundStyle(.secondary)
            .task { refresh() }
    }

    func refresh() {
        Task {
            let model = model
            usage = await Task.detached { model.storageUsage() }.value
        }
    }

    func size(_ bytes: Int64?) -> String {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…"
    }
}
