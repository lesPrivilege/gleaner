import GleanerCore
import SwiftUI

/// One conversation's handovers, oldest first: each request, the files that reply named and the
/// agent's own words. A page, not a mode: it ends where the conversation ended.
struct ThreadView: View {
    @Environment(LibraryModel.self) private var model
    var page: ThreadPage

    var body: some View {
        let handovers = Handovers.thread(logPath: page.logPath, in: model.artifacts)
        let back = model.selected?.artifact
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(handovers, back: back)
                    ForEach(handovers) { handover in
                        HandoverCard(handover: handover, focused: handover.items.contains { $0.id == page.focus })
                            .id(handover.id)
                    }
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
            .onAppear {
                if let focused = handovers.first(where: { $0.items.contains { $0.id == page.focus } }) {
                    proxy.scrollTo(focused.id, anchor: .top)
                }
            }
        }
        .onExitCommand { model.thread = nil }
    }

    func header(_ handovers: [Handover], back: Artifact?) -> some View {
        let first = handovers.first
        let dates = [handovers.first?.deliveredAt, handovers.last?.deliveredAt].compactMap { $0 }
            .map { $0.formatted(date: .abbreviated, time: .omitted) }
        let span = Set(dates).count > 1 ? dates.joined(separator: " – ") : dates.first
        return VStack(alignment: .leading, spacing: 4) {
            if let back {
                Button("Back to \(back.name)", systemImage: "chevron.left") { model.thread = nil }
                    .buttonStyle(.link)
                    .help("Return to the file (Esc).")
                    .padding(.bottom, 6)
            }
            Text("THREAD").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            Text(first?.sessionTitle ?? "Untitled session").font(.title2.weight(.semibold)).textSelection(.enabled)
            Text([first.map { Wording.agent($0.provider) }, "\(handovers.count) \(handovers.count == 1 ? "handover" : "handovers")", span]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.callout).foregroundStyle(.secondary)
            Text((page.logPath as NSString).abbreviatingWithTildeInPath)
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }
}

/// One reply in a thread: when, what was asked, what it handed over, and what it said.
struct HandoverCard: View {
    @Environment(LibraryModel.self) private var model
    var handover: Handover
    var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Wording.date(handover.deliveredAt)).font(.caption).foregroundStyle(.secondary)
            if let request = handover.request {
                (Text("You asked: ").foregroundStyle(.secondary) + Text("“\(request)”"))
                    .font(.callout).lineLimit(6).textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(handover.items) { item in
                    FileButton(item: item)
                }
            }
            ForEach(handover.excerpts, id: \.self) { excerpt in
                Text(excerpt)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? Palette.selection : Color(nsColor: .separatorColor),
                                                               lineWidth: focused ? 1.5 : 1))
    }
}

/// A file one handover named; choosing it shows that delivery in the library.
struct FileButton: View {
    @Environment(LibraryModel.self) private var model
    var item: Handover.Item

    var body: some View {
        let artifact = item.artifact
        Button { model.show(item) } label: {
            HStack(spacing: 8) {
                TypeBadge(artifact: artifact)
                Text(artifact.name).lineLimit(1).truncationMode(.middle)
                if artifact.deliveries.count > 1 {
                    Text("delivery \(item.delivery.number) of \(artifact.latest.number)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show this delivery of \(artifact.name) in the library")
        .accessibilityLabel("\(artifact.name), delivery \(item.delivery.number)")
    }
}
