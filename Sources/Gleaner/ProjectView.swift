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
                    Label { Text("Possibly one work · waiting on you") } icon: { GlyphView(glyph: .awaiting, size: 12).foregroundStyle(Palette.awaiting) }
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
                EmptyState(title: "Nothing here yet", glyph: .person, description: "Move work here from its detail: Move to Project…")
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
                GlyphLabel(title: project.name, glyph: Wording.projectGlyph(project.origin), size: 20).font(.title3.weight(.semibold))
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
                    Button("Show Apart") { Task { await model.undo(combined.correction, following: false) } }.controlSize(.mini)
                }
            }
            let recent = project.works.prefix(3)
            if !recent.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Delivered last:").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(recent)) { work in
                        LinkButton(title: work.name) { model.select(work.deliveries[0]) }
                            .font(.caption).lineLimit(1)
                            .help("Delivery \(work.deliveries[0].number), \(Wording.date(work.deliveries[0].deliveredAt))")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Two files that may be versions of one work, with Gleaner's reason and the person's answer. It
/// waits on the person, so it carries the one accent and the awaiting mark, and says who says so
/// and that nothing is in effect yet; its dashed outline is the "not in effect" of the relation
/// grammar (`kit/design/foundations/standing.md`). What a choice does is written, not hovered.
struct SuggestionView: View {
    @Environment(LibraryModel.self) private var model
    var suggestion: Organization.Suggestion
    /// In a list of a project's suggestions, rather than one file's detail.
    var compact = false
    /// The work whose detail shows this, to say which side it is.
    var from: Work?

    var body: some View {
        let earlier = (suggestion.earlier as NSString).lastPathComponent, later = (suggestion.later as NSString).lastPathComponent
        HStack(alignment: .top, spacing: Space.m - 2) {
            GlyphView(glyph: .awaiting, size: compact ? 16 : 20).foregroundStyle(Palette.awaiting).padding(.top, 1)
            VStack(alignment: .leading, spacing: Space.xs + 2) {
                Text("Gleaner suggests · not joined")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.awaiting)
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
                Text(Wording.suggestionReason(suggestion, in: model.organization)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s) {
                    Button { Task { await model.join(suggestion.earlier, suggestion.later) } } label: {
                        Label { Text("Same Work") } icon: { GlyphView(glyph: .merge, size: 13) }
                    }
                    Button("Not the Same") { Task { await model.keepApart(suggestion.earlier, suggestion.later) } }
                    if compact, let work = model.organization.work(containing: suggestion.later) {
                        LinkButton(title: "Show") { model.select(work.deliveries[0]) }
                            .accessibilityLabel("Show \(later)")
                    }
                }
                .controlSize(.small)
                Text("Nothing on disk changes, and either answer can be undone.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, compact ? Space.xs : Space.m - 2)
        .padding(.horizontal, compact ? 0 : Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if !compact {
                RoundedRectangle(cornerRadius: Radius.control + 2)
                    .strokeBorder(Palette.awaiting.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .accessibilityElement(children: .contain)
    }
}
