import GleanerCore
import SwiftUI

/// A work in a list and, when it has more than one revision, its revisions under it, as Mail lists
/// a conversation and its messages. Each level keeps its own type, mark and room
/// (docs/design/outline.md): the work by its file's icon and its name in semibold; a revision by
/// the endpoint that says whether its bytes were seen at delivery, in regular text, closer
/// together. Every row hands over what it names: a work's row the version it shows, a revision's
/// row that revision.
struct WorkEntry: View {
    @Environment(LibraryModel.self) private var model
    var result: SearchResult
    /// The project, when the list isn't one project's.
    var project: Organization.Project?
    var showFolder = false
    var placement: Organization.Placement?

    var body: some View {
        let work = result.work
        if work.deliveries.count > 1 {
            let open = model.isOpen(work)
            DisclosureGroup(isExpanded: Binding(get: { model.isOpen(work) }, set: { model.disclosed[work.id] = $0 })) {
                ForEach(work.deliveries) { delivery in
                    let file = work.file(of: delivery)
                    HandingOver(available: model.rowHandoff(file, delivery) != nil, item: { model.dragItem(file, delivery) }) {
                        RevisionRow(work: work, delivery: delivery)
                    }
                    .tag(OutlineRow.revision(work.id, delivery.id))
                    .id(OutlineRow.revision(work.id, delivery.id))
                    // A work and its revisions read as one group: a rule only after the last.
                    .listRowSeparator(delivery.id == work.deliveries.last?.id ? .automatic : .hidden)
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
        HandingOver(available: model.rowHandoff(result) != nil, item: { model.dragItem(for: result) }) {
            ResultRow(result: result, file: model.file(in: result), delivery: model.delivery(in: result), project: project,
                      showFolder: showFolder, status: model.rowStatus(result), placement: placement, open: open)
        }
        .tag(OutlineRow.work(result.work.id))
        .id(OutlineRow.work(result.work.id))
        .listRowSeparator(open ? .hidden : .automatic)
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

/// A row that can be dragged into another app when it has something to hand over. A row with
/// nothing starts no drag, rather than one that fails at drop.
struct HandingOver<Content: View>: View {
    var available: Bool
    var item: () -> NSItemProvider?
    @ViewBuilder var content: Content

    var body: some View {
        if available {
            content.onDrag { item() ?? NSItemProvider() }
        } else {
            content
        }
    }
}

/// One revision of a work, under it: the endpoint (filled when Gleaner saw the bytes at delivery,
/// hollow when it first saw them later), the delivery's number, its file when the work has
/// several, and what you asked for, then the agent and the date at the end, where the work's row
/// has them. The text starts under the work's name.
struct RevisionRow: View {
    var work: Work
    var delivery: Delivery

    /// From the outline's indent to the work's name: the work's icon and the room after it, less
    /// the indent the list gives a child row and the endpoint's own column.
    static let leading: CGFloat = 32 + Space.s + 2 - 14 - 12 - Space.s

    var body: some View {
        let provenance = Wording.provenanceShort(delivery.capture)
        let name = "Delivery \(Wording.number(delivery))"
        HStack(alignment: .center, spacing: Space.s) {
            GlyphView(glyph: provenance.0.glyph, size: 10).foregroundStyle(provenance.0.color)
                .frame(width: 12)
                .help(provenance.1)
            Text(name).monospacedDigit().lineLimit(1).layoutPriority(1)
            if work.files.count > 1 {
                Text((delivery.path as NSString).lastPathComponent).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).layoutPriority(1)
            }
            if let request = delivery.request {
                Text(request).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.xs)
            ProviderMark(provider: delivery.provider, size: 11).foregroundStyle(.secondary)
            Text(Wording.shortDate(delivery.deliveredAt)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .help(Wording.date(delivery.deliveredAt))
        }
        .font(.callout)
        .padding(.leading, max(0, Self.leading))
        .padding(.vertical, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    var spoken: String {
        var line = Wording.deliveryLine(delivery, sameAs: nil)
        if work.files.count > 1 { line = (delivery.path as NSString).lastPathComponent + ", " + line }
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
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Space.s)
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(Wording.count(count, "work"))")
    }
}

/// The detail with nothing selected: the next step, the newest work in this place, as a button.
struct NoSelection: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label { Text("No Selection") } icon: { GlyphView(glyph: .artifact, size: 40).foregroundStyle(.secondary) }
        } actions: {
            if let newest = model.results.first {
                Button { model.outlineSelection = .work(newest.id) } label: {
                    Label { Text(newest.work.name).lineLimit(1).truncationMode(.middle) } icon: {
                        FileIcon(path: newest.work.latest.path, folder: newest.work.kind == .folder, size: 16)
                    }
                }
                .help("Show the newest work here")
            }
        }
    }
}

/// A project of your own with no work in it: the next step, bringing work in.
struct EmptyProject: View {
    var project: Organization.Project
    @State private var choosing = false

    var body: some View {
        ContentUnavailableView {
            Label { Text("No Work Yet") } icon: { GlyphView(glyph: .person, size: 40).foregroundStyle(.secondary) }
        } actions: {
            Button("Move Work Here…") { choosing = true }
        }
        .sheet(isPresented: $choosing) { MoveHereSheet(project: project) }
    }
}

/// Brings a work from another project into this one, as Move to Project… in a work's detail does.
struct MoveHereSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var project: Organization.Project
    @State private var chosen: Work.ID?
    @State private var filter = ""

    var body: some View {
        let candidates = model.organization.works.filter { work in
            work.project != project.key && (filter.isEmpty || work.files.contains { $0.name.localizedCaseInsensitiveContains(filter) })
        }
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Move Work to “\(project.name)”").font(.headline)
            Text("Files stay where they are. Later deliveries of them follow.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Filter", text: $filter, prompt: Text("Filter by name"))
            List(selection: $chosen) {
                ForEach(candidates) { work in
                    HStack(spacing: Space.s) {
                        FileIcon(path: work.latest.path, folder: work.latest.kind == .folder, size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(work.name).lineLimit(1).truncationMode(.middle)
                            HStack(spacing: 3) {
                                if let from = model.organization.project(work.project) {
                                    GlyphView(glyph: Wording.projectGlyph(from.origin), size: 11)
                                    Text(from.name + " · ")
                                }
                                Text(Wording.shortDate(work.deliveries[0].deliveredAt))
                            }
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(Optional(work.id))
                }
            }
            .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move") {
                    if let chosen, let work = model.organization.work(containing: chosen) {
                        Task { await model.move(work, to: project.key) }
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil)
            }
        }
        .padding(Space.xl)
        .frame(width: 460)
    }
}
