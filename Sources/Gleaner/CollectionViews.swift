import AppKit
import GleanerCore
import GleanerUI
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A collection in the sidebar: under its project, named in place when it is renamed, and a place
/// to drop works on (docs/design/review.md, Collections).
struct UnitSidebarRow: View {
    @Environment(LibraryModel.self) private var model
    var unit: WorkUnit

    var body: some View {
        if model.naming == .rename(unit.key) {
            NamingField(initial: unit.name)
        } else {
            let works = model.organization.works(in: unit.key, inner: true).count
            // Under its project, as the indent shows; its works are counted in the help tag.
            Text(unit.name).lineLimit(1).truncationMode(.middle)
                .padding(.leading, Sidebar.inset)
                .tag(Place.unit(unit.key))
                .accessibilityLabel("\(unit.name), collection, \(Wording.count(works, "work"))")
                .help("\(Wording.unitPath(unit, in: model.organization)) · \(Wording.count(works, "work"))")
                .contextMenu { UnitCommands(unit: unit) }
                .onDrop(of: [.gleanerWork], isTargeted: nil) { providers in
                    UnitDrop.accept(providers, into: unit, model: model)
                }
        }
    }
}

/// Works dropped on a collection go in it: the rows dragged, or, when one of several chosen rows
/// was dragged, every work chosen.
enum UnitDrop {
    @MainActor static func accept(_ providers: [NSItemProvider], into unit: WorkUnit, model: LibraryModel) -> Bool {
        let wanted = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.gleanerWork.identifier) }
        guard !wanted.isEmpty else { return false }
        for provider in wanted {
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.gleanerWork.identifier) { data, _ in
                guard let data else { return }
                let path = String(decoding: data, as: UTF8.self)
                Task { @MainActor in
                    guard let unit = model.organization.unit(unit.key) else { return }
                    await model.add(model.dropped([path]), to: unit)
                }
            }
        }
        return true
    }
}

/// A collection's name, edited in place in the sidebar as Finder edits a new folder's: Return or
/// leaving the field keeps it, Escape leaves things as they were.
struct NamingField: View {
    @Environment(LibraryModel.self) private var model
    var initial = ""
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Collection Name", text: $name, prompt: Text("New Collection"))
            .padding(.leading, Sidebar.inset)
            .focused($focused)
            .onSubmit(commit)
            .onExitCommand { model.naming = nil }
        .onAppear {
            name = initial
            // After the row is in the list, which takes the first responder as it appears.
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: focused) { if !focused { commit() } }
    }

    func commit() {
        guard let naming = model.naming else { return }
        model.naming = nil
        let name = name
        Task { await model.commit(naming, name: name) }
    }
}

/// Making, renaming and deleting a collection, as its context menu and the File menu offer them.
struct UnitCommands: View {
    @Environment(LibraryModel.self) private var model
    var unit: WorkUnit

    var body: some View {
        // Collections nest one level deep: one inside another holds none of its own.
        if unit.parent == nil {
            Button("New Collection Inside") { model.startNewUnit(in: unit.project, inside: unit.key) }
        }
        Button("Rename") { model.startRenaming(unit) }
        Button("Delete") { Task { await model.delete(unit) } }
            .help("Its works go back to the project. No file changes.")
    }
}

/// New Collection from These, for a group the window shows: a folder in a project's outline, a
/// session's observed files, a folded row, files shown together on a review page, what a reply
/// delivered together, what a search found (docs/design/review.md). It names a new collection in
/// place holding exactly them, the observed files kept, as one decision with one Undo; nothing is
/// inferred. Its help says which collections it takes works out of, since a work is in one at
/// most. Offered while they are in one project, since a collection holds one project's works.
struct NewCollectionFromThese: View {
    @Environment(LibraryModel.self) private var model
    var works: [Work] = []
    var candidates: [Candidate] = []
    /// The collection to make it inside, for files shown together on a collection's page.
    var inside: String? = nil

    var body: some View {
        let one = model.project(of: works, candidates) != nil
        Button("New Collection from These") { model.newCollection(from: works, candidates, inside: inside) }
            .disabled(!one)
            .help(one ? Wording.fromThese(files: works.count + candidates.count, takingOut: model.unitsHolding(works))
                  : "These are in several projects; a collection holds one project’s works.")
    }
}

/// Add to Collection ▸ and Remove from Collection, for the works chosen.
struct CollectionCommands: View {
    @Environment(LibraryModel.self) private var model
    var works: [Work]

    var body: some View {
        if let project = works.first?.project {
            Menu(Wording.collectionCommand(works)) {
                CollectionChoices(project: project, except: Set(works.compactMap(\.unit))) { unit in
                    Task { await model.add(works, to: unit) }
                } new: {
                    model.startNewUnit(in: project, adding: works.map(\.id))
                }
            }
        }
        if works.contains(where: { $0.unit != nil }) {
            Button("Remove from Collection") { Task { await model.remove(works) } }
        }
    }
}

/// The collections to choose from in a project, each followed by those inside it, then New
/// Collection, which names one in place in the sidebar.
struct CollectionChoices: View {
    @Environment(LibraryModel.self) private var model
    var project: String
    /// Collections the choice is already in.
    var except: Set<String> = []
    var choose: (WorkUnit) -> Void
    var new: () -> Void

    var body: some View {
        let units = model.organization.units.filter { $0.project == project }
        ForEach(units) { unit in
            Button(Wording.unitPath(unit, in: model.organization)) { choose(unit) }
                .disabled(except == [unit.key])
        }
        if !units.isEmpty { Divider() }
        Button("New Collection", action: new)
    }
}

/// A collection's content column: the collection itself at the head, whose review page the
/// detail shows; the collections inside it as rows; then its own works, in list order (what a
/// person opens first, then newest). Delete takes the chosen works out, and Return opens a
/// collection chosen inside it.
struct UnitList: View {
    @Environment(LibraryModel.self) private var model
    var unit: WorkUnit
    @State private var adding = false

    var body: some View {
        @Bindable var model = model
        let inner = model.organization.units(inside: unit.key)
        let results = model.organization.works(in: unit.key).compactMap { model.result(for: $0) }
        VStack(spacing: 0) {
            FilterBar(named: false)
            List(selection: $model.selectedRows) {
                Section { UnitHeader(unit: unit).tag(OutlineRow.unit(unit.key)) }
                if !inner.isEmpty {
                    Section {
                        ForEach(inner) { UnitRow(unit: $0).tag(OutlineRow.unit($0.key)) }
                    } header: {
                        SectionHeader(title: "Collections", count: inner.count, noun: "collection")
                    }
                }
                Section {
                    ForEach(results) { WorkEntry(result: $0) }
                } header: {
                    if !inner.isEmpty && !results.isEmpty { SectionHeader(title: "Works", count: results.count, noun: "work") }
                }
            }
            .modifier(ListHandoff())
            .modifier(FollowsSelection())
            .onDeleteCommand {
                let works = model.selectedWorks.filter { $0.unit == unit.key }
                if !works.isEmpty { Task { await model.remove(works) } }
            }
            .onKeyPress(.return) {
                guard case .unit(let key)? = model.outlineSelection, key != unit.key else { return .ignored }
                model.place = .unit(key)
                return .handled
            }
            .overlay {
                if results.isEmpty && inner.isEmpty {
                    if model.kind != nil && !model.organization.works(in: unit.key).isEmpty {
                        NoKind()
                    } else {
                        EmptyState(title: "No Works Yet", glyph: .collection) {
                            Button("Add Works…") { adding = true }
                        }
                        .padding(.top, 80)
                    }
                }
            }
            .sheet(isPresented: $adding) { AddWorksSheet(unit: unit) }
            TroubleBar()
        }
    }
}

/// Brings works of the collection's project that are in no collection into it, as many as the
/// person chooses, as one decision.
struct AddWorksSheet: View {
    @Environment(LibraryModel.self) private var model
    var unit: WorkUnit

    var body: some View {
        WorkPicker(title: "Add to “\(unit.name)”", note: "Files stay where they are.", action: "Add",
                   works: model.organization.works.filter { $0.project == unit.project && $0.unit == nil }, several: true,
                   none: "Every Work Here Is in a Collection") { works in
            Task { await model.add(works, to: unit) }
        }
    }
}

/// The collection at the head of its list: what it is, where, and what waits. Chosen, the detail
/// shows its review page.
struct UnitHeader: View {
    @Environment(LibraryModel.self) private var model
    var unit: WorkUnit

    var body: some View {
        let organization = model.organization
        let waiting = model.waiting(in: unit.key)
        let project = organization.project(unit.project)
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .center, spacing: Space.s) {
                Text(unit.name).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle)
            }
            HStack(spacing: Space.s) {
                Text(Wording.unitCounts(works: organization.works(in: unit.key).count, units: organization.units(inside: unit.key).count))
                    .foregroundStyle(.secondary).monospacedDigit()
                if waiting > 0 { StatusLabel(mark: .awaiting, text: Wording.toReview(waiting), size: 11) }
            }
            .font(.callout)
            HStack(spacing: 3) {
                if let parent = unit.parent, let above = organization.unit(parent) {
                    LinkButton(title: above.name) { model.place = .unit(above.key) }
                    Text("in").foregroundStyle(.secondary)
                }
                LinkButton(title: organization.projectName(unit.project)) { model.place = .project(unit.project) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, Space.xs)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(unit.name), collection, \(Wording.count(organization.works(in: unit.key).count, "work"))"
            + (waiting > 0 ? ", \(Wording.toReview(waiting))" : ""))
        .accessibilityHint("Shows its review page.")
    }
}

/// A collection as a row, in a project's outline or inside another: the first image among its
/// works as a poster, its name, how many works, and only what waits on the person.
struct UnitRow: View {
    @Environment(LibraryModel.self) private var model
    var unit: WorkUnit
    /// Listed under the collection it is inside, in a project's outline.
    var inside = false

    var body: some View {
        // Its works and those of the collections inside it, as the sidebar counts them.
        let works = model.organization.works(in: unit.key, inner: true).count
        let waiting = model.waiting(in: unit.key)
        HStack(alignment: .center, spacing: Space.s + 2) {
            Poster(path: model.organization.poster(of: unit.key)?.latest.path, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(unit.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Space.xs)
                    Text("\(works)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .help(Wording.count(works, "work"))
                }
                if waiting > 0 {
                    StatusLabel(mark: .awaiting, text: Wording.toReview(waiting), size: 11).font(.caption)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .padding(.leading, inside ? Space.xl : 0)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .contextMenu { UnitCommands(unit: unit) }
        .onDrop(of: [.gleanerWork], isTargeted: nil) { UnitDrop.accept($0, into: unit, model: model) }
        .help(Wording.unitPath(unit, in: model.organization))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unit.name), collection, \(Wording.count(works, "work"))" + (waiting > 0 ? ", \(Wording.toReview(waiting))" : ""))
        .accessibilityHint("Return opens it.")
    }
}

/// What stands for a collection in a list: its first image, filling a small square, or its mark.
struct Poster: View {
    var path: String?
    var size: CGFloat
    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.tag).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                GlyphView(glyph: .collection, size: size * 0.55).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tag))
        .task(id: path) { image = await ImageFile.load(path, pixels: Int(size * scale * 2)) }
        .accessibilityHidden(true)
    }
}

/// An image file read for showing, never for its bytes' identity: ImageIO at most `pixels` on its
/// longer side, off the main thread, else AppKit's own reading (SVG among the formats ImageIO
/// leaves). Nil when neither can draw it.
enum ImageFile {
    static func load(_ path: String?, pixels: Int) async -> NSImage? {
        guard let path else { return nil }
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(pixels, 1),
            ] as CFDictionary)
        }.value
        if let image { return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
        return NSImage(contentsOfFile: path).flatMap { $0.isValid && $0.size.width > 0 ? $0 : nil }
    }
}

/// What waits on the person's review, grouped by collection in the order the sidebar lists them,
/// then the works in none by project: each group headed by where it is, which leads there.
struct ToReviewList: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // The queue as listed, of the kind chosen, put back in its groups.
        let listed = Dictionary(model.results.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let groups = model.toReview.map { group in (group, group.works.compactMap { listed[$0.id] }) }.filter { !$0.1.isEmpty }
        VStack(spacing: 0) {
            FilterBar(named: false)
            List(selection: $model.selectedRows) {
                ForEach(groups, id: \.0.id) { group, results in
                    Section {
                        ForEach(results) { WorkEntry(result: $0) }
                    } header: {
                        QueueHeader(group: group, count: results.count)
                    }
                }
            }
            .modifier(ListHandoff())
            .modifier(FollowsSelection())
            .overlay {
                if groups.isEmpty {
                    if model.kind != nil && !model.toReview.isEmpty { NoKind() } else { EmptyState(title: "Nothing to Review", glyph: .awaiting) }
                }
            }
            TroubleBar()
        }
    }
}

/// Where a group of To Review is: its collection, with the one it is inside, and its project; or
/// the project, for works in no collection. Each name leads there.
struct QueueHeader: View {
    @Environment(LibraryModel.self) private var model
    var group: Organization.ReviewGroup
    var count: Int

    var body: some View {
        let organization = model.organization
        HStack(alignment: .firstTextBaseline, spacing: Space.xs + 2) {
            if let key = group.unit, let unit = organization.unit(key) {
                LinkButton(title: Wording.unitPath(unit, in: organization)) { model.place = .unit(key) }
                    .lineLimit(1)
                Text(organization.projectName(group.project)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                LinkButton(title: organization.projectName(group.project)) { model.place = .project(group.project) }
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s)
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(group.unit.flatMap { organization.unit($0) }.map { Wording.unitPath($0, in: organization) }
            .map { "\($0), \(organization.projectName(group.project))" } ?? organization.projectName(group.project))
        .accessibilityValue(Wording.toReview(count))
    }
}

/// The detail with several works chosen: how many, and what can be done with all of them.
struct SeveralSelected: View {
    @Environment(LibraryModel.self) private var model
    var works: [Work]

    var body: some View {
        EmptyState(title: "\(works.count) Works Selected", glyph: .work) {
            CollectionCommands(works: works)
                .fixedSize()
        }
    }
}
