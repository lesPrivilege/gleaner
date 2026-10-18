import GleanerCore
import SwiftUI

/// Where a work belongs and why: its project, the files that are versions of it, and the pairs the
/// person declined. Every decision here can be undone, and none changes a file on disk.
struct WorkSection: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var work: Work
    @State private var moving = false
    @State private var joining = false

    var body: some View {
        let organization = model.organization
        let placement = organization.placement(of: work)
        let project = organization.project(work.project)
        let links = organization.links(of: work), declines = organization.declines(of: work)
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Where This Belongs").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Label {
                    Text(model.projectName(work)).font(.callout.weight(.semibold))
                } icon: {
                    GlyphView(glyph: Wording.projectGlyph(project?.origin ?? .folder), size: 16).foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.s)
                switch placement {
                case .moved: Button("Put Back") { Task { await model.undoMove(work) } }.help("Return it to the project Gleaner found it in.")
                case .combined(let folder, let correction):
                    Button { Task { await model.undo(correction) } } label: {
                        Label { Text("Show Apart") } icon: { GlyphView(glyph: .branch, size: 13) }
                    }
                    .help("Show \(organization.projectName(folder)) as its own project again, with all its work.")
                case .found: EmptyView()
                }
                Button("Move to Project…") { moving = true }
            }
            .controlSize(.small)
            Text(Wording.placement(placement, of: work, organization: organization))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if work.files.count > 1 || !declines.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(work.files.count > 1 ? "Versions of this work, oldest first" : "Versions of this work")
                        .font(.callout).foregroundStyle(.secondary)
                    VersionsStrip(work: work)
                    ForEach(links) { link in
                        DecisionLine(text: "You said \(model.describe(link)) · \(Wording.date(link.madeAt))") {
                            Task { await model.undo(link) }
                        }
                        .transition(Motion.arrive)
                    }
                    ForEach(declines) { decline in
                        DeclineLine(decline: decline, work: work)
                            .transition(Motion.arrive)
                    }
                }
            }
            Button { joining = true } label: {
                Label { Text("Join With Another File…") } icon: { GlyphView(glyph: .merge, size: 13) }
            }
            .controlSize(.small)
            .help("Say that another file is a version of this work, such as a renamed draft.")
            if let failure = model.correctionFailure {
                StatusLabel(mark: .attention, text: failure).font(.callout)
            }
        }
        .animation(Motion.state(reduceMotion), value: links.map(\.id))
        .animation(Motion.state(reduceMotion), value: declines.map(\.id))
        .padding(.top, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $moving) { MoveSheet(work: work) }
        .sheet(isPresented: $joining) { JoinSheet(work: work) }
    }
}

/// A work's files in the order they first arrived, hung on one line: solid, with filled ends,
/// because the person joined them (the relation grammar's "in effect, confirmed"). Spacing says
/// order only, never how long apart they came.
struct VersionsStrip: View {
    var work: Work

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(work.files.enumerated()), id: \.element.path) { index, file in
                HStack(alignment: .center, spacing: Space.s) {
                    ZStack {
                        // The line into this node and out of it, solid: the join is in effect.
                        VStack(spacing: 0) {
                            Rectangle().fill(index == 0 ? Color.clear : Color.secondary).frame(width: 1.5)
                            Rectangle().fill(index == work.files.count - 1 ? Color.clear : Color.secondary).frame(width: 1.5)
                        }
                        GlyphView(glyph: work.files.count > 1 ? .endSolid : .endHollow, size: 13).foregroundStyle(.secondary)
                    }
                    .frame(width: 14)
                    TypeBadge(artifact: file)
                    Text(file.name).font(.callout).lineLimit(1).truncationMode(.middle)
                    Text(Wording.count(file.deliveries.count, "delivery", "deliveries") + (file.folder == "." ? "" : " · \(file.folder)"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).monospacedDigit()
                }
                .frame(minHeight: 26)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Versions of this work, oldest first: " + work.files.map(\.name).joined(separator: ", "))
    }
}

/// One of the person's decisions, said as theirs, with its Undo beside it.
struct DecisionLine: View {
    var text: String
    var undo: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Undo", action: undo).controlSize(.small).accessibilityLabel("Undo: \(text)")
        }
    }
}

/// A pair the person declined, still shown: a dashed line ending in a cross, not in effect.
struct DeclineLine: View {
    @Environment(LibraryModel.self) private var model
    var decline: Correction
    var work: Work

    var body: some View {
        let other = work.contains(decline.subject) ? decline.target : decline.subject
        HStack(alignment: .center, spacing: Space.s) {
            ZStack(alignment: .leading) {
                Path { $0.move(to: CGPoint(x: 0, y: 6)); $0.addLine(to: CGPoint(x: 14, y: 6)) }
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))
                GlyphView(glyph: .endCross, size: 9).offset(x: 14)
            }
            .frame(width: 26, height: 12, alignment: .leading)
            .foregroundStyle(.secondary)
            DecisionLine(text: "You said \((other as NSString).lastPathComponent) is not the same work · \(Wording.date(decline.madeAt))") {
                Task { await model.undo(decline) }
            }
        }
    }
}

/// Puts a work in another project, or a new one of the person's own.
struct MoveSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var work: Work
    @State private var target: String?
    @State private var newName = ""

    var body: some View {
        let others = model.projects.filter { $0.key != work.project }
        VStack(alignment: .leading, spacing: 12) {
            Text("Move “\(work.name)” to a Project").font(.headline)
            Text("Only Gleaner’s library changes: the files stay where they are. Every file of this work moves together, and later deliveries of them stay in the project you choose.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(selection: $target) {
                ForEach(others) { project in
                    GlyphLabel(title: project.name, glyph: Wording.projectGlyph(project.origin)).tag(Optional(project.key))
                }
            }
            .frame(minHeight: 180)
            .onChange(of: target) { if target != nil { newName = "" } }
            HStack {
                TextField("Or a new project named…", text: $newName)
                    .onSubmit(move)
                    .onChange(of: newName) { if !newName.isEmpty { target = nil } }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move", action: move).keyboardShortcut(.defaultAction)
                    .disabled(target == nil && newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    func move() {
        if let target { Task { await model.move(work, to: target) } } else if !newName.trimmingCharacters(in: .whitespaces).isEmpty { Task { await model.move(work, toNewProject: newName) } } else { return }
        dismiss()
    }
}

/// Says that another file is a version of this work.
struct JoinSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var work: Work
    @State private var other: Work.ID?
    @State private var filter = ""

    var body: some View {
        let candidates = model.organization.works.filter { candidate in
            candidate.id != work.id && (filter.isEmpty || candidate.files.contains { $0.name.localizedCaseInsensitiveContains(filter) })
        }
        // This project's works first: versions of one work are usually kept together.
        let ordered = candidates.filter { $0.project == work.project } + candidates.filter { $0.project != work.project }
        VStack(alignment: .leading, spacing: 12) {
            Text("Join “\(work.name)” With Another File").font(.headline)
            Text("Both files will show as versions of one work, with every delivery of each. Gleaner checks nothing about this: it is your call, and you can undo it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Filter by name", text: $filter)
            List(selection: $other) {
                ForEach(ordered) { candidate in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            TypeBadge(artifact: candidate.latest)
                            Text(candidate.files.map(\.name).joined(separator: " → ")).lineLimit(1).truncationMode(.middle)
                        }
                        Text("\(model.projectName(candidate)) · \(candidate.latest.folder) · \(Wording.date(candidate.deliveries[0].deliveredAt))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .tag(Optional(candidate.id))
                }
            }
            .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Join") {
                    if let other { Task { await model.join(work.id, other) } }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(other == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
