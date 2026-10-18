import GleanerCore
import SwiftUI

/// Where a work belongs and why: its project, the files that are versions of it, and the joins
/// Gleaner suggests. Every decision here can be undone, and none changes a file on disk.
struct WorkSection: View {
    @Environment(LibraryModel.self) private var model
    var work: Work
    @State private var moving = false
    @State private var joining = false

    var body: some View {
        let organization = model.organization
        let placement = organization.placement(of: work)
        let project = organization.project(work.project)
        VStack(alignment: .leading, spacing: 10) {
            Text("Where This Belongs").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(model.projectName(work), systemImage: Wording.projectIcon(project?.origin ?? .folder))
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                switch placement {
                case .moved: Button("Put Back") { model.undoMove(work) }.help("Return it to the project Gleaner found it in.")
                case .combined(_, let correction): Button("Show Apart") { model.undo(correction) }
                case .found: EmptyView()
                }
                Button("Move to Project…") { moving = true }
            }
            .controlSize(.small)
            Text(Wording.placement(placement, of: work, organization: organization))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if work.files.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Versions of this work, oldest first:").font(.callout).foregroundStyle(.secondary)
                    ForEach(work.files, id: \.path) { file in
                        HStack(spacing: 6) {
                            TypeBadge(artifact: file)
                            Text(file.name).font(.callout)
                            Text("· \(Wording.count(file.deliveries.count, "delivery", "deliveries")) · \(file.folder)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    ForEach(organization.links(of: work)) { link in
                        HStack(spacing: 6) {
                            Text("You said \(model.describe(link)) on \(Wording.date(link.madeAt)).")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Undo") { model.undo(link) }.controlSize(.mini)
                        }
                    }
                }
            }
            Button("Join With Another File…") { joining = true }
                .controlSize(.small)
                .help("Say that another file is a version of this work, such as a renamed draft.")
            if let failure = model.correctionFailure {
                StatusLabel(mark: .attention, text: failure).font(.callout)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        .sheet(isPresented: $moving) { MoveSheet(work: work) }
        .sheet(isPresented: $joining) { JoinSheet(work: work) }
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
                    Label(project.name, systemImage: Wording.projectIcon(project.origin)).tag(Optional(project.key))
                }
            }
            .frame(minHeight: 180)
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
        if let target { model.move(work, to: target) } else if !newName.trimmingCharacters(in: .whitespaces).isEmpty { model.move(work, toNewProject: newName) } else { return }
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
                    if let other { model.join(work.id, other) }
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
