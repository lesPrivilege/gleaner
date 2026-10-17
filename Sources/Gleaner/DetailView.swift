import AppKit
import GleanerCore
import Quartz
import SwiftUI

struct DetailView: View {
    @Environment(LibraryModel.self) private var model
    var result: SearchResult

    var body: some View {
        let artifact = result.artifact
        let delivery = model.delivery(in: result)
        let observation = model.observations[artifact.path]
        let onDisk = observation.map { artifact.onDisk($0, hasSaved: model.hasSaved) }
        let plan = observation.map { artifact.handoff(delivery, now: $0, hasSaved: model.hasSaved) }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PreviewPane(artifact: artifact, plan: plan, staging: model.staging)
                header(artifact, observation: observation)
                if let observation, let onDisk {
                    Panel(statement: Wording.onDisk(onDisk, checked: observation.checkedAt), eyebrow: "On disk now")
                } else {
                    ProgressView("Checking the file…").controlSize(.small)
                }
                if let plan, let onDisk, let observation {
                    HandoffPanel(artifact: artifact, delivery: delivery, plan: plan, onDisk: onDisk, observation: observation)
                }
                DeliveriesSection(artifact: artifact, selected: delivery, checked: observation != nil,
                                  current: observation?.state.sha256)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .task(id: artifact.id) {
            model.staging = .idle
            await model.observe(artifact)
        }
        .task(id: "\(artifact.id)|\(delivery.id)|\(observation?.checkedAt.timeIntervalSince1970 ?? 0)") {
            if case .ready(let sha, _, _) = plan {
                await model.stage(sha: sha, artifact: artifact)
            } else {
                model.staging = .idle
            }
        }
    }

    @ViewBuilder
    func header(_ artifact: Artifact, observation: FileObservation?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(artifact.name).font(.title2.weight(.semibold)).textSelection(.enabled)
            Text(artifact.path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled)
            let size = observation?.state.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            let git = observation.map { "Git: " + $0.state.git.rawValue.replacingOccurrences(of: "_", with: " ") }
            Text(([artifact.project, artifact.place, size, git] as [String?]).compactMap { $0 }.joined(separator: " · "))
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

struct PreviewPane: View {
    var artifact: Artifact
    var plan: Handoff?
    var staging: Staging

    var body: some View {
        let url: URL? = switch (plan, staging) {
        case (.folder?, _): URL(fileURLWithPath: artifact.path)
        case (_, .ready(let url, _)): url
        default: nil
        }
        ZStack {
            if let url, let text = TextPreview.load(url) {
                TextPreview(text: text, markdown: ["md", "markdown"].contains(url.pathExtension.lowercased()))
            } else if let url {
                QuickLookPreview(url: url)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash").font(.title2)
                    Text(staging == .preparing ? "Preparing a verified copy…" : "No preview: these bytes aren’t available")
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Quick Look's compact view leaves plain text and Markdown blank, so those are shown directly.
struct TextPreview: View {
    var text: String
    var markdown: Bool

    static let textTypes: Set<String> = ["md", "markdown", "txt", "json", "tsv", "csv", "log", "yaml", "yml", "toml", "swift", "py", "js", "ts"]

    static func load(_ url: URL) -> String? {
        guard textTypes.contains(url.pathExtension.lowercased()),
              let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 64 << 10) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    var body: some View {
        ScrollView {
            Group {
                if markdown, let rich = try? AttributedString(
                    markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(rich)
                } else {
                    Text(text).font(.system(.callout, design: .monospaced))
                }
            }
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

struct HandoffPanel: View {
    @Environment(LibraryModel.self) private var model
    var artifact: Artifact
    var delivery: Delivery
    var plan: Handoff
    var onDisk: OnDisk
    var observation: FileObservation

    var body: some View {
        let statement = Wording.handoff(plan, delivery: delivery.number, onDisk: onDisk)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hand off delivery \(delivery.number)").font(.headline)
                Spacer()
                Text("To hand off another version, pick it under Deliveries.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                tile
                Button("Open") { open() }.disabled(openURL == nil)
                Button("Show in Finder") { reveal() }
                Button("Copy Path") { copy(artifact.path) }
                if canSave {
                    Button("Save a Copy (\(sizeText))") { Task { await model.saveCopy(of: delivery, artifact: artifact) } }
                }
            }
            .controlSize(.large)
            Panel(statement: statement) {
                actions
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
    }

    /// The thing you drag: the file itself, labeled with the exact version it carries.
    @ViewBuilder var tile: some View {
        let ready: URL? = switch (plan, model.staging) {
        case (.folder, _): URL(fileURLWithPath: artifact.path)
        case (_, .ready(let url, _)): url
        default: nil
        }
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityHidden(true)
            TypeBadge(artifact: artifact)
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                Text(tileCaption).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            if model.staging == .preparing { ProgressView().controlSize(.small) }
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
        .accessibilityLabel("Drag \(artifact.name), delivery \(delivery.number)")
    }

    var tileCaption: String {
        switch model.staging {
        case .ready(_, let sha):
            let label = artifact.deliveries.first { $0.sha256 == sha && $0.isTrusted }.map { "delivery \($0.number)" }
                ?? (sha == delivery.sha256 ? "delivery \(delivery.number)" : "current file · never delivered")
            return "\(label) · \(sha.prefix(12))…"
        case .preparing: return "verifying…"
        case .failed(let why): return why
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
            if let command = restoreCommand {
                HStack {
                    Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                    Button("Copy Command") { copy(command) }
                }
            }
        default:
            EmptyView()
        }
        if case .failed(let why) = model.staging {
            StatusLabel(mark: .attention, text: why).font(.callout)
        }
    }

    var canSave: Bool {
        guard let sha = delivery.sha256, !model.hasSaved(sha) else { return false }
        return observation.state.sha256 == sha
    }

    var sizeText: String {
        observation.state.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
    }

    var openURL: URL? {
        if case .ready(let url, _) = model.staging { return url }
        if plan == .folder { return URL(fileURLWithPath: artifact.path) }
        return nil
    }

    var restoreCommand: String? {
        guard let root = observation.state.repositoryRoot else { return nil }
        let rel = artifact.path.hasPrefix(root + "/") ? String(artifact.path.dropFirst(root.count + 1)) : artifact.path
        if observation.state.git == .recoverableFromHead {
            return "git -C '\(root)' restore --source=HEAD -- '\(rel)'"
        }
        return "git -C '\(root)' checkout \"$(git -C '\(root)' rev-list -n 1 --all -- '\(rel)')^\" -- '\(rel)'"
    }

    func open() { if let openURL { NSWorkspace.shared.open(openURL) } }

    func reveal() {
        let source = URL(fileURLWithPath: artifact.path)
        if FileManager.default.fileExists(atPath: source.path) {
            NSWorkspace.shared.activateFileViewerSelecting([source])
        } else if let openURL {
            NSWorkspace.shared.activateFileViewerSelecting([openURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([source.deletingLastPathComponent()])
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct DeliveriesSection: View {
    @Environment(LibraryModel.self) private var model
    var artifact: Artifact
    var selected: Delivery
    var checked: Bool
    var current: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Deliveries").font(.headline)
                Spacer()
                Text("Newest first, one entry per reply that handed you this file. Spacing doesn’t show time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(artifact.deliveries) { delivery in
                Button { model.chosenDelivery = delivery.id } label: { card(delivery) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(delivery.id == selected.id ? .isSelected : [])
            }
        }
    }

    func card(_ delivery: Delivery) -> some View {
        let isSelected = delivery.id == selected.id
        let provenance = Wording.provenance(delivery.capture)
        let storage = Wording.storage(delivery, hasSaved: delivery.sha256.map(model.hasSaved) ?? false,
                                      current: current, checked: checked)
        let sameAs = artifact.deliveries.first {
            $0.number < delivery.number && $0.sha256 != nil && $0.sha256 == delivery.sha256
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Delivery \(delivery.number) · \(Wording.date(delivery.deliveredAt))").fontWeight(.semibold)
                Spacer()
                Text("\(delivery.provider == .codex ? "Codex" : "Claude Code") · “\(delivery.sessionTitle ?? "Untitled session")”")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let request = delivery.request {
                (Text("You asked: ").foregroundStyle(.secondary) + Text("“\(request)”"))
                    .font(.callout).lineLimit(3)
            }
            ForEach(Array(delivery.evidence.enumerated()), id: \.offset) { _, item in
                Text(item.excerpt)
                    .font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack(spacing: 16) {
                StatusLabel(mark: provenance.0, text: provenance.1)
                StatusLabel(mark: storage.0, text: storage.1)
                if let sameAs { Text("Same content as delivery \(sameAs.number)").foregroundStyle(.secondary) }
            }
            .font(.caption)
            Text("sha256 \(delivery.sha256 ?? "not recorded")")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Palette.selection : Color(nsColor: .separatorColor),
                                                               lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
    }
}
