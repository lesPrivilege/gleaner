import GleanerCore
import SwiftUI

/// What Gleaner reads, the corrections the person made, and what it keeps, laid out as System
/// Settings lays out a pane: reached from the sidebar or ⌘,.
struct SourcesList: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        let page = Binding<SourcePage?>(get: { model.sourcePage }, set: { if let page = $0 { model.sourcePage = page } })
        List(selection: page) {
            Section("Agents") {
                ForEach(Provider.allCases, id: \.self) { provider in
                    let state = model.sources?[provider].map(Wording.source) ?? (model.indexed ? (.dashed, "Not read") : (.running, "Reading…"))
                    HStack(spacing: Space.s + 2) {
                        ProviderMark(provider: provider, size: 28, color: true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Wording.provider(provider)).fontWeight(.semibold)
                            StatusLabel(mark: state.0, text: state.1, size: 11).font(.caption)
                        }
                    }
                    .padding(.vertical, Space.xs)
                    .tag(SourcePage.agent(provider))
                }
            }
            Section("Library") {
                GlyphLabel(title: "Corrections", glyph: .person, size: 16)
                    .badge(model.correctionGroups.count + model.userProjects.count)
                    .tag(SourcePage.corrections)
                GlyphLabel(title: "Storage", glyph: .database, size: 16)
                    .tag(SourcePage.storage)
            }
        }
    }
}

struct SourcePageView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        Group {
            switch model.sourcePage {
            case .agent(let provider): AgentSourcePage(provider: provider)
            case .corrections: CorrectionsPage()
            case .storage: StoragePage()
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }
}

/// One agent's logs: where they are, how the last read went, what Gleaner takes from them and
/// what it leaves out.
struct AgentSourcePage: View {
    @Environment(LibraryModel.self) private var model
    var provider: Provider

    var body: some View {
        let folder = model.indexer.sources.folder(provider).path
        let source = model.sources?[provider]
        let statement = Wording.sourceStatement(source, indexed: model.indexed)
        let deliveries = model.artifacts.flatMap(\.deliveries).filter { $0.provider == provider }
        let conversations = Set(deliveries.map(\.logPath)).count
        Form {
            Section {
                HStack(spacing: Space.m) {
                    ProviderMark(provider: provider, size: 44, color: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Wording.provider(provider)).font(.title3.weight(.semibold))
                        Text(Wording.tilde(folder)).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                        .disabled(Locator.stat(folder).kind != .directory)
                }
                .padding(.vertical, Space.xs)
            }
            Section {
                LabeledContent("Status") {
                    HStack(spacing: Space.xs) {
                        StatusLabel(mark: statement.mark, text: statement.title)
                        InfoButton(text: statement.detail)
                    }
                }
                if let lastRead = model.lastRead { LabeledContent("Last Read", value: Wording.date(lastRead)) }
                LabeledContent("Deliveries") {
                    Text("\(deliveries.count) from \(Wording.count(conversations, "conversation"))").monospacedDigit()
                }
                if let failure = model.indexFailure {
                    StatusLabel(mark: .attention, text: failure).font(.callout)
                }
            } footer: {
                HStack {
                    Spacer()
                    if model.progress != nil { ProgressView().controlSize(.small) }
                    Button("Read Again") { model.reindex() }
                        .help("Read every log again. Saved copies and corrections stay.")
                }
            }
            if let source {
                ProblemSection(title: "Malformed Lines", footer: "What they name was added; they’re read again next time.", paths: source.partialLogs)
                ProblemSection(title: "Shorter Than Before", footer: "They lost records, so nothing they stopped naming is removed.", paths: source.shortenedLogs)
                ProblemSection(title: "Unreadable Logs", footer: "What they delivered stays as it was.", paths: source.failures)
                ProblemSection(title: "Unlisted Folders", footer: "Their logs went unread; what they delivered stays.", paths: source.unlistedFolders)
                if !source.unknownRecordTypes.isEmpty {
                    Section {
                        ForEach(source.unknownRecordTypes.sorted { $0.key < $1.key }, id: \.key) { type, count in
                            LabeledContent { Text("\(count)").monospacedDigit() } label: {
                                Text(type).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                    } header: {
                        Text("Unknown Record Types")
                    } footer: {
                        Text("The log format moved. These records may hold deliveries Gleaner doesn’t list.")
                    }
                }
            }
            Section("Reads") {
                ForEach(Wording.reads(provider), id: \.0) { label, value in
                    LabeledContent(label, value: value)
                }
            }
            Section("Skips") {
                ForEach(Wording.skips(provider), id: \.self) { Text($0) }
            }
        }
    }
}

/// Paths behind one kind of read problem, each to look at in Finder.
struct ProblemSection: View {
    var title: String
    var footer: String
    var paths: [String]

    var body: some View {
        if !paths.isEmpty {
            Section {
                ForEach(paths, id: \.self) { entry in
                    // A failure reads "path: reason"; the path is what Finder can show.
                    let path = String(entry.split(separator: ":", maxSplits: 1).first ?? Substring(entry))
                    HStack(spacing: Space.s) {
                        Text(Wording.tilde(entry)).font(.system(.callout, design: .monospaced))
                            .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        Spacer(minLength: Space.s)
                        Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                            .controlSize(.small)
                            .disabled(Locator.stat(path).kind == .missing)
                    }
                }
            } header: {
                HStack(spacing: Space.xs + 2) {
                    GlyphView(glyph: .warning, size: 12).foregroundStyle(Palette.attention)
                    Text("\(title) (\(paths.count))")
                }
            } footer: {
                Text(footer)
            }
        }
    }
}

/// Every decision the person made about how the library is organized, newest first, each to undo,
/// and the projects they made.
struct CorrectionsPage: View {
    @Environment(LibraryModel.self) private var model
    @State private var confirming = false
    @State private var removing: Organization.Project?

    var body: some View {
        Form {
            Section {
                if model.corrections.isEmpty {
                    Text("None yet. The library is as Gleaner found it.").foregroundStyle(.secondary)
                }
                ForEach(model.correctionGroups, id: \.first!.id) { group in
                    HStack(spacing: Space.s + 2) {
                        GlyphView(glyph: glyph(group[0].kind), size: 16).foregroundStyle(Palette.mark).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.describe(group)).lineLimit(2).truncationMode(.middle)
                            Text(Wording.date(group[0].madeAt)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Space.s)
                        Button("Undo") { Task { await model.undo(group) } }
                            .controlSize(.small)
                            .accessibilityLabel("Undo: \(model.describe(group))")
                    }
                }
            } header: {
                Text("Corrections, Newest First")
            } footer: {
                Text("Corrections never change a file, and reading the logs again keeps them.")
            }
            if !model.userProjects.isEmpty {
                Section("Your Projects") {
                    ForEach(model.userProjects) { project in
                        let shown = model.organization.project(project.key)
                        HStack(spacing: Space.s + 2) {
                            GlyphView(glyph: .person, size: 16).foregroundStyle(Palette.mark).frame(width: 20)
                            Text(project.name)
                            Text(Wording.count(shown?.works.count ?? 0, "work")).foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            if let shown {
                                Button("Go to Project") { model.place = .project(shown.key) }.controlSize(.small)
                                Button("Delete…") { removing = shown }.controlSize(.small)
                            }
                        }
                    }
                }
            }
            if !model.corrections.isEmpty || !model.userProjects.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        Button("Undo All Corrections…", role: .destructive) { confirming = true }
                    }
                }
            }
            if let failure = model.correctionFailure {
                StatusLabel(mark: .attention, text: failure).font(.callout)
            }
        }
        .confirmationDialog("Delete “\(removing?.name ?? "")”?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Delete Project", role: .destructive) { if let removing { Task { await model.remove(removing) } } }
        } message: {
            Text("Its work goes back where Gleaner found it. No file changes.")
        }
        .confirmationDialog("Undo every correction?", isPresented: $confirming) {
            Button("Undo All", role: .destructive) { Task { await model.undoAllCorrections() } }
        } message: {
            Text("The library returns to how Gleaner found it, and your projects are removed. Files and saved copies stay.")
        }
    }

    func glyph(_ kind: Correction.Kind) -> Glyph {
        switch kind {
        case .project: .folder
        case .combine: .branch
        case .sameWork: .merge
        case .notSameWork: .rejected
        }
    }
}

/// What Gleaner keeps: saved copies, and disposable hand-off copies.
struct StoragePage: View {
    @Environment(LibraryModel.self) private var model
    @State private var usage: (saved: Int64, handoff: Int64)?

    var body: some View {
        Form {
            Section {
                LabeledContent("Saved Copies") {
                    HStack {
                        Text(size(usage?.saved)).monospacedDigit()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.indexer.store.objects]) }
                            .controlSize(.small)
                    }
                }
            } footer: {
                Text("Delivered bytes, kept so each version survives later edits. Kept until you remove them.")
            }
            Section {
                LabeledContent("Hand-Off Copies") {
                    HStack {
                        Text(size(usage?.handoff)).monospacedDigit()
                        Button("Clear") {
                            model.clearHandoffCopies(keeping: .general)
                            refresh()
                        }
                        .controlSize(.small)
                        .help("Remove the read-only copies made for dragging and opening, except the one on the clipboard")
                    }
                }
            } footer: {
                Text("Read-only copies for dragging and opening. Gleaner makes them again when needed.")
            }
        }
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
