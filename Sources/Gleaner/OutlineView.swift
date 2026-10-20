import GleanerCore
import GleanerUI
import SwiftUI

/// A work in a list and, when it has more than one revision, its revisions under it, as Mail lists
/// a conversation and its messages. Each level keeps its own type, mark and room
/// (docs/design/outline.md): the work by its file's icon and its name in semibold; a revision by
/// the endpoint that says whether its bytes were seen at delivery, in regular text, closer
/// together. Every row shows, hands over and opens its menu on what it names: a closed work's row
/// the revision it shows, an open work's row the work's own (the matched or newest), and a
/// revision's row that revision.
struct WorkEntry: View {
    @Environment(LibraryModel.self) private var model
    var result: SearchResult
    /// The project, when the list isn't one project's.
    var project: Organization.Project?
    var showFolder = false
    var placement: Organization.Placement?
    /// Names the work's collection on its row, as search results do; elsewhere its help tag does.
    var namesCollection = false

    var body: some View {
        let work = result.work
        if work.deliveries.count > 1 {
            let open = model.isOpen(work)
            DisclosureGroup(isExpanded: Binding(get: { model.isOpen(work) }, set: { model.disclosed[work.id] = $0 })) {
                ForEach(work.deliveries) { delivery in
                    let file = work.file(of: delivery)
                    HandingOver(item: { model.rowDragItem(work, file, delivery) }) {
                        RevisionRow(work: work, delivery: delivery, status: model.revisionStatus(file, delivery))
                    }
                    .tag(OutlineRow.revision(work.id, delivery.id))
                    .id(OutlineRow.revision(work.id, delivery.id))
                    // A work and its revisions read as one group: no rule inside it, one after it.
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparator(delivery.id == work.deliveries.last?.id ? .automatic : .hidden, edges: .bottom)
                }
            } label: {
                row(open: open)
            }
        } else {
            row(open: false)
        }
    }

    /// The work's row. What it hands over is decided when the drag starts: the detail may have
    /// chosen another of its revisions since the row was drawn.
    func row(open: Bool) -> some View {
        let delivery = model.workDelivery(result), file = result.work.file(of: delivery)
        return HandingOver(item: {
            let delivery = model.workDelivery(result)
            return model.rowDragItem(result.work, result.work.file(of: delivery), delivery)
        }) {
            ResultRow(result: result, file: file, delivery: delivery, project: project, showFolder: showFolder,
                      status: open ? (model.fileStatus(file), nil) : model.rowStatus(result), placement: placement, open: open,
                      waiting: model.waits(result.work), collection: model.collectionPath(result.work),
                      namesCollection: namesCollection)
        }
        .tag(OutlineRow.work(result.work.id))
        .id(OutlineRow.work(result.work.id))
        .listRowSeparator(open ? .hidden : .automatic, edges: .bottom)
    }
}

/// Keeps the selected row in view when something other than the list chose it, such as a link in
/// the detail or the project's Recent: the list scrolls only as far as it must.
struct FollowsSelection: ViewModifier {
    @Environment(LibraryModel.self) private var model

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: model.outlineSelection) {
                if let row = model.outlineSelection { proxy.scrollTo(row) }
            }
        }
    }
}

/// A row dragged: into another app, when it has something to hand over, and onto a collection in
/// the sidebar, always (`LibraryModel.rowDragItem`). A row with nothing to hand over offers another
/// app nothing, so no drop there fails: only a collection takes it.
struct HandingOver<Content: View>: View {
    var item: () -> NSItemProvider
    @ViewBuilder var content: Content

    var body: some View {
        content.onDrag(item)
    }
}

/// One revision of a work, under it, in the order of the work's own row: first the endpoint
/// (filled when Gleaner saw the bytes at delivery, hollow when it first saw them later), the
/// delivery's number and its file when the work has several, with the agent and the date at the
/// end; then what you asked for; then, only when it has nothing to hand over, why. The text starts
/// under the work's name.
struct RevisionRow: View {
    var work: Work
    var delivery: Delivery
    /// Why it has nothing to hand over (`LibraryModel.revisionStatus`).
    var status: (label: (Mark, String), reason: String)?

    /// The list's indent for a row under another, measured in the tour: SwiftUI doesn't publish it.
    static let indent: CGFloat = 15
    /// From where the list puts a revision to under its work's name: the work's icon and the room
    /// after it, less the indent and the endpoint's own column.
    static let leading: CGFloat = 32 + Space.s + 2 - indent - 12 - Space.s

    var body: some View {
        let provenance = Wording.provenanceShort(delivery.capture, kept: delivery.kept != nil)
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            // The first tier: a state as it should be, by its mark alone, its word in the help tag.
            StatusMark(mark: provenance.0, word: provenance.1, size: 10)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(([Wording.revision(delivery)]
                          + (work.files.count > 1 ? [(delivery.path as NSString).lastPathComponent] : [])).joined(separator: " · "))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Space.xs)
                    AgentMark(provider: delivery.provider, size: 11).foregroundStyle(.secondary)
                    Text(Wording.shortDate(delivery.deliveredAt)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .help(Wording.date(delivery.deliveredAt))
                }
                if let request = delivery.request {
                    Text(request).foregroundStyle(.secondary).lineLimit(2)
                } else if delivery.kept != nil {
                    Text("Observed during \(Wording.session(delivery.sessionTitle))").foregroundStyle(.secondary).lineLimit(2)
                }
                if let status {
                    StatusLabel(mark: status.label.0, text: status.label.1, size: 11).font(.caption)
                        .help(status.reason)
                }
            }
        }
        .font(.callout)
        .padding(.leading, Self.leading)
        .padding(.vertical, 2)
        // The rule after a work's last revision starts where the work's own rule does.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] - Self.indent }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    var spoken: String {
        var line = Wording.deliveryLine(delivery, sameAs: nil)
        if work.files.count > 1 { line = (delivery.path as NSString).lastPathComponent + ", " + line }
        if let status { line += ", \(status.label.1.lowercased()). \(status.reason)" }
        if let request = delivery.request { line += ", you asked: \(request.prefix(160))" }
        return line
    }
}

/// A folder of a project's outline: a group, not an object, so it has no mark and is never
/// selected. Its count is the works listed in it.
struct FolderHeader: View {
    var name: String
    var count: Int

    var body: some View {
        SectionHeader(title: name, count: count, noun: "work")
    }
}

/// A section's header in a list: its title, and how many it lists at the trailing end, where
/// every count of the outline stands.
struct SectionHeader<Leading: View>: View {
    var title: String
    var count: Int
    /// What it counts, for VoiceOver, and its plural when not the noun with an s.
    var noun: String
    var plural: String? = nil
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs + 2) {
            leading
            Text(title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Space.s)
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(Wording.count(count, noun, plural ?? noun + "s"))")
    }
}

extension SectionHeader where Leading == EmptyView {
    init(title: String, count: Int, noun: String, plural: String? = nil) {
        self.init(title: title, count: count, noun: noun, plural: plural) { EmptyView() }
    }
}

/// The detail with nothing selected: the next step, the newest work in this place.
struct NoSelection: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        EmptyState(title: "No Selection", glyph: .artifact) {
            if let newest = model.results.first {
                Button { model.outlineSelection = .work(newest.id) } label: {
                    Label { Text("Show \(newest.work.name)").lineLimit(1).truncationMode(.middle) } icon: {
                        FileIcon(path: newest.work.latest.path, folder: newest.work.kind == .folder, size: 16)
                    }
                }
                .help("The newest work here")
                .accessibilityHint("Shows the newest work here.")
            }
        }
    }
}

/// A list with nothing of the kind chosen: the next step, every kind again.
struct NoKind: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No \(model.kind.map(Wording.kindName) ?? "Works")", systemImage: "line.3.horizontal.decrease.circle")
        } actions: {
            Button("Show All Kinds") { model.kind = nil }
        }
    }
}

/// A project of your own with no work in it: the next step, bringing work in.
struct EmptyProject: View {
    var project: Organization.Project
    @State private var choosing = false

    var body: some View {
        EmptyState(title: "No Work Yet", glyph: .person) {
            Button("Move Work Here…") { choosing = true }
        }
        .sheet(isPresented: $choosing) { MoveHereSheet(project: project) }
    }
}

/// Brings a work from another project into this one, as Move to Project… in a work's detail does.
struct MoveHereSheet: View {
    @Environment(LibraryModel.self) private var model
    var project: Organization.Project

    var body: some View {
        WorkPicker(title: "Move Work to “\(project.name)”", note: "Files stay where they are. Later deliveries of them follow.",
                   action: "Move", works: model.organization.works.filter { $0.project != project.key }) { works in
            if let work = works.first { Task { await model.move(work, to: project.key) } }
        }
    }
}

/// A sheet that picks one work, or with `several` any number of them: its title, one line about
/// what the action does, a filter by name, the works in the order given, and Cancel and the
/// action. With none to pick, it says so.
struct WorkPicker: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var title: String
    var note: String
    var action: String
    var works: [Work]
    /// Whether ⌘- and ⇧-clicks choose several, for one decision on all of them.
    var several = false
    /// What the sheet says when there is no work to pick.
    var none = "No Works"
    var choose: ([Work]) -> Void
    @State private var chosen: Set<Work.ID> = []
    @State private var filter = ""

    var body: some View {
        let shown = works.filter { work in filter.isEmpty || work.files.contains { $0.name.localizedCaseInsensitiveContains(filter) } }
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title).font(.headline)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Filter", text: $filter, prompt: Text("Filter by name"))
                .disabled(works.isEmpty)
            Group {
                if several {
                    List(selection: $chosen) { rows(shown) }
                } else {
                    List(selection: Binding(get: { chosen.first }, set: { chosen = $0.map { [$0] } ?? [] })) { rows(shown) }
                }
            }
            .frame(minHeight: 220)
            .overlay { if works.isEmpty { EmptyState(title: none, glyph: .work) } }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action) {
                    let picked = works.filter { chosen.contains($0.id) }
                    if !picked.isEmpty { choose(picked) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(Space.xl)
        .frame(width: 460)
    }

    func rows(_ shown: [Work]) -> some View {
        ForEach(shown) { work in
            HStack(spacing: Space.s) {
                FileIcon(path: work.latest.path, folder: work.latest.kind == .folder, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(work.files.map(\.name).joined(separator: " → ")).lineLimit(1).truncationMode(.middle)
                    caption(work)
                }
            }
            .tag(work.id)
        }
    }

    /// Where the work is and when it last arrived: its project by name, its folder, the date.
    func caption(_ work: Work) -> some View {
        let project = model.organization.project(work.project)
        return Text([project?.name ?? model.projectName(work), Wording.folder(work.latest.folder),
                     Wording.shortDate(work.deliveries[0].deliveredAt)].joined(separator: " · "))
            .help(project.map { Wording.projectOrigin($0.origin) } ?? "")
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
}
