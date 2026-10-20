import GleanerCore
import GleanerUI
import SwiftUI

/// The replies that handed over the listed files, newest first and grouped by day, across every
/// conversation and agent (docs/design/structure.md, Project timeline). Rows keep the order of
/// events, never their spacing: an empty stretch of time takes no room.
struct TimelineList: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        let days = model.timeline
        VStack(spacing: 0) {
            // A project's head names it, as its outline's does, so the bar leaves it out.
            FilterBar(named: false)
            List {
                // The list's first row, so the first day's header begins below the band the filters sit in.
                if !days.isEmpty {
                    Section {
                        if let project = model.currentProject {
                            ProjectHeader(project: project).listRowSeparator(.hidden)
                        } else {
                            Text(Wording.count(days.map(\.handovers.count).reduce(0, +), "reply", "replies"))
                                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                ForEach(days) { day in
                    Section {
                        ForEach(day.handovers) { handover in
                            TimelineRow(handover: handover, project: model.currentProject == nil ? project(of: handover) : nil)
                        }
                    } header: {
                        SectionHeader(title: Wording.day(day.day), count: day.handovers.count, noun: "reply", plural: "replies")
                    }
                }
            }
            .overlay {
                if days.isEmpty {
                    if model.results.isEmpty {
                        ResultsEmptyState()
                    } else {
                        // What is listed was kept from a session, or came inside a folder: no reply of its own.
                        EmptyState(title: "No Replies", glyph: .artifact) {
                            Button("Show Works") { model.arrangement = .works }
                        }
                    }
                }
            }
            TroubleBar()
        }
    }

    /// The project its first file's work is shown in.
    func project(of handover: Handover) -> Organization.Project? {
        model.organization.work(containing: handover.first.path).flatMap { model.organization.project($0.project) }
    }
}

/// One reply in the timeline, read as the list reads a work: when and by which agent, its
/// conversation (which opens the thread), what you asked, then the files it handed over (each
/// shows that delivery).
struct TimelineRow: View {
    @Environment(LibraryModel.self) private var model
    var handover: Handover
    /// The project as shown, by its mark and name, or nil when the list is one project's.
    var project: Organization.Project?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                AgentMark(provider: handover.provider, size: 12).foregroundStyle(.secondary)
                    .help(Wording.provider(handover.provider))
                if let at = handover.deliveredAt {
                    Text(at.formatted(date: .omitted, time: .shortened)).monospacedDigit().foregroundStyle(.secondary)
                }
                ConversationLink(title: handover.sessionTitle, delivery: handover.first)
                Spacer(minLength: Space.xs)
                if let project {
                    HStack(spacing: 3) {
                        GlyphView(glyph: Wording.projectGlyph(project.origin), size: 11)
                        Text(project.name).lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .help(Wording.projectOrigin(project.origin))
                }
            }
            .font(.caption)
            if let request = handover.request {
                Text(request).font(.callout).lineLimit(2)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(handover.items) { item in
                    HandedOverFile(item: item, emphasized: model.selectedDelivery?.id == item.delivery.id)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, Space.xs)
    }
}

/// A conversation by its name, which opens it as a thread.
struct ConversationLink: View {
    @Environment(LibraryModel.self) private var model
    var title: String?
    var delivery: Delivery

    var body: some View {
        LinkButton(title: title ?? "Untitled conversation") { model.openThread(delivery) }
            .lineLimit(1).truncationMode(.tail)
            .help("Show everything this conversation handed over, reply by reply")
    }
}

/// A file one reply handed over; choosing it shows that delivery. `emphasized` sets in semibold
/// the one the detail shows, or the one a thread was opened from.
struct HandedOverFile: View {
    @Environment(LibraryModel.self) private var model
    var item: Handover.Item
    var emphasized = false

    var body: some View {
        let artifact = item.artifact
        HStack(spacing: Space.s) {
            FileIcon(path: artifact.path, folder: artifact.kind == .folder, size: 16)
            LinkButton(title: artifact.name) { model.select(item.delivery) }
                .lineLimit(1).truncationMode(.middle)
                .fontWeight(emphasized ? .semibold : .regular)
            if artifact.deliveries.count > 1 {
                Text("Delivery \(item.delivery.number)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .font(.callout)
        .help("Show delivery \(item.delivery.number) of \(artifact.name)")
        .accessibilityElement(children: .combine)
    }
}

/// One conversation's replies in the order its log holds them: each request, the files the reply
/// handed over and the agent's own words. A page, not a mode: it ends where the conversation
/// ended, and Esc goes back to the file.
struct ThreadView: View {
    @Environment(LibraryModel.self) private var model
    var page: ThreadPage

    var body: some View {
        let handovers = Handovers.thread(logPath: page.logPath, in: model.artifacts)
        let focused = handovers.first { $0.items.contains { $0.id == page.focus } }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header(handovers)
                    ForEach(handovers) { handover in
                        ThreadReply(handover: handover, focus: page.focus).id(handover.id)
                    }
                }
                .padding(Space.xl)
                .frame(maxWidth: 880, alignment: .leading)
            }
            .onAppear { if let focused, focused.id != handovers.first?.id { proxy.scrollTo(focused.id, anchor: .top) } }
        }
        .onExitCommand { model.thread = nil }
    }

    func header(_ handovers: [Handover]) -> some View {
        let first = handovers.first
        let dates = handovers.compactMap(\.deliveredAt)
        let span = [dates.min(), dates.max()].compactMap { $0 }.map { $0.formatted(date: .abbreviated, time: .omitted) }
        let facts = [first.map { Wording.provider($0.provider) }, Wording.count(handovers.count, "reply", "replies"),
                     Set(span).count > 1 ? span.joined(separator: " – ") : span.first].compactMap { $0 }
        return VStack(alignment: .leading, spacing: Space.s) {
            if let back = model.selected {
                Button("Back to \(model.file(in: back).name)", systemImage: "chevron.left") { model.thread = nil }
                    .controlRole(.inline)
                    .help("Show the file again (Esc)")
                    .padding(.bottom, Space.xs)
            }
            Text(first?.sessionTitle ?? "Untitled conversation").font(.title3.weight(.semibold)).textSelection(.enabled)
            HStack(spacing: Space.s) {
                if let first { AgentMark(provider: first.provider, size: 14, color: true) }
                Text(facts.joined(separator: " · ")).foregroundStyle(.secondary)
            }
            .font(.callout)
            HStack(spacing: Space.s) {
                Text(Wording.tilde(page.logPath)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    .help(page.logPath)
                if let first {
                    Button("Show in Log") { model.revealLog(first.first) }
                        .controlRole(.inline)
                }
            }
            .font(.caption)
        }
    }
}

/// One reply of a thread, laid out as a delivery's Information: what you asked, what it handed
/// over, and what it said.
struct ThreadReply: View {
    var handover: Handover
    var focus: Delivery.ID?

    var body: some View {
        DetailSection(title: Wording.date(handover.deliveredAt)) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.s + 2) {
                if let request = handover.request {
                    InfoRow(label: "Request") { Text("“\(request)”").lineLimit(6).textSelection(.enabled) }
                }
                InfoRow(label: handover.items.count == 1 ? "File" : "Files") {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(handover.items) { item in
                            HandedOverFile(item: item, emphasized: item.id == focus)
                        }
                    }
                }
                if !handover.excerpts.isEmpty {
                    InfoRow(label: "Reply") {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            // The agent's own words, quoted beside a rule, as the Information section quotes them.
                            ForEach(handover.excerpts, id: \.self) { excerpt in
                                Text(InformationSection.excerpt(excerpt))
                                    .textSelection(.enabled)
                                    .padding(.leading, Space.s + 2)
                                    .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
                            }
                        }
                    }
                }
            }
            .font(.callout)
        }
    }
}
