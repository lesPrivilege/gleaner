import GleanerCore
import GleanerUI
import SwiftUI

/// Where a work belongs: its project and why, the files joined as its versions, and the pairs the
/// person kept apart. Every decision here can be undone, and none changes a file on disk.
struct WorkSection: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var work: Work
    @State private var moving = false
    @State private var joining = false

    var body: some View {
        let organization = model.organization
        let placement = organization.placement(of: work)
        let why = Wording.placement(placement, of: work, organization: organization)
        let project = organization.project(work.project)
        let links = organization.links(of: work), declines = organization.declines(of: work)
        DetailSection(title: "Project") {
            Button("Move to Project…") { moving = true }.controlRole(.inline)
        } content: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Label {
                    Text(model.projectName(work)).fontWeight(.semibold)
                } icon: {
                    GlyphView(glyph: Wording.projectGlyph(project?.origin ?? .folder), size: 16).foregroundStyle(Palette.mark)
                }
                Text(why.title).foregroundStyle(.secondary)
                InfoButton(text: why.detail)
                Spacer(minLength: Space.s)
                switch placement {
                case .moved:
                    Button("Put Back") { Task { await model.undoMove(work) } }
                        .controlRole(.inline)
                        .help("Return it to the project Gleaner found it in")
                case .combined(let folder, let correction):
                    Button { Task { await model.undo(correction) } } label: {
                        Label { Text("Show Apart") } icon: { GlyphView(glyph: .branch, size: 12) }
                    }
                    .controlRole(.inline)
                    .help("Show \(organization.projectName(folder)) as its own project again")
                case .found:
                    EmptyView()
                }
            }
            .font(.callout)

            if work.files.count > 1 {
                VersionsStrip(work: work).padding(.top, Space.xs)
            }
            if !links.isEmpty || !declines.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(links) { link in
                        DecisionLine(glyph: .merge, text: model.describe(link), date: link.madeAt) { Task { await model.undo(link) } }
                            .transition(Motion.arrive(reduceMotion))
                    }
                    ForEach(declines) { decline in
                        DeclineLine(decline: decline)
                            .transition(Motion.arrive(reduceMotion))
                    }
                }
            }
            HStack {
                Button { joining = true } label: {
                    Label { Text("Join With Another File…") } icon: { GlyphView(glyph: .merge, size: 12) }
                }
                .controlRole(.inline)
                .help("Say that another file is a version of this work, such as a renamed draft")
            }
            if let failure = model.correctionFailure {
                StatusLabel(mark: .attention, text: failure).font(.callout)
            }
        }
        .animation(Motion.state(reduceMotion), value: links.map(\.id))
        .animation(Motion.state(reduceMotion), value: declines.map(\.id))
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
                        // The line into this node and out of it, solid: the join is in effect. It
                        // stops at the dot's edge, so the dot reads as one solid end.
                        VStack(spacing: 8) {
                            Rectangle().fill(index == 0 ? Color.clear : Color.secondary).frame(width: 1.5)
                            Rectangle().fill(index == work.files.count - 1 ? Color.clear : Color.secondary).frame(width: 1.5)
                        }
                        GlyphView(glyph: .endSolid, size: 12).foregroundStyle(.secondary)
                    }
                    .frame(width: 14)
                    FileIcon(path: file.path, folder: file.kind == .folder, size: 16)
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                    Text([Wording.count(file.deliveries.count, "delivery", "deliveries"),
                          file.folder == "." ? nil : file.folder].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).monospacedDigit()
                }
                .font(.callout)
                .frame(minHeight: 26)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Versions of this work, oldest first: " + work.files.map(\.name).joined(separator: ", "))
    }
}

/// One of the person's decisions, said as theirs, with its Undo beside it.
struct DecisionLine: View {
    var glyph: Glyph
    var text: String
    var date: Date
    var undo: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            GlyphView(glyph: glyph, size: 12).foregroundStyle(.secondary).frame(width: 14)
            Text(text).lineLimit(1).truncationMode(.middle)
            Text(Wording.shortDate(date)).foregroundStyle(.secondary).monospacedDigit()
                .help(Wording.date(date))
            Button("Undo", action: undo).controlRole(.inline).accessibilityLabel("Undo: \(text)")
        }
        .font(.caption)
    }
}

/// A pair the person kept apart, still shown: a dashed line ending in a cross, not in effect.
struct DeclineLine: View {
    @Environment(LibraryModel.self) private var model
    var decline: Correction

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            ZStack(alignment: .leading) {
                Path { $0.move(to: CGPoint(x: 0, y: 6)); $0.addLine(to: CGPoint(x: 8, y: 6)) }
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 3]))
                GlyphView(glyph: .endCross, size: 8).offset(x: 7)
            }
            .frame(width: 14, height: 12, alignment: .leading)
            .foregroundStyle(.secondary)
            Text(model.describe(decline)).lineLimit(1).truncationMode(.middle)
            Text(Wording.shortDate(decline.madeAt)).foregroundStyle(.secondary).monospacedDigit()
                .help(Wording.date(decline.madeAt))
            Button("Undo") { Task { await model.undo(decline) } }
                .controlRole(.inline)
                .accessibilityLabel("Undo: \(model.describe(decline))")
        }
        .font(.caption)
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
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Move “\(work.name)”").font(.headline)
            Text("Files stay where they are. Later deliveries of them follow.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(selection: $target) {
                ForEach(others) { project in
                    GlyphLabel(title: project.name, glyph: Wording.projectGlyph(project.origin), size: 16).tag(Optional(project.key))
                }
            }
            .frame(minHeight: 180)
            .onChange(of: target) { if target != nil { newName = "" } }
            TextField("New Project", text: $newName, prompt: Text("Or name a new project"))
                .onSubmit(move)
                .onChange(of: newName) { if !newName.isEmpty { target = nil } }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move", action: move).keyboardShortcut(.defaultAction)
                    .disabled(target == nil && newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.xl)
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
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Join “\(work.name)” With…").font(.headline)
            Text("Both files show as versions of one work. Gleaner checks nothing: it’s your call.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Filter", text: $filter, prompt: Text("Filter by name"))
            List(selection: $other) {
                ForEach(ordered) { candidate in
                    HStack(spacing: Space.s) {
                        FileIcon(path: candidate.latest.path, folder: candidate.latest.kind == .folder, size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.files.map(\.name).joined(separator: " → ")).lineLimit(1).truncationMode(.middle)
                            Text([model.projectName(candidate), Wording.folder(candidate.latest.folder),
                                  Wording.shortDate(candidate.deliveries[0].deliveredAt)].joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
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
        .padding(Space.xl)
        .frame(width: 460)
    }
}
