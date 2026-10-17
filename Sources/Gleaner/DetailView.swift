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
        let artifact = result.artifact
        let delivery = model.delivery(in: result)
        let observation = model.observations[artifact.path]
        let onDisk = observation.map { artifact.onDisk($0, hasSaved: model.hasSaved) }
        let plan = observation.map { artifact.handoff(delivery, now: $0, hasSaved: model.hasSaved) }
        let staging = model.staging(for: plan?.sha)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(artifact)
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
                if artifact.deliveries.count > 1 {
                    DeliveriesSection(artifact: artifact, selected: delivery)
                }
                DetailsSection(artifact: artifact, delivery: delivery, observation: observation)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .task(id: artifact.id) {
            model.clearStaging()
            await model.observe(artifact)
        }
        .task(id: "\(artifact.id)|\(delivery.id)|\(observation?.checkedAt.timeIntervalSince1970 ?? 0)|\(model.stagingGeneration)") {
            if case .ready(let sha, _, _) = plan {
                await model.stage(sha: sha, artifact: artifact)
            } else {
                model.clearStaging()
            }
        }
    }

    func header(_ artifact: Artifact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(artifact.name).font(.title2.weight(.semibold)).textSelection(.enabled)
            Text(([model.projectName(artifact), artifact.inWorktree ? artifact.place : nil] as [String?]).compactMap { $0 }.joined(separator: " · "))
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// The eyebrow-titled status block. Amber or red only when the person needs to look.
struct Panel<Actions: View>: View {
    var statement: Statement
    var eyebrow: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            }
            StatusLabel(mark: statement.mark, text: statement.title).font(.headline)
            Text(statement.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(stroke))
    }

    var fill: Color {
        switch statement.mark {
        case .attention: Palette.attentionFill
        case .cross: Palette.lostFill
        default: Color(nsColor: .controlBackgroundColor)
        }
    }

    var stroke: Color {
        switch statement.mark {
        case .attention: Palette.attention.opacity(0.35)
        case .cross: Palette.lost.opacity(0.3)
        default: Color(nsColor: .separatorColor)
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
        let text = url.flatMap(TextPreview.load)
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

    static let textTypes: Set<String> = ["md", "markdown", "txt", "json", "tsv", "csv", "log", "yaml", "yml", "toml", "swift", "py", "js", "ts"]
    static let limit = 64 << 10

    static func load(_ url: URL) -> (text: String, truncated: Bool)? {
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
            Text("Hand off delivery \(delivery.number)").font(.headline)
            HStack(spacing: 10) {
                tile
                Button("Open") { model.openSelected() }
                    .disabled(openURL == nil)
                    .help("Open the verified copy in its app (⌘O). ⌘C in the list copies it as a file.")
                if let ends = diskComparison {
                    Button("Compare with File on Disk") { model.comparison = ends }
                        .help("Show what changed between delivery \(delivery.number) and the file on disk now.")
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
                    Button("Copy Path") { model.copyPath(artifact) }
                        .help("Copies where the original lives. The file there may change; drag or ⌘C hands over the verified copy.")
                }
            }
            .font(.callout)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
    }

    /// The thing you drag: the file itself, labeled with the exact version it carries.
    @ViewBuilder var tile: some View {
        let ready = openURL
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityHidden(true)
            TypeBadge(artifact: artifact)
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                Text(tileCaption).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            if staging.isPreparing { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ready == nil ? Color(nsColor: .separatorColor) : Palette.selection.opacity(0.6)))
        .opacity(ready == nil ? 0.55 : 1)
        .onDrag {
            guard let ready else { return NSItemProvider() }
            return NSItemProvider(contentsOf: ready) ?? NSItemProvider()
        }
        .help(ready == nil ? "Nothing to drag for this version" : "Drag into Finder, a chat, or an upload field")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drag \(artifact.name), delivery \(delivery.number)")
        .accessibilityValue(tileCaption)
        .accessibilityHint(ready == nil ? "" : "Drag into another app, or choose File > Open Verified Copy.")
    }

    var tileCaption: String {
        switch staging {
        case .ready(_, let sha):
            let label = artifact.deliveries.first { $0.sha256 == sha && $0.isTrusted }.map { "delivery \($0.number)" }
                ?? (sha == delivery.sha256
                    ? "delivery \(delivery.number)" + (delivery.capture?.provenance == .firstSeenAfterDelivery ? " · first seen later" : "")
                    : "current file · not a found delivery")
            return "\(label) · \(sha.prefix(12))…"
        case .preparing: return "verifying…"
        case .failed(let why, _): return why
        case .idle: return plan == .folder ? "folder as it is now" : "not available"
        }
    }

    @ViewBuilder var actions: some View {
        switch plan {
        case .unavailable(let k?, _):
            if let other = artifact.deliveries.first(where: { $0.number == k }) {
                Button("Hand Off Delivery \(k) Instead") { model.chosenDelivery = other.id }
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
            StatusLabel(mark: .attention, text: why).font(.callout)
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

/// Why this file is here: the request and the reply that handed it over, and what else that
/// reply named.
struct ReplySection: View {
    @Environment(LibraryModel.self) private var model
    var artifact: Artifact
    var delivery: Delivery

    var body: some View {
        let others = model.siblings[delivery.id] ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text("Delivered \(Wording.date(delivery.deliveredAt)) by \(Wording.provider(delivery.provider)) · “\(delivery.sessionTitle ?? "Untitled session")”")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let request = delivery.request {
                (Text("You asked: ").foregroundStyle(.secondary) + Text("“\(request)”"))
                    .font(.callout).lineLimit(4).textSelection(.enabled)
            }
            ForEach(Array(delivery.evidence.enumerated()), id: \.offset) { _, item in
                Text(item.excerpt)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            if !others.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Delivered with:").font(.caption).foregroundStyle(.secondary)
                    ForEach(others.prefix(6)) { other in
                        Button((other.path as NSString).lastPathComponent) { model.select(other) }
                            .buttonStyle(.link).font(.caption)
                    }
                    if others.count > 6 { Text("and \(others.count - 6) more").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

/// One line per delivery; picking one switches the preview and the hand-off together.
struct DeliveriesSection: View {
    @Environment(LibraryModel.self) private var model
    var artifact: Artifact
    var selected: Delivery

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Deliveries").font(.headline)
            ForEach(artifact.deliveries) { delivery in
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
              let a = model.compareEnd(delivery, artifact: artifact),
              let b = model.compareEnd(selected, artifact: artifact) else { return nil }
        return delivery.number < selected.number ? (a, b) : (b, a)
    }

    func spoken(_ delivery: Delivery) -> String {
        let sameAs = artifact.deliveries.first {
            $0.number < delivery.number && $0.sha256 != nil && $0.sha256 == delivery.sha256
        }
        return ["Delivery \(delivery.number)", Wording.date(delivery.deliveredAt),
                Wording.provider(delivery.provider),
                Wording.provenanceShort(delivery.capture).1.lowercased(),
                sameAs.map { "same content as delivery \($0.number)" }].compactMap { $0 }.joined(separator: ", ")
    }

    func row(_ delivery: Delivery) -> some View {
        let isSelected = delivery.id == selected.id
        let provenance = Wording.provenanceShort(delivery.capture)
        let sameAs = artifact.deliveries.first {
            $0.number < delivery.number && $0.sha256 != nil && $0.sha256 == delivery.sha256
        }
        return HStack(spacing: 12) {
            Text("Delivery \(delivery.number)").fontWeight(isSelected ? .semibold : .regular)
            Text(Wording.date(delivery.deliveredAt)).foregroundStyle(.secondary)
            Text(Wording.provider(delivery.provider)).foregroundStyle(.secondary)
            Spacer()
            if let sameAs { Text("same as \(sameAs.number)").foregroundStyle(.secondary) }
            StatusLabel(mark: provenance.0, text: provenance.1)
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isSelected ? Palette.selection.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Palette.selection : Color(nsColor: .separatorColor),
                                                              lineWidth: isSelected ? 1.5 : 1))
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
        DisclosureGroup("Details") {
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
