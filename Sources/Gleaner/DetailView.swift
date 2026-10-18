import AppKit
import GleanerCore
import Quartz
import SwiftUI

/// One delivered file, preview first. Always visible: the bytes, what they are, how to hand them
/// over and any caveat about them. On demand: other deliveries and the full record (rulings §5).
struct DetailView: View {
    @Environment(LibraryModel.self) private var model
    var result: SearchResult

    var body: some View {
        let work = result.work
        let artifact = model.file(in: result)
        let delivery = model.delivery(in: result)
        let observation = model.observations[artifact.path]
        let onDisk = observation.map { artifact.onDisk($0, hasSaved: model.hasSaved) }
        let plan = observation.map { artifact.handoff(delivery, now: $0, hasSaved: model.hasSaved) }
        let staging = model.staging(for: plan?.sha)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(work, artifact)
                if let comparison = model.comparison {
                    ComparePane(artifact: artifact, from: comparison.from, to: comparison.to)
                } else {
                    PreviewPane(artifact: artifact, delivery: delivery, plan: plan, staging: staging)
                }
                if let plan, let onDisk, let observation {
                    HandoffPanel(artifact: artifact, delivery: delivery, plan: plan, onDisk: onDisk, observation: observation)
                } else {
                    ProgressView("Checking the file…").controlSize(.small)
                }
                ReplySection(artifact: artifact, delivery: delivery)
                if work.deliveries.count > 1 {
                    DeliveriesSection(work: work, selected: delivery)
                }
                WorkSection(work: work)
                DetailsSection(artifact: artifact, delivery: delivery, observation: observation)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .task(id: artifact.id) {
            model.clearStaging()
            await model.observe(artifact)
        }
        // A ready copy another app changed is prepared again, whenever the view looks at it.
        .task(id: model.isPreparedIntact) { model.prepareAgain() }
        .task(id: "\(artifact.id)|\(delivery.id)|\(observation?.checkedAt.timeIntervalSince1970 ?? 0)|\(model.stagingGeneration)") {
            if case .ready(let sha, _, _) = plan {
                await model.stage(sha: sha, artifact: artifact)
            } else {
                model.clearStaging()
            }
        }
    }

    func header(_ work: Work, _ artifact: Artifact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(artifact.name).font(.title2.weight(.semibold)).textSelection(.enabled)
            Text(([model.projectName(work), artifact.inWorktree ? artifact.place : nil] as [String?]).compactMap { $0 }.joined(separator: " · "))
                .font(.callout).foregroundStyle(.secondary)
            if work.files.count > 1 {
                Text("One work in \(work.files.count) files: " + work.files.map(\.name).joined(separator: " → "))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            // What this work may be is said with what it is, before its bytes.
            ForEach(model.organization.suggestions(for: work)) {
                SuggestionView(suggestion: $0, from: work).padding(.top, Space.xs + 2).transition(Motion.arrive)
            }
        }
    }
}

/// A status statement: the mark and its words, then what they mean. It stands in a tinted box
/// only when the person needs to look (amber) or something is gone (red); otherwise it is plain
/// text in its place, so boxes don't stack inside boxes.
struct Panel<Actions: View>: View {
    var statement: Statement
    var eyebrow: String?
    @ViewBuilder var actions: Actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs + 2) {
            if let eyebrow {
                Text(eyebrow.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            }
            StatusLabel(mark: statement.mark, text: statement.title, size: 15).font(.headline)
                .id(statement.title).transition(.opacity)
            Text(statement.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(tinted ? Space.m + 2 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(stroke))
        .animation(Motion.state(reduceMotion), value: statement.title)
    }

    var tinted: Bool { [.attention, .cross, .failed].contains(statement.mark) }

    var fill: Color {
        switch statement.mark {
        case .attention, .failed: Palette.attentionFill
        case .cross: Palette.lostFill
        default: .clear
        }
    }

    var stroke: Color {
        switch statement.mark {
        case .attention, .failed: Palette.attention.opacity(0.35)
        case .cross: Palette.lost.opacity(0.3)
        default: .clear
        }
    }
}

extension Panel where Actions == EmptyView {
    init(statement: Statement, eyebrow: String? = nil) {
        self.init(statement: statement, eyebrow: eyebrow) { EmptyView() }
    }
}

extension Staging {
    var isPreparing: Bool { if case .preparing = self { true } else { false } }
}

/// The selected version's bytes, with one line saying exactly which bytes they are.
struct PreviewPane: View {
    @Environment(LibraryModel.self) private var model
    var artifact: Artifact
    var delivery: Delivery
    var plan: Handoff?
    var staging: Staging

    var body: some View {
        let url: URL? = switch (plan, staging) {
        case (.folder?, _): URL(fileURLWithPath: artifact.path)
        case (_, .ready(let url, _)): url
        default: nil
        }
        let text = plan == .folder ? nil : model.preparedText(for: staging.sha)
        let caption = Wording.bytesCaption(plan, staged: staging.sha, delivery: delivery)
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let url, let text, ["md", "markdown"].contains(url.pathExtension.lowercased()) {
                    MarkdownPreview(text.text)
                } else if let text {
                    TextPreview(text: text.text)
                } else if let url, !Self.neverPreviewed.contains(url.pathExtension.lowercased()) {
                    QuickLookPreview(url: url)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: url == nil ? "eye.slash" : "shippingbox").font(.title2)
                        Text(url != nil ? "No preview for this kind of file. Open it to look inside."
                             : staging.isPreparing ? "Preparing a verified copy…"
                             : plan == nil ? "Checking the file…" : "No preview: these bytes aren’t available")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            if let caption {
                Text(caption + (text?.truncated == true ? " · showing the first 64 KB, Open to read all" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Installers and apps are never opened, mounted or previewed by selection.
    static let neverPreviewed: Set<String> = ["dmg", "pkg", "app", "ipa"]
}

/// Quick Look's compact view leaves plain text and Markdown blank, so those are shown directly.
struct TextPreview: View {
    var text: String

    nonisolated static let textTypes: Set<String> = ["md", "markdown", "txt", "json", "tsv", "csv", "log", "yaml", "yml", "toml", "swift", "py", "js", "ts"]
    nonisolated static let limit = 64 << 10

    nonisolated static func load(_ url: URL) -> (text: String, truncated: Bool)? {
        guard textTypes.contains(url.pathExtension.lowercased()),
              let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: limit + 1) else { return nil }
        return (String(decoding: data.prefix(limit), as: UTF8.self), data.count > limit)
    }

    var body: some View {
        ScrollView {
            Text(text).font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

struct QuickLookPreview: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.autostarts = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }
}

/// Hand-off: the tile and Open act on the verified copy; the Original row acts on the file's
/// location. Each says which.
struct HandoffPanel: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tileHover = false
    var artifact: Artifact
    var delivery: Delivery
    var plan: Handoff
    var onDisk: OnDisk
    var observation: FileObservation

    /// What is staged for this panel's version only.
    var staging: Staging { model.staging(for: plan.sha) }

    var body: some View {
        let statement = Wording.handoff(plan, delivery: delivery, in: artifact, now: observation.state, large: model.isLarge(delivery))
        let disk = Wording.onDisk(onDisk, in: artifact, now: observation)
        VStack(alignment: .leading, spacing: 12) {
            Text(Wording.handoffHeading(delivery)).font(.headline)
            HStack(spacing: 10) {
                tile
                Button("Open") { model.openSelected() }
                    .disabled(openURL == nil)
                    .help("Open the verified copy in its app (⌘O). ⌘C in the list copies it as a file.")
                if let ends = diskComparison {
                    Button("Compare with File on Disk") { model.comparison = ends }
                        .help("Show what changed between delivery \(Wording.number(delivery)) and the file on disk now.")
                }
                if canSave {
                    Button("Save a Copy (\(sizeText))") { Task { await model.saveCopy(of: delivery, artifact: artifact) } }
                        .help("Keep these bytes in Gleaner, so this version survives later edits.")
                }
            }
            .controlSize(.large)
            Panel(statement: statement) { actions }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("On disk now:").foregroundStyle(.secondary)
                    StatusLabel(mark: disk.mark, text: disk.title)
                }
                HStack(spacing: 8) {
                    Text("Original:").foregroundStyle(.secondary)
                    Text((artifact.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button(sourceExists ? "Show in Finder" : "Show Folder") { model.reveal(artifact) }
                        .help(sourceExists ? "Select the original file in Finder." : "The file isn’t there; show the folder it was in.")
                    CopyButton(title: "Copy Path", text: artifact.path) { model.copy($0) }
                        .help("Copies where the original lives. The file there may change; drag or ⌘C hands over the verified copy.")
                }
            }
            .font(.callout)
            .controlSize(.small)
        }
        .padding(Space.l)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.card + 2))
        .overlay(RoundedRectangle(cornerRadius: Radius.card + 2).strokeBorder(Color(nsColor: .separatorColor)))
    }

    /// The thing you drag: the file itself, labeled with the exact version it carries.
    @ViewBuilder var tile: some View {
        let ready = openURL
        HStack(spacing: Space.m - 2) {
            // The file handed over: the artifact mark, where a drag starts.
            GlyphView(glyph: .artifact, size: 22).foregroundStyle(ready == nil ? .tertiary : .secondary)
            TypeBadge(artifact: artifact)
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(ready == nil ? .secondary : .primary)
                Text(tileCaption).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    .contentTransition(.opacity)
            }
            if staging.isPreparing { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, Space.m)
        .frame(minHeight: 52)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.card))
        // Nothing to hand over reads in the outline too, not only in a fainter tile.
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(
            ready == nil ? Color(nsColor: .separatorColor) : Color.primary.opacity(tileHover ? 0.5 : 0.22),
            style: StrokeStyle(lineWidth: 1, dash: ready == nil ? [5, 4] : [])))
        .onHover { hovering in withAnimation(Motion.feedback(reduceMotion)) { tileHover = hovering && ready != nil } }
        .onDrag {
            // Decided now, not when the tile was drawn: the copy may have changed since.
            guard ready != nil else { return NSItemProvider() }
            return model.tileItem(plan, artifact: artifact)
        }
        .help(ready == nil ? "Nothing to drag for this version" : "Drag into Finder, a chat, or an upload field")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drag \(artifact.name), \(Wording.tileVersion(staged: staged, plan: plan, delivery: delivery, in: artifact))")
        .accessibilityValue(tileCaption)
        .accessibilityHint(ready == nil ? "" : "Drag into another app, or choose File > Open Verified Copy.")
    }

    /// The bytes ready to drag, when a copy is.
    var staged: String? {
        if case .ready(_, let sha) = staging { sha } else { nil }
    }

    var tileCaption: String {
        switch staging {
        case .ready(_, let sha):
            return "\(Wording.tileVersion(staged: sha, plan: plan, delivery: delivery, in: artifact)) · \(sha.prefix(12))…"
        case .preparing: return "verifying…"
        case .failed(let why, _): return why
        case .idle: return plan == .folder ? "folder as it is now" : "not available"
        }
    }

    @ViewBuilder var actions: some View {
        switch plan {
        case .unavailable(let k?, _):
            if let other = artifact.deliveries.first(where: { $0.number == k }) {
                Button("Hand Off Delivery \(Wording.number(other)) Instead") { model.chosenDelivery = other.id }
            }
        case .unavailable(nil, let current?):
            Button("Hand Off the Current File") { Task { await model.stage(sha: current, artifact: artifact) } }
        case .restoreFromGit:
            if let command = observation.state.restoreCommand {
                HStack {
                    Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                    Button("Copy Command") { copy(command) }
                }
            }
        default:
            EmptyView()
        }
        if case .failed(let why, _) = staging {
            HStack {
                StatusLabel(mark: .attention, text: why).font(.callout)
                Button("Check Again") { Task { await model.checkAgain(artifact) } }
                    .help("Check the file now and prepare its copy again.")
            }
        }
        if let failure = model.actionFailure(artifact, delivery) {
            StatusLabel(mark: .attention, text: failure).font(.callout)
        }
    }

    var sourceExists: Bool { observation.state.kind != .missing }

    /// Offered when the file on disk is no longer this delivery and both versions can be read.
    var diskComparison: (from: Comparison.End, to: Comparison.End)? {
        guard plan != .folder, let current = model.currentEnd(artifact), current.sha != delivery.sha256,
              let delivered = model.compareEnd(delivery, artifact: artifact) else { return nil }
        return (delivered, current)
    }

    var canSave: Bool {
        guard let sha = delivery.sha256, !model.hasSaved(sha) else { return false }
        return observation.state.sha256 == sha
    }

    var sizeText: String {
        observation.state.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
    }

    var openURL: URL? {
        if plan == .folder { return URL(fileURLWithPath: artifact.path) }
        if case .ready(let url, _) = staging { return url }
        return nil
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Why this file is here: the request and the reply that handed it over, what else that reply
/// named, and how to go back to the conversation.
struct ReplySection: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var artifact: Artifact
    var delivery: Delivery
    @State private var showsAll = false

    /// Siblings listed before "Show All".
    static let shown = 6

    var body: some View {
        let others = model.siblings[delivery.id] ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text("Delivered \(Wording.date(delivery.deliveredAt)) by \(Wording.provider(delivery.provider)) · “\(delivery.sessionTitle ?? "Untitled session")”")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let request = delivery.request {
                (Text("You asked: ").foregroundStyle(.secondary) + Text("“\(request)”"))
                    .font(.callout).lineLimit(4).textSelection(.enabled)
            }
            // The agent's own words, quoted beside a rule: what the reply said, not a status.
            ForEach(Array(delivery.evidence.enumerated()), id: \.offset) { _, item in
                Text(item.excerpt)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(.leading, Space.m)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 2) }
            }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delivered with (\(others.count)):").font(.caption).foregroundStyle(.secondary)
                    FlowLayout(spacing: 10) {
                        ForEach(showsAll ? others : Array(others.prefix(Self.shown))) { other in
                            LinkButton(title: (other.path as NSString).lastPathComponent) { model.select(other) }
                                .font(.caption)
                                .help(Wording.siblingHelp(other))
                                .transition(Motion.arrive)
                        }
                        if others.count > Self.shown {
                            Button(showsAll ? "Show Fewer" : "Show All \(others.count)") {
                                withAnimation(Motion.state(reduceMotion)) { showsAll.toggle() }
                            }
                            .buttonStyle(.link).font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            ConversationRow(delivery: delivery)
        }
        .onChange(of: delivery.id) { showsAll = false }
    }
}

/// Going back to the conversation: a command to copy where the agent documents one and the
/// conversation can still be resumed, else why not. Gleaner never opens a log as if it were it.
struct ConversationRow: View {
    @Environment(LibraryModel.self) private var model
    var delivery: Delivery

    var body: some View {
        let resume = model.resume(delivery)
        HStack(alignment: .center, spacing: Space.s) {
            GlyphView(glyph: .terminal, size: 14).foregroundStyle(.secondary)
            Text("Conversation").font(.caption).foregroundStyle(.secondary)
            switch resume {
            case .command(let command):
                Text(command).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                CopyButton(title: "Copy Resume Command", text: command) { model.copy($0) }
                    .controlSize(.small)
                    .help(Wording.resumeHelp(delivery.provider))
                    .id(delivery.id)
            default:
                Text(Wording.resume(resume)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Lays its views out in rows, wrapping to the width it is given.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var width: CGFloat = 0, height: CGFloat = 0
        for (index, row) in rows(subviews, width: proposal.width ?? .infinity).enumerated() {
            let sizes = row.map { $0.sizeThatFits(.unspecified) }
            let rowWidth: CGFloat = sizes.reduce(0) { $0 + $1.width } + CGFloat(row.count - 1) * spacing
            width = max(width, rowWidth)
            height += (sizes.map(\.height).max() ?? 0) + (index > 0 ? spacing / 2 : 0)
        }
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + spacing / 2
        }
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]], x: CGFloat = 0
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if x > 0, x + w > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append(view)
            x += w + spacing
        }
        return rows.filter { !$0.isEmpty }
    }
}

/// One line per delivery of the work, across its files; picking one switches the preview and the
/// hand-off together.
struct DeliveriesSection: View {
    @Environment(LibraryModel.self) private var model
    var work: Work
    var selected: Delivery

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Deliveries, newest first").font(.headline)
            ForEach(work.deliveries) { delivery in
                HStack(spacing: 8) {
                    Button { model.chosenDelivery = delivery.id } label: { row(delivery) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(spoken(delivery))
                        .accessibilityAddTraits(delivery.id == selected.id ? .isSelected : [])
                    if let ends = ends(delivery) {
                        Button("Compare") { model.comparison = ends }
                            .controlSize(.small)
                            .help("Show what changed between this delivery and the selected one.")
                    }
                }
            }
        }
    }

    /// This delivery against the selected one, older first, when both versions can be read and differ.
    func ends(_ delivery: Delivery) -> (from: Comparison.End, to: Comparison.End)? {
        guard delivery.id != selected.id, delivery.sha256 != selected.sha256,
              let a = model.compareEnd(delivery, artifact: work.file(of: delivery), named: work.files.count > 1),
              let b = model.compareEnd(selected, artifact: work.file(of: selected), named: work.files.count > 1) else { return nil }
        let older = (delivery.deliveredAt ?? .distantPast) < (selected.deliveredAt ?? .distantPast)
        return older ? (a, b) : (b, a)
    }

    /// An earlier delivery of the same file with the same bytes; another file's is named with its name.
    func sameAs(_ delivery: Delivery) -> Delivery? {
        let earlier = work.deliveries.drop { $0.id != delivery.id }.dropFirst()
        return earlier.first { $0.path == delivery.path && $0.sha256 != nil && $0.sha256 == delivery.sha256 }
            ?? earlier.first { $0.sha256 != nil && $0.sha256 == delivery.sha256 }
    }

    func spoken(_ delivery: Delivery) -> String {
        let earlier = sameAs(delivery)
        var line = Wording.deliveryLine(delivery, sameAs: earlier?.path == delivery.path ? earlier : nil)
        if let earlier, earlier.path != delivery.path {
            line += ", same bytes as \((earlier.path as NSString).lastPathComponent) \(Wording.number(earlier))"
        }
        return work.files.count > 1 ? (delivery.path as NSString).lastPathComponent + ", " + line : line
    }

    func row(_ delivery: Delivery) -> some View {
        let isSelected = delivery.id == selected.id
        let provenance = Wording.provenanceShort(delivery.capture)
        let earlier = sameAs(delivery)
        let name = (delivery.path as NSString).lastPathComponent
        return HStack(spacing: Space.m) {
            if work.files.count > 1 { Text(name).fontWeight(isSelected ? .semibold : .regular).lineLimit(1).truncationMode(.middle) }
            Text("Delivery \(delivery.number)").fontWeight(isSelected && work.files.count == 1 ? .semibold : .regular)
            Text(Wording.date(delivery.deliveredAt)).foregroundStyle(.secondary).monospacedDigit()
            Text(Wording.provider(delivery.provider)).foregroundStyle(.secondary)
            if isSelected { Text("shown above").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if let earlier {
                Text(earlier.path == delivery.path ? "same as \(Wording.number(earlier))"
                     : "same bytes as \((earlier.path as NSString).lastPathComponent) \(Wording.number(earlier))")
                    .foregroundStyle(.secondary)
            }
            StatusLabel(mark: provenance.0, text: provenance.1)
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isSelected ? Color.primary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control + 2))
        .overlay(RoundedRectangle(cornerRadius: Radius.control + 2).strokeBorder(
            isSelected ? Color.primary.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: isSelected ? 1.5 : 1))
        .contentShape(Rectangle())
    }
}

/// The full record for the selected delivery, for when the short answer isn't enough.
struct DetailsSection: View {
    @Environment(LibraryModel.self) private var model
    var artifact: Artifact
    var delivery: Delivery
    var observation: FileObservation?

    var body: some View {
        DisclosureGroup("Details: path, hashes, session log") {
            let capture = delivery.capture
            let provenance = Wording.provenance(capture)
            let storage = Wording.storage(delivery, hasSaved: delivery.sha256.map(model.hasSaved) ?? false,
                                          large: model.isLarge(delivery), now: observation?.state)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                row("Path", artifact.path, mono: true)
                if let observation {
                    row("On disk", [observation.state.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
                                    "git " + observation.state.git.rawValue.replacingOccurrences(of: "_", with: " "),
                                    "checked \(Wording.date(observation.checkedAt))"].compactMap { $0 }.joined(separator: " · "))
                }
                row("Delivery \(delivery.number)", provenance.1)
                row("Storage", storage.1)
                row("sha256", delivery.sha256 ?? "not recorded", mono: true)
                if let capture { row("First looked", Wording.date(capture.observedAt)) }
                if let saved = capture?.savedAt { row("Saved", Wording.date(saved)) }
                row("Session log", delivery.logPath, mono: true)
            }
            .padding(.top, 8)
        }
        .font(.callout)
    }

    func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value)
                .font(mono ? .system(.caption, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
