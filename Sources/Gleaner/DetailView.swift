import AppKit
import GleanerCore
import Quartz
import GleanerUI
import SwiftUI

/// One delivered file, laid out as Finder's preview pane lays out a file: the file itself to drag
/// and open, its bytes, then its information. What needs a look is said under the file's name;
/// what is as it should be is said by a mark (rulings §5).
struct DetailView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var result: SearchResult

    var body: some View {
        let work = result.work
        let artifact = model.file(in: result)
        let delivery = model.delivery(in: result)
        let observation = model.observations[artifact.path]
        let onDisk = observation.map { artifact.onDisk($0, hasSaved: model.hasSaved) }
        let plan = observation.map { artifact.handoff(delivery, now: $0, hasSaved: model.hasSaved) }
        let staging = model.staging(for: plan?.sha)
        let suggestions = model.organization.suggestions(for: work)

        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.m) {
                    // A new selection is a new view: nothing animates between two files.
                    DetailHeader(artifact: artifact, delivery: delivery, plan: plan, staging: staging, observation: observation)
                        .id("\(artifact.id)|\(delivery.id)")
                    ForEach(suggestions) { SuggestionView(suggestion: $0, from: work).transition(Motion.arrive(reduceMotion)) }
                }
                .animation(Motion.state(reduceMotion), value: suggestions.map(\.id))
                if let comparison = model.comparison {
                    ComparePane(artifact: artifact, from: comparison.from, to: comparison.to)
                } else {
                    PreviewPane(artifact: artifact, plan: plan, staging: staging)
                }
                InformationSection(artifact: artifact, delivery: delivery, plan: plan, onDisk: onDisk, observation: observation)
                if work.deliveries.count > 1 {
                    VersionsSection(work: work, selected: delivery)
                }
                WorkSection(work: work).id(work.id)
                MoreInfoSection(artifact: artifact, delivery: delivery, observation: observation)
            }
            .padding(Space.xl)
            .frame(maxWidth: 880, alignment: .leading)
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
}

/// The file, as the thing you drag: its own icon and name, which bytes they are, and whether
/// Gleaner vouches for them. Open and Show in Finder sit beside it; the rest is in the menu. When
/// the version can't be handed over, the reason and what can be done instead follow.
struct DetailHeader: View {
    @Environment(LibraryModel.self) private var model
    var artifact: Artifact
    var delivery: Delivery
    var plan: Handoff?
    var staging: Staging
    var observation: FileObservation?

    var body: some View {
        let statement = plan.map { Wording.handoff($0, delivery: delivery, in: artifact, now: observation!.state, large: model.isLarge(delivery)) }
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .center, spacing: Space.m) {
                tile(statement)
                Spacer(minLength: Space.s)
                Button("Open") { model.openSelected() }
                    .disabled(openURL == nil)
                    .help("Open the verified copy (⌘O)")
                Button("Show in Finder") { model.reveal(artifact) }
                    .help(sourceExists ? "Show the original in Finder (⇧⌘R)" : "The file is gone; show its folder")
                Menu {
                    menu
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                .accessibilityLabel("More")
            }
            if let statement, let plan, showsPanel(statement, plan) {
                StatusPanel(statement: statement) { actions(plan) }
            }
            if case .failed(let why, _) = staging {
                StatusPanel(statement: Statement(mark: .attention, title: "Couldn’t prepare a copy", detail: why)) {
                    Button("Check Again") { Task { await model.checkAgain(artifact) } }
                }
            }
            if let failure = model.actionFailure(artifact, delivery) {
                StatusLabel(mark: .attention, text: failure).font(.callout)
            }
        }
    }

    /// The thing you drag, labeled with the exact version it carries.
    func tile(_ statement: Statement?) -> some View {
        let ready = openURL != nil
        let status = caption(statement)
        return HStack(spacing: Space.m) {
            FileIcon(path: artifact.path, folder: artifact.kind == .folder, size: 48)
                .opacity(ready ? 1 : 0.45)
                .overlay(alignment: .bottomTrailing) {
                    if staging.isPreparing { ProgressView().controlSize(.mini).offset(x: 4, y: 4) }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(artifact.name).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: Space.s) {
                    StatusLabel(mark: status.mark, text: status.text)
                    Text(Wording.bytesCaption(plan, staged: staged, delivery: delivery)).foregroundStyle(.secondary)
                    if let staged { Text(staged.prefix(8)).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary) }
                }
                .font(.callout)
                .lineLimit(1)
            }
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.s)
        .hoverWash(ready)
        .padding(.horizontal, -Space.s)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .pointerStyle(ready ? .grabIdle : nil)
        .onDrag {
            // Decided now, not when the tile was drawn: the copy may have changed since.
            guard ready, let plan else { return NSItemProvider() }
            return model.tileItem(plan, artifact: artifact)
        }
        .help(ready ? "Drag to hand over \(Wording.tileVersion(staged: staged, plan: plan ?? .folder, delivery: delivery, in: artifact))" : "Nothing to hand over for this version")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(artifact.name), \(plan.map { Wording.tileVersion(staged: staged, plan: $0, delivery: delivery, in: artifact) } ?? Wording.compareTitle(delivery))")
        .accessibilityValue(status.text)
        .accessibilityHint(ready ? "Drag into another app, or choose File > Open Verified Copy." : "")
    }

    /// The tile's status, in a word or two: what the panel below says in full.
    func caption(_ statement: Statement?) -> (mark: Mark, text: String) {
        switch (plan, staging) {
        case (nil, _): (.running, "Checking…")
        case (_, .preparing): (.running, "Verifying…")
        case (_, .failed): (.attention, "Not prepared")
        case (.folder?, _): (.na, "Folder")
        case (.ready?, _): (statement!.mark, statement!.title)
        case (.unavailable(_, let current?)?, .ready(_, let sha)) where sha == current: (.attention, "Not a found delivery")
        case (.lost?, _): (.cross, "Lost")
        case (.restoreFromGit?, _): (.dashed, "In git only")
        case (.unavailable?, _): (.attention, "Unavailable")
        }
    }

    /// The panel says what the caption can't: a caveat, or why nothing can be handed over.
    func showsPanel(_ statement: Statement, _ plan: Handoff) -> Bool {
        switch plan {
        case .ready(_, _, nil), .folder: false
        default: true
        }
    }

    @ViewBuilder func actions(_ plan: Handoff) -> some View {
        switch plan {
        case .unavailable(let k?, _):
            if let other = artifact.deliveries.first(where: { $0.number == k }) {
                Button("Hand Off Delivery \(Wording.number(other)) Instead") { model.chosenDelivery = other.id }
            }
        case .unavailable(nil, let current?):
            Button("Hand Off the Current File") { Task { await model.stage(sha: current, artifact: artifact) } }
        case .restoreFromGit:
            if let command = observation?.state.restoreCommand {
                HStack {
                    Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                    CopyButton(title: "Copy Command", text: command) { model.copy($0) }.id(command)
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder var menu: some View {
        Button("Quick Look") { model.toggleQuickLook() }.disabled(openURL == nil)
        Divider()
        Button("Copy Path") { model.copyPath(artifact) }
        if case .command(let command) = model.resume(delivery) {
            Button("Copy Resume Command") { model.copy(command) }
        }
        if canSave {
            Divider()
            Button("Save a Copy (\(sizeText))") { Task { await model.saveCopy(of: delivery, artifact: artifact) } }
        }
    }

    var sourceExists: Bool { observation?.state.kind != .missing }

    /// The bytes ready to drag, when a copy is.
    var staged: String? {
        if case .ready(_, let sha) = staging { sha } else { nil }
    }

    var canSave: Bool {
        guard let sha = delivery.sha256, !model.hasSaved(sha) else { return false }
        return observation?.state.sha256 == sha
    }

    var sizeText: String {
        observation?.state.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
    }

    var openURL: URL? {
        if plan == .folder { return URL(fileURLWithPath: artifact.path) }
        if case .ready(let url, _) = staging { return url }
        return nil
    }
}

extension Staging {
    var isPreparing: Bool { if case .preparing = self { true } else { false } }
}

/// The selected version's bytes, drawn as a page: as tall as the text, up to a limit past which it
/// scrolls. The header above names which bytes they are.
struct PreviewPane: View {
    @Environment(LibraryModel.self) private var model
    var artifact: Artifact
    var plan: Handoff?
    var staging: Staging
    @State private var textHeight: CGFloat = 0

    static let tallest: CGFloat = 480

    var body: some View {
        let url: URL? = switch (plan, staging) {
        case (.folder?, _): URL(fileURLWithPath: artifact.path)
        case (_, .ready(let url, _)): url
        default: nil
        }
        let text = plan == .folder ? nil : model.preparedText(for: staging.sha)
        Group {
            if let url, let text {
                ScrollView {
                    Group {
                        if ["md", "markdown"].contains(url.pathExtension.lowercased()) {
                            MarkdownPreview(text.text)
                        } else {
                            Text(text.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Space.l)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                }
                .scrollDisabled(textHeight <= Self.tallest)
                .frame(height: min(max(textHeight, 96), Self.tallest))
                .overlay(alignment: .bottomTrailing) {
                    if text.truncated {
                        Text("First 64 KB").font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, Space.s).padding(.vertical, 2)
                            .surface(.floating, in: Capsule())
                            .padding(Space.s)
                            .help("Open it to read the rest.")
                    }
                }
            } else if let url, !Self.neverPreviewed.contains(url.pathExtension.lowercased()) {
                QuickLookPreview(url: url).frame(height: 360)
            } else {
                VStack(spacing: Space.s) {
                    FileIcon(path: artifact.path, folder: artifact.kind == .folder, size: 64).opacity(url == nil ? 0.4 : 1)
                    Text(url != nil ? "No preview" : staging.isPreparing ? "Verifying…" : plan == nil ? "Checking…" : "No bytes to show")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity)
        .surface(.page)
    }

    /// Installers and apps are never opened, mounted or previewed by selection.
    static let neverPreviewed: Set<String> = ["dmg", "pkg", "app", "ipa"]
}

/// Quick Look's compact view leaves plain text and Markdown blank, so those are shown directly.
enum TextPreview {
    nonisolated static let textTypes: Set<String> = ["md", "markdown", "txt", "json", "tsv", "csv", "log", "yaml", "yml", "toml", "swift", "py", "js", "ts"]
    nonisolated static let limit = 64 << 10

    nonisolated static func load(_ url: URL) -> (text: String, truncated: Bool)? {
        guard textTypes.contains(url.pathExtension.lowercased()),
              let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: limit + 1) else { return nil }
        return (String(decoding: data.prefix(limit), as: UTF8.self), data.count > limit)
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

/// What the delivery is: the request, the reply that handed it over, the agent and conversation,
/// when, where the file is now, and what else that reply named.
struct InformationSection: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var artifact: Artifact
    var delivery: Delivery
    var plan: Handoff?
    var onDisk: OnDisk?
    var observation: FileObservation?
    @State private var showsAll = false

    /// Siblings listed before "Show All".
    static let shown = 6

    var body: some View {
        let others = model.siblings[delivery.id] ?? []
        DetailSection(title: "Information") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.s + 2) {
                if let request = delivery.request {
                    InfoRow(label: "Request") { Text("“\(request)”").lineLimit(6).textSelection(.enabled) }
                }
                if !delivery.evidence.isEmpty {
                    InfoRow(label: "Reply") {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            // The agent's own words, quoted beside a rule: what the reply said, not a status.
                            ForEach(Array(delivery.evidence.enumerated()), id: \.offset) { _, item in
                                Text(Self.excerpt(item.excerpt))
                                    .textSelection(.enabled)
                                    .padding(.leading, Space.s + 2)
                                    .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
                                    .help(item.excerpt)
                            }
                        }
                    }
                }
                InfoRow(label: "Agent") {
                    HStack(spacing: Space.s) {
                        AgentMark(provider: delivery.provider, size: 16, color: true)
                        Text(delivery.sessionTitle ?? "Untitled conversation").lineLimit(1).truncationMode(.tail)
                        resume
                    }
                }
                if let name = delivery.model {
                    InfoRow(label: "Model") {
                        HStack(spacing: Space.s) {
                            if let vendor = ModelVendor.of(model: name) { VendorMark(vendor: vendor, size: 14).foregroundStyle(.secondary) }
                            Text(name).textSelection(.enabled)
                            if let gateway = delivery.modelProvider, gateway != "openai" {
                                Text("via \(gateway)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                InfoRow("Delivered", Wording.date(delivery.deliveredAt))
                if let onDisk, let observation {
                    let disk = Wording.onDisk(onDisk, in: artifact, now: observation)
                    InfoRow(label: "On Disk") {
                        HStack(spacing: Space.s) {
                            StatusLabel(mark: disk.mark, text: disk.title).id(disk.title)
                            InfoButton(text: disk.detail)
                            if let ends = diskComparison {
                                Button("Compare") { model.comparison = ends }
                                    .controlRole(.inline)
                                    .help("Compare delivery \(Wording.number(delivery)) with the file on disk")
                            }
                        }
                    }
                }
                InfoRow(label: "Location") {
                    HStack(spacing: Space.s) {
                        Text(Wording.tilde(artifact.path)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            .help(artifact.path)
                        CopyButton(title: "Copy", text: artifact.path) { model.copy($0) }
                            .controlRole(.inline)
                            .help("Copy the original’s path. The file there may change; drag the file above to hand over the verified copy.")
                            .id(artifact.path)
                    }
                }
                if !others.isEmpty {
                    InfoRow(label: "Delivered With") {
                        FlowLayout(spacing: Space.m) {
                            ForEach(showsAll ? others : Array(others.prefix(Self.shown))) { other in
                                LinkButton(title: (other.path as NSString).lastPathComponent) { model.select(other) }
                                    .help(Wording.siblingHelp(other))
                                    .transition(Motion.arrive(reduceMotion))
                            }
                            if others.count > Self.shown {
                                Button(showsAll ? "Show Fewer" : "\(others.count - Self.shown) More") {
                                    withAnimation(Motion.state(reduceMotion)) { showsAll.toggle() }
                                }
                                .buttonStyle(.quiet)
                            }
                        }
                    }
                }
            }
            .font(.callout)
        }
        .onChange(of: delivery.id) { showsAll = false }
    }

    /// Going back to the conversation: a command to copy where the agent documents one and the
    /// conversation can still be resumed, else why not. Gleaner never opens a log as if it were it.
    @ViewBuilder var resume: some View {
        switch model.resume(delivery) {
        case .command(let command):
            CopyButton(title: "Copy Resume Command", text: command) { model.copy($0) }
                .controlRole(.inline)
                .help("Copies “\(command)”. Paste it in Terminal to continue in \(Wording.provider(delivery.provider)).")
                .id(delivery.id)
        case let other:
            Text(Wording.resume(other)).foregroundStyle(.secondary)
        }
    }

    /// Offered when the file on disk is no longer this delivery and both versions can be read.
    var diskComparison: (from: Comparison.End, to: Comparison.End)? {
        guard plan != .folder, let current = model.currentEnd(artifact), current.sha != delivery.sha256,
              let delivered = model.compareEnd(delivery, artifact: artifact) else { return nil }
        return (delivered, current)
    }

    /// The reply's own Markdown, read as text: emphasis and code kept, links not clickable.
    static func excerpt(_ text: String) -> AttributedString {
        guard var attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return AttributedString(text) }
        let links = attributed.runs.filter { $0.link != nil }.map(\.range)
        for range in links { attributed[range].link = nil }
        return attributed
    }
}

/// Every delivery of the work, across its files, newest first, as one table: picking a row
/// switches the file above and its bytes together. Gleaner saw most deliveries' bytes as they
/// arrived, so that row shows only its mark; the exceptions say so in words.
struct VersionsSection: View {
    @Environment(LibraryModel.self) private var model
    var work: Work
    var selected: Delivery

    var body: some View {
        DetailSection(title: "Versions") {
            VStack(spacing: 0) {
                ForEach(Array(work.deliveries.enumerated()), id: \.element.id) { index, delivery in
                    if index > 0 { Divider().padding(.leading, 28) }
                    row(delivery)
                }
            }
        }
    }

    func row(_ delivery: Delivery) -> some View {
        let isSelected = delivery.id == selected.id
        let provenance = Wording.provenanceShort(delivery.capture)
        let earlier = sameAs(delivery)
        return HStack(spacing: Space.m) {
            GlyphView(glyph: provenance.0.glyph, size: 12).foregroundStyle(provenance.0.color)
                .frame(width: 16)
                .help(provenance.1)
            Text("Delivery \(delivery.number)").fontWeight(isSelected ? .semibold : .regular)
                .frame(width: 84, alignment: .leading)
            if work.files.count > 1 {
                Text((delivery.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                    .frame(width: 180, alignment: .leading)
            }
            Text(Wording.date(delivery.deliveredAt)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                .frame(width: 150, alignment: .leading)
            AgentMark(provider: delivery.provider, size: 13).foregroundStyle(.secondary)
            if provenance.0 != .solid {
                Text(provenance.1).foregroundStyle(.secondary).lineLimit(1)
            }
            if let earlier {
                Text(earlier.path == delivery.path ? "Same as \(Wording.number(earlier))"
                     : "Same as \((earlier.path as NSString).lastPathComponent) \(Wording.number(earlier))")
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Space.s)
            // Every row keeps the column, so the right edge holds.
            ZStack(alignment: .trailing) {
                Color.clear.frame(width: 72, height: 1)
                if let ends = ends(delivery) {
                    Button("Compare") { model.comparison = ends }
                        .controlRole(.inline)
                        .help("Compare with delivery \(Wording.number(selected))")
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, Space.s)
        .frame(minHeight: 30)
        .background(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear,
                    in: RoundedRectangle(cornerRadius: Radius.tag + 2))
        .contentShape(Rectangle())
        .onTapGesture { model.chosenDelivery = delivery.id }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(delivery))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.chosenDelivery = delivery.id }
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
        if delivery.id == selected.id { line += ", shown" }
        return work.files.count > 1 ? (delivery.path as NSString).lastPathComponent + ", " + line : line
    }
}

/// The full record for the selected delivery, for when the short answer isn't enough.
struct MoreInfoSection: View {
    @Environment(LibraryModel.self) private var model
    var artifact: Artifact
    var delivery: Delivery
    var observation: FileObservation?

    var body: some View {
        DisclosureGroup("More Info") {
            let capture = delivery.capture
            let provenance = Wording.provenance(capture)
            let storage = Wording.storage(delivery, hasSaved: delivery.sha256.map(model.hasSaved) ?? false,
                                          large: model.isLarge(delivery), now: observation?.state)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.s) {
                InfoRow(label: "Path") { mono(artifact.path) }
                InfoRow(label: "Delivery \(delivery.number)") { StatusLabel(mark: provenance.0, text: provenance.1) }
                InfoRow(label: "Copy") { StatusLabel(mark: storage.0, text: storage.1) }
                InfoRow(label: "SHA-256") { mono(delivery.sha256 ?? "Not recorded") }
                if let capture { InfoRow("First Looked", Wording.date(capture.observedAt)) }
                if let saved = capture?.savedAt { InfoRow("Saved", Wording.date(saved)) }
                if let observation {
                    InfoRow("On Disk", [observation.state.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
                                        "git " + observation.state.git.rawValue.replacingOccurrences(of: "_", with: " "),
                                        "checked \(Wording.date(observation.checkedAt))"].compactMap { $0 }.joined(separator: " · "))
                }
                InfoRow(label: "Session Log") { mono(delivery.logPath) }
            }
            .font(.callout)
            .padding(.top, Space.s)
        }
        .font(.headline)
    }

    func mono(_ text: String) -> some View {
        Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
}
