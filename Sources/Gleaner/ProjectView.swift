import GleanerCore
import GleanerUI
import SwiftUI

/// One project as an outline, to enter and resume: the project at its head (what it is, and what
/// arrived last), the collections the person made in it, each opening its review page, the joins
/// Gleaner suggests, then its works by the folder each is in, as the
/// project's own folders lay them out, and each work's revisions under it. In each folder, what a
/// person opens comes before what a program reads, then newest first (SPEC §5.3, "Order and
/// grouping"), with a crowded folder's files that no reply named itself folded; revisions are
/// newest first, as everywhere in the window.
struct ProjectOutline: View {
    @Environment(LibraryModel.self) private var model
    var project: Organization.Project

    /// Suggestions listed here; each file's detail shows its own.
    static let suggestionsShown = 5

    var body: some View {
        @Bindable var model = model
        let results = model.results
        let outline = model.outline(of: project)
        let suggestions = model.organization.suggestions(in: project)
        VStack(spacing: 0) {
            FilterBar(named: false)
            List(selection: $model.selectedRows) {
                Section { ProjectHeader(project: project).listRowSeparator(.hidden) }
                // The person's own grouping first, as it guides the rest: each collection, with
                // those inside it under it, opens its review page when chosen.
                let units = model.organization.units(in: project.key)
                if !units.isEmpty {
                    Section {
                        ForEach(units) { unit in
                            UnitRow(unit: unit).tag(OutlineRow.unit(unit.key))
                            ForEach(model.organization.units(inside: unit.key)) { inner in
                                UnitRow(unit: inner, inside: true).tag(OutlineRow.unit(inner.key))
                            }
                        }
                    } header: {
                        SectionHeader(title: "Collections", count: model.organization.units.filter { $0.project == project.key }.count,
                                      noun: "collection")
                    }
                }
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
                ForEach(outline, id: \.folder) { folder in
                    Section {
                        ForEach(folder.items) { item in
                            switch item {
                            case .work(let result):
                                WorkEntry(result: result, placement: model.organization.placement(of: result.work))
                            case .folded(let key, let kind, let results):
                                FoldedWorks(key: key, kind: kind, results: results)
                            }
                        }
                    } header: {
                        FolderHeader(name: Wording.folder(folder.folder), count: folder.count)
                            .contextMenu { NewCollectionFromThese(works: folder.items.flatMap(\.works)) }
                    }
                }
                // What sessions were observed doing here and handed over in no reply, after
                // everything that was.
                let sessions = model.observedSessions(in: project)
                if !sessions.isEmpty {
                    Section {
                        ForEach(sessions) { ObservedSessionGroup(session: $0, project: project) }
                    } header: {
                        SectionHeader(title: "Observed", count: sessions.map(\.candidates.count).reduce(0, +), noun: "file") {
                            GlyphView(glyph: Mark.observed.glyph, size: 12).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("No reply handed these over. Keeping one never moves or changes it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .modifier(ListHandoff())
            .modifier(FollowsSelection())
            .onKeyPress(.return) {
                guard case .unit(let key)? = model.outlineSelection else { return .ignored }
                model.place = .unit(key)
                return .handled
            }
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

/// A folder's files of one kind that no reply named itself, folded into one row with their count:
/// a group, not an object, as a folder's heading is, so it is never selected. It opens on demand,
/// and on its own while it holds the selection.
struct FoldedWorks: View {
    @Environment(LibraryModel.self) private var model
    var key: String
    var kind: Artifact.Kind
    var results: [SearchResult]

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { model.isUnfolded(key, results) }, set: { model.unfolded[key] = $0 })) {
            ForEach(results) { result in
                WorkEntry(result: result, placement: model.organization.placement(of: result.work))
            }
        } label: {
            // Counted at the trailing end, as every count of the outline is.
            SectionHeader(title: Wording.kindName(kind), count: results.count, noun: "file") {
                FileIcon(path: results.first?.work.latest.path ?? "", folder: false, size: 16)
            }
            .help(Wording.folded(kind, count: results.count))
            .contextMenu { NewCollectionFromThese(works: results.map(\.work)) }
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
                Text(project.name).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    .help(Wording.projectOrigin(project.origin))
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
                    .controlRole(.inline)
                    .help("Show \(combined.name) as its own project again, as you set on \(Wording.date(combined.correction.madeAt))")
                }
            }
            // What replies named; a folder's files come with it, under it in the outline, and no
            // reply named a file the person kept.
            let recent = project.works.lazy.filter { $0.deliveries.contains { $0.member == nil && $0.kept == nil } }.prefix(3)
            if !recent.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("Recent").foregroundStyle(.secondary)
                    ForEach(Array(recent)) { work in
                        LinkButton(title: work.name) { model.select(work.deliveries[0]) }
                            .lineLimit(1)
                            .help("\(Wording.revision(work.deliveries[0])), \(Wording.date(work.deliveries[0].deliveredAt))")
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
                .surface(.awaiting)
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
            Button { Task { await model.keepApart(suggestion.earlier, suggestion.later) } } label: {
                Label { Text("Keep Apart") } icon: { GlyphView(glyph: .rejected, size: 12) }
            }
            .help("Gleaner stops suggesting this")
        }
        .controlRole(.inline)
    }
}

/// A row of a session's observed files: a file, or a folder's files of one kind folded into one
/// row when they crowd it, as `Listing` lays them out.
enum ObservedItem: Identifiable {
    case file(Candidate)
    case folded(folder: String, kind: Artifact.Kind, candidates: [Candidate])

    var id: String {
        switch self {
        case .file(let candidate): candidate.path
        case .folded(let folder, let kind, _): "folded\n" + folder + "\n" + kind.rawValue
        }
    }

    static func items(_ candidates: [Candidate]) -> [ObservedItem] {
        Listing.rows(candidates.map(Listing.Entry.candidate)).flatMap { row -> [ObservedItem] in
            func files(_ entries: [Listing.Entry]) -> [Candidate] {
                entries.compactMap { if case .candidate(let candidate) = $0 { candidate } else { nil } }
            }
            switch row {
            case .entry(let entry): return files([entry]).map(ObservedItem.file)
            case .together(_, let entries): return files(entries).map(ObservedItem.file)
            case .folded(let folder, let kind, let entries): return [.folded(folder: folder, kind: kind, candidates: files(entries))]
            }
        }
    }
}

/// One session's files observed in the project and handed over in no reply, under the session's
/// name: open where a project's works open, closed in a repository, as the person leaves it.
struct ObservedSessionGroup: View {
    @Environment(LibraryModel.self) private var model
    var session: ObservedSession
    var project: Organization.Project

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { model.isOpen(session) }, set: { model.unfolded["observed\n" + session.logPath] = $0 })) {
            ForEach(session.items) { item in
                switch item {
                case .file(let candidate):
                    CandidateRow(candidate: candidate, project: project)
                case .folded(let folder, let kind, let candidates):
                    FoldedCandidates(session: session, folder: folder, kind: kind, candidates: candidates, project: project)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs + 2) {
                AgentMark(provider: session.provider, size: 12).foregroundStyle(.secondary)
                    .help(Wording.provider(session.provider))
                Text(Wording.session(session.title)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: Space.s)
                Text("\(session.candidates.count)").monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Observed during \(Wording.session(session.title)), \(Wording.count(session.candidates.count, "file"))")
            .contextMenu { NewCollectionFromThese(candidates: session.candidates) }
        }
    }
}

/// A folder's observed files of one kind, folded into one row with their count, opened on demand.
/// Keep All and Add All to Collection act on every file it holds.
struct FoldedCandidates: View {
    @Environment(LibraryModel.self) private var model
    var session: ObservedSession
    var folder: String
    var kind: Artifact.Kind
    var candidates: [Candidate]
    var project: Organization.Project

    var body: some View {
        let key = "observed\n" + session.logPath + "\n" + folder + "\n" + kind.rawValue
        DisclosureGroup(isExpanded: Binding(get: { model.unfolded[key] ?? false }, set: { model.unfolded[key] = $0 })) {
            ForEach(candidates) { CandidateRow(candidate: $0, project: project) }
        } label: {
            // Its actions are on the row, as a single file's are, and in its menu.
            HStack(alignment: .center, spacing: Space.s + 2) {
                SectionHeader(title: Wording.folded(model.outlineFolder(candidates[0], in: project), count: candidates.count),
                              count: candidates.count, noun: "file") {
                    FileIcon(path: candidates[0].path, folder: false, size: 16)
                }
                Button("Keep All") { Task { await model.keep(candidates) } }
                    .controlRole(.inline)
                    .help("Add every one to the library, as this session left it")
                Menu { addAll } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More")
                    .accessibilityLabel("More")
            }
            .contextMenu {
                Button("Keep All") { Task { await model.keep(candidates) } }
                addAll
                NewCollectionFromThese(candidates: candidates)
            }
        }
    }

    var addAll: some View {
        Menu("Add All to Collection") {
            CollectionChoices(project: project.key) { unit in
                Task { await model.add(candidates, to: unit) }
            } new: {
                model.startNewUnit(in: project.key, adding: candidates.map(\.path))
            }
        }
    }
}

/// A file observed during a session and handed over in no reply: its name, whether it appeared or
/// changed and when, and where it is. Keep admits it; Add to Collection keeps it in one; Not From
/// This Session detaches it from the session it is listed under (docs/design/review.md).
struct CandidateRow: View {
    @Environment(LibraryModel.self) private var model
    var candidate: Candidate
    var project: Organization.Project

    var body: some View {
        let latest = candidate.latest
        let statement = Wording.observed(latest)
        let others = candidate.observations.dropFirst().map { Wording.session($0.sessionTitle) }
        let folder = Wording.folder(model.outlineFolder(candidate, in: project))
        HStack(alignment: .center, spacing: Space.s + 2) {
            FileIcon(path: candidate.path, folder: false, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(candidate.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Space.xs)
                    Text(Wording.shortDate(latest.date)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .help(Wording.date(latest.date))
                }
                HStack(spacing: Space.s) {
                    // The session is said once, by its group; the row says what it saw, and where.
                    StatusLabel(mark: .observed, text: latest.kind == .appeared ? "Appeared" : "Changed", size: 11)
                    Text(folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                .font(.caption)
                .help(([statement.detail] + candidate.observations.dropFirst().map { Wording.observed($0).title + "." }).joined(separator: " "))
            }
            Button("Keep") { Task { await model.keep([candidate]) } }
                .controlRole(.inline)
                .help("Add it to the library, as this session left it")
            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Keep") { Task { await model.keep([candidate]) } }
            actions
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: candidate.path)]) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.name), \(statement.title)" + (others.isEmpty ? "" : ", also during \(others.joined(separator: ", "))"))
    }

    @ViewBuilder var actions: some View {
        Menu("Add to Collection") {
            CollectionChoices(project: project.key) { unit in
                Task { await model.add([candidate], to: unit) }
            } new: {
                model.startNewUnit(in: project.key, adding: [candidate.path])
            }
        }
        Button("Not From This Session") { Task { await model.detach(candidate.path, from: candidate.latest.logPath) } }
    }
}
