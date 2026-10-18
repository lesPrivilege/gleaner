import GleanerCore
import SwiftUI

/// One project, to enter and resume: what it is and why, what arrived last, the joins to review,
/// then every work by the folder it is in, as the project's own folders lay them out.
struct ProjectOutline: View {
    @Environment(LibraryModel.self) private var model
    var project: Organization.Project

    /// Suggestions listed here; each file's detail shows its own.
    static let suggestionsShown = 5

    var body: some View {
        @Bindable var model = model
        let results = model.results
        let folders = Dictionary(grouping: results) { model.outlineFolder($0.work, in: project) }
        let order = folders.keys.sorted { a, b in a.isEmpty != b.isEmpty ? a.isEmpty : a.localizedStandardCompare(b) == .orderedAscending }
        let suggestions = model.organization.suggestions(in: project)
        VStack(spacing: 0) {
        FilterBar()
        List(selection: $model.selection) {
            Section { ProjectHeader(project: project) }
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions.prefix(Self.suggestionsShown)) { SuggestionView(suggestion: $0, compact: true) }
                    if suggestions.count > Self.suggestionsShown {
                        Text("\(suggestions.count - Self.suggestionsShown) more, each in its file’s detail.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Possibly one work")
                        .help("Gleaner never joins files by itself. Joined files show as versions of one work; nothing on disk changes.")
                }
            }
            ForEach(order, id: \.self) { folder in
                Section(folder.isEmpty ? "Top level" : folder) {
                    ForEach(folders[folder]!.sorted { $0.work.name.localizedStandardCompare($1.work.name) == .orderedAscending }) { result in
                        let row = ResultRow(result: result, file: model.file(in: result), delivery: model.delivery(in: result),
                                            project: nil, showFolder: false, status: model.rowStatus(result))
                            .tag(result.id)
                        if model.rowHandoff(result) != nil {
                            row.onDrag { model.dragItem(for: result) ?? NSItemProvider() }
                        } else {
                            row
                        }
                    }
                }
            }
        }
        .modifier(ListHandoff())
        .overlay {
            if project.works.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "tray",
                                       description: Text("Move work here from its detail: Move to Project…"))
            } else if results.isEmpty {
                ContentUnavailableView {
                    Label("No \(model.kind.map(Wording.kindName) ?? "works") here", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Show All Kinds") { model.kind = nil }
                }
            }
        }
        TroubleBar()
        }
    }
}

/// What the project is, why its work is in it, and where to pick up.
struct ProjectHeader: View {
    @Environment(LibraryModel.self) private var model
    var project: Organization.Project

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(project.name, systemImage: Wording.projectIcon(project.origin)).font(.title3.weight(.semibold))
                Spacer()
                if let folder = project.folder, Locator.stat(folder).kind == .directory {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                        .controlSize(.small)
                        .help("Show the project’s folder. Gleaner never changes anything in it.")
                }
            }
            Text(Wording.projectSummary(project)).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(project.combined, id: \.folder) { combined in
                HStack(spacing: 6) {
                    Text("Also shows \(combined.name), which you put inside it \(Wording.date(combined.correction.madeAt)).")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Show Apart") { Task { await model.undo(combined.correction) } }.controlSize(.mini)
                }
            }
            let recent = project.works.prefix(3)
            if !recent.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Latest:").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(recent)) { work in
                        Button(work.name) { model.select(work.deliveries[0]) }
                            .buttonStyle(.link).font(.caption).lineLimit(1)
                            .help("Delivered \(Wording.date(work.deliveries[0].deliveredAt))")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Two files that may be versions of one work, with Gleaner's reason and the person's answer.
struct SuggestionView: View {
    @Environment(LibraryModel.self) private var model
    var suggestion: Organization.Suggestion
    /// In a list of a project's suggestions, rather than one file's detail.
    var compact = false
    /// The work whose detail shows this, to say which side it is.
    var from: Work?

    var body: some View {
        let earlier = (suggestion.earlier as NSString).lastPathComponent, later = (suggestion.later as NSString).lastPathComponent
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let from, from.contains(suggestion.later) {
                    Text("**\(earlier)** may be an earlier version of this file.")
                } else if let from, from.contains(suggestion.earlier) {
                    Text("**\(later)** may be a later version of this file.")
                } else {
                    Text("**\(earlier)** → **\(later)**")
                }
            }
            .font(.callout)
            Text(Wording.suggestionReason(suggestion)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Same Work") { Task { await model.join(suggestion.earlier, suggestion.later) } }
                    .help("Show both files as versions of one work. Nothing on disk changes; you can undo this.")
                Button("Not the Same") { Task { await model.keepApart(suggestion.earlier, suggestion.later) } }
                    .help("Keep them apart. Gleaner won’t suggest this again.")
                if compact, let work = model.organization.work(containing: suggestion.later) {
                    Button("Show") { model.select(work.deliveries[0]) }.buttonStyle(.link)
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, compact ? 4 : 10)
        .padding(.horizontal, compact ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(compact ? Color.clear : Palette.selection.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay { if !compact { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.selection.opacity(0.3)) } }
        .accessibilityElement(children: .contain)
    }
}
