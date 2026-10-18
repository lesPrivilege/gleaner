import GleanerCore
import SwiftUI

/// One project as an outline, to enter and resume: the project at its head (what it is, and what
/// arrived last), the joins Gleaner suggests, then its works by the folder each is in, as the
/// project's own folders lay them out, and each work's revisions under it. Works and revisions are
/// newest first, as everywhere in the window; folders keep the project's own layout.
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
            FilterBar(named: false)
            List(selection: $model.outlineSelection) {
                Section { ProjectHeader(project: project).listRowSeparator(.hidden) }
                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions.prefix(Self.suggestionsShown)) { SuggestionView(suggestion: $0, compact: true) }
                        if suggestions.count > Self.suggestionsShown {
                            Text("\(suggestions.count - Self.suggestionsShown) more in their files’ details")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        SectionHeader(title: "Suggestions", count: suggestions.count, noun: "suggestion") {
                            GlyphView(glyph: .awaiting, size: 12).foregroundStyle(Palette.awaiting)
                        }
                    } footer: {
                        Text("Joining never moves or changes a file.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(order, id: \.self) { folder in
                    let works = folders[folder]!
                    Section {
                        ForEach(works) { result in
                            WorkEntry(result: result, placement: model.organization.placement(of: result.work))
                        }
                    } header: {
                        FolderHeader(name: Wording.folder(folder), count: works.count)
                    }
                }
            }
            .modifier(ListHandoff())
            .modifier(FollowsSelection())
            .overlay {
                if project.works.isEmpty {
                    EmptyProject(project: project)
                } else if results.isEmpty {
                    NoKind()
                }
            }
            TroubleBar()
        }
    }
}

/// What the project is, where its folder is, and what arrived last.
struct ProjectHeader: View {
    @Environment(LibraryModel.self) private var model
    var project: Organization.Project

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .center, spacing: Space.s) {
                GlyphView(glyph: Wording.projectGlyph(project.origin), size: 20).foregroundStyle(Palette.mark)
                    .help(Wording.projectOrigin(project.origin))
                Text(project.name).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: Space.s)
                if let folder = project.folder, Locator.stat(folder).kind == .directory {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Show the project’s folder in Finder")
                    .accessibilityLabel("Show in Finder")
                }
            }
            // An empty project says so once, where the next step is.
            if !project.works.isEmpty {
                Text(Wording.projectCounts(project)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            if let folder = project.folder {
                Text(Wording.tilde(folder))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .help("\(Wording.projectOrigin(project.origin)): \(folder)")
            }
            ForEach(project.combined, id: \.folder) { combined in
                HStack(spacing: Space.s) {
                    Text("Includes \(combined.name)").font(.caption).foregroundStyle(.secondary)
                    Button { Task { await model.undo(combined.correction, following: false) } } label: {
                        Label { Text("Show Apart") } icon: { GlyphView(glyph: .branch, size: 12) }
                    }
                    .controlSize(.small)
                    .help("Show \(combined.name) as its own project again, as you set on \(Wording.date(combined.correction.madeAt))")
                }
            }
            let recent = project.works.prefix(3)
            if !recent.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("Recent").foregroundStyle(.secondary)
                    ForEach(Array(recent)) { work in
                        LinkButton(title: work.name) { model.select(work.deliveries[0]) }
                            .lineLimit(1)
                            .help("Delivery \(work.deliveries[0].number), \(Wording.date(work.deliveries[0].deliveredAt))")
                    }
                }
                .font(.caption)
                .padding(.top, Space.xs)
            }
        }
        .padding(.vertical, Space.xs)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}

/// Two files that may be versions of one work, with Gleaner's reason and the person's answer. It
/// waits on the person, so it carries the one accent and the awaiting mark; in a file's detail it
/// is a banner with a dashed outline, the "not in effect" of the relation grammar
/// (`kit/design/foundations/standing.md`). Gleaner's full reason is one click away.
struct SuggestionView: View {
    @Environment(LibraryModel.self) private var model
    var suggestion: Organization.Suggestion
    /// In a list of a project's suggestions, rather than one file's detail.
    var compact = false
    /// The work whose detail shows this, to say which side it is.
    var from: Work?

    var body: some View {
        let earlier = (suggestion.earlier as NSString).lastPathComponent, later = (suggestion.later as NSString).lastPathComponent
        let reason = Wording.suggestionReason(suggestion, in: model.organization)
        Group {
            if compact {
                VStack(alignment: .leading, spacing: Space.xs + 2) {
                    HStack(spacing: Space.xs) {
                        Text(earlier).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary).accessibilityLabel("then")
                        if let work = model.organization.work(containing: suggestion.later) {
                            LinkButton(title: later) { model.select(work.deliveries[0]) }
                                .fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                                .help("Show \(later)")
                        }
                    }
                    HStack(spacing: Space.xs) {
                        Text(reason.short).font(.caption).foregroundStyle(.secondary)
                        InfoButton(text: reason.full)
                    }
                    buttons
                }
                .padding(.vertical, Space.xs)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            } else {
                HStack(alignment: .center, spacing: Space.m) {
                    GlyphView(glyph: .awaiting, size: 18).foregroundStyle(Palette.awaiting)
                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if let from, from.contains(suggestion.later) {
                                Text("Suggested: ").foregroundStyle(Palette.awaiting).fontWeight(.semibold)
                                    + Text("may be a later version of **\(earlier)**")
                            } else if let from, from.contains(suggestion.earlier) {
                                Text("Suggested: ").foregroundStyle(Palette.awaiting).fontWeight(.semibold)
                                    + Text("**\(later)** may be a later version")
                            } else {
                                Text("Suggested: ").foregroundStyle(Palette.awaiting).fontWeight(.semibold)
                                    + Text("**\(earlier)** → **\(later)**")
                            }
                        }
                        .font(.callout)
                        HStack(spacing: Space.xs) {
                            Text(reason.short).font(.caption).foregroundStyle(.secondary)
                            InfoButton(text: reason.full + " Joining never moves or changes a file, and Edit › Undo takes it back.")
                        }
                    }
                    Spacer(minLength: Space.s)
                    buttons
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s + 2)
                .background(Palette.awaitingWash, in: RoundedRectangle(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(Palette.awaiting.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested: \(earlier), then \(later). \(reason.short)")
    }

    var buttons: some View {
        HStack(spacing: Space.s) {
            Button { Task { await model.join(suggestion.earlier, suggestion.later) } } label: {
                Label { Text("Join") } icon: { GlyphView(glyph: .merge, size: 12) }
            }
            .help("Show both as versions of one work")
            Button("Keep Apart") { Task { await model.keepApart(suggestion.earlier, suggestion.later) } }
                .help("Gleaner stops suggesting this")
        }
        .controlSize(.small)
    }
}
