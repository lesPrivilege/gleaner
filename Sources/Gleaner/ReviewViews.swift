import AVFoundation
import AVKit
import GleanerCore
import GleanerUI
import SwiftUI
import UniformTypeIdentifiers

/// How a review page shows a work, as a person opens it; nil for what a program reads (code, data,
/// formats Gleaner can't place), which the page lists under Other Files.
enum ReviewForm: Int, Comparable {
    case video, image, document, audio, file

    init?(_ work: Work) {
        switch work.kind {
        case .media:
            let type = UTType(filenameExtension: (work.latest.path as NSString).pathExtension)
            self = type?.conforms(to: .audio) == true ? .audio : .video
        case .image: self = .image
        case .document, .web: self = .document
        case .model, .build, .folder: self = .file
        case .code, .data, .other: return nil
        }
    }

    static func < (a: ReviewForm, b: ReviewForm) -> Bool { a.rawValue < b.rawValue }
}

/// A collection's works as its review page lays them out: what a person opens, by form, in list
/// order, each with the files that share its stem in its folder beside it; then what a program
/// reads. Files shown together claim nothing about which was made from which (SPEC §5.3).
struct ReviewLayout {
    struct Item: Identifiable {
        /// Drawn in its form: of the files sharing a stem, the first a person sees (a video before
        /// an image, a render before its source of the same kind), else the first in list order.
        var lead: Work
        /// The others, each named beside it.
        var beside: [Work]
        var form: ReviewForm
        var id: Work.ID { lead.id }
    }

    var items: [Item] = []
    var others: [Work] = []

    init(_ works: [Work]) {
        others = works.filter { ReviewForm($0) == nil }
        let opened = works.filter { ReviewForm($0) != nil }
        for row in Listing.rows(opened.map(Listing.Entry.work), crowded: .max) {
            let entries: [Listing.Entry] = switch row {
            case .entry(let entry): [entry]
            case .together(_, let entries), .folded(_, _, let entries): entries
            }
            let group = entries.compactMap { entry -> Work? in if case .work(let work) = entry { work } else { nil } }
            guard let lead = group.enumerated().min(by: { (ReviewForm($0.element)!, $0.offset) < (ReviewForm($1.element)!, $1.offset) })?.element
            else { continue }
            items.append(Item(lead: lead, beside: group.filter { $0.id != lead.id }, form: ReviewForm(lead)!))
        }
        // By form, each in list order: images then stand side by side.
        items = items.enumerated().sorted { ($0.element.form, $0.offset) < ($1.element.form, $1.offset) }.map(\.element)
    }

    /// Every work the page shows, the others last.
    var works: [Work] { items.flatMap { [$0.lead] + $0.beside } + others }
}

/// A verdict or mark the person is about to make, with a note: on one work, or every work a page
/// shows.
struct Asking: Identifiable {
    var works: [Work]
    var kind: Review.Kind
    /// Each file as it was shown, by path.
    var shown: [String: FileStat]
    var id: String { kind.rawValue + "\n" + works.map(\.id).joined(separator: "\n") }
}

/// A collection's review page (docs/design/review.md, A collection's detail): its name, what waits,
/// and Review All; the collections inside it; then each of its works in place, as a person opens
/// it. A video plays where it is, audio in a player row, images stand side by side at their own
/// aspects, a document is rendered as the preview pane renders it, and files a program reads are
/// rows under Other Files, closed. Each work carries its four states and its Review menu. Showing
/// the page plays and renders from disk; nothing is hashed until a verdict or mark is made, and a
/// verdict binds only to a file still as it was shown (A17).
struct ReviewPage: View {
    @Environment(LibraryModel.self) private var model
    var unit: WorkUnit
    /// Each file as it was when its item was drawn, by path.
    @State private var shown: [String: FileStat] = [:]
    /// Bumped by Look Again: each item reads its file again.
    @State private var generation = 0
    @State private var asking: Asking?
    @State private var othersOpen = false
    /// Each image's width over its height, once read, by path: an image's item is as wide as its
    /// picture at the shared height.
    @State private var aspects: [String: CGFloat] = [:]

    var body: some View {
        let organization = model.organization
        let layout = ReviewLayout(organization.works(in: unit.key))
        let inner = organization.units(inside: unit.key)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header(layout)
                if let failure = model.reviewFailure {
                    StatusPanel(statement: Statement(mark: .attention, title: "Nothing recorded", detail: failure)) {
                        Button("Look Again") { generation += 1; model.lookAgain() }
                    }
                }
                if !inner.isEmpty {
                    DetailSection(title: "Collections") {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(inner) { inside in
                                Button { model.outlineSelection = .unit(inside.key) } label: {
                                    UnitRow(unit: inside).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Shows its review page.")
                            }
                        }
                    }
                }
                let images = layout.items.filter { $0.form == .image }
                ForEach(layout.items.filter { $0.form < .image }) { item($0) }
                if !images.isEmpty {
                    FlowLayout(spacing: Space.l) {
                        ForEach(images) { item($0) }
                    }
                }
                ForEach(layout.items.filter { $0.form > .image }) { item($0) }
                if !layout.others.isEmpty {
                    DisclosureGroup(isExpanded: $othersOpen) {
                        VStack(alignment: .leading, spacing: Space.s) {
                            ForEach(layout.others) { work in
                                ReviewBar(work: work, shown: shown[work.latest.path], icon: true, ask: ask)
                                    .task(id: generation) { look(work) }
                            }
                        }
                        .padding(.top, Space.s)
                    } label: {
                        SectionHeader(title: "Other Files", count: layout.others.count, noun: "file")
                            .font(.headline)
                    }
                }
                if layout.items.isEmpty && layout.others.isEmpty && inner.isEmpty {
                    EmptyState(title: "No Works Yet", glyph: .collection)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 880, alignment: .leading)
        }
        .sheet(item: $asking) { NoteSheet(asking: $0) }
    }

    /// The collection's name, what it holds and what waits, and Review All, which makes one verdict
    /// on each work the page shows, on the bytes there now.
    func header(_ layout: ReviewLayout) -> some View {
        let organization = model.organization
        let waiting = model.waiting(in: unit.key)
        return HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    GlyphView(glyph: .collection, size: 22).foregroundStyle(Palette.mark)
                    Text(unit.name).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack(spacing: Space.s) {
                    Text(Wording.unitCounts(works: organization.works(in: unit.key).count, units: organization.units(inside: unit.key).count))
                        .foregroundStyle(.secondary).monospacedDigit()
                    if waiting > 0 { StatusLabel(mark: .awaiting, text: Wording.toReview(waiting), size: 12) }
                }
                .font(.callout)
            }
            Spacer(minLength: Space.s)
            let all = layout.works
            Menu("Review All") {
                Button("Approve All") { make(.approved, all, note: nil) }
                Button("Request Changes to All…") { ask(Asking(works: targets(.changesRequested, all), kind: .changesRequested, shown: shown)) }
                Button("Reject All…") { ask(Asking(works: targets(.rejected, all), kind: .rejected, shown: shown)) }
            }
            .fixedSize()
            .disabled(targets(.approved, all).isEmpty && targets(.rejected, all).isEmpty)
            .help("A verdict on each work shown here, on the bytes there now")
        }
    }

    /// The works shown that a verdict of `kind` would add to: those drawn, with a file there, not
    /// already given that verdict on these bytes. A folder has no bytes to judge.
    func targets(_ kind: Review.Kind, _ works: [Work]) -> [Work] {
        works.filter { work in
            guard work.kind != .folder, shown[work.latest.path] != nil else { return false }
            if case .current(let review) = model.verdict(of: work), review.kind == kind { return false }
            return true
        }
    }

    func make(_ kind: Review.Kind, _ works: [Work], note: String?) {
        let works = targets(kind, works), shown = shown
        guard !works.isEmpty else { return }
        Task { await model.review(works, as: kind, note: note, shown: shown) }
    }

    func ask(_ asking: Asking) {
        if asking.kind == .approved {
            Task { await model.review(asking.works, as: .approved, shown: asking.shown) }
        } else if !asking.works.isEmpty {
            self.asking = asking
        }
    }

    /// Takes the file as it is now, as its item is drawn: what a verdict made on it binds to.
    func look(_ work: Work) {
        let path = work.latest.path
        shown[path] = FileStat(path)
    }

    /// A work in place, its states and actions under it, and the files sharing its stem beside it.
    @ViewBuilder func item(_ item: ReviewLayout.Item) -> some View {
        let lead = item.lead
        VStack(alignment: .leading, spacing: Space.s) {
            Group {
                if item.form == .image {
                    ImageTile(path: lead.latest.path, generation: generation, aspect: $aspects[lead.latest.path])
                } else {
                    ReviewMedia(work: lead, form: item.form, generation: generation)
                }
            }
            .task(id: generation) { look(lead) }
            ReviewBar(work: lead, shown: shown[lead.latest.path], ask: ask)
            ForEach(item.beside) { other in
                VStack(alignment: .leading, spacing: Space.xs) {
                    // Audio beside plays in its own row; anything else is named beside it.
                    if ReviewForm(other) == .audio {
                        ReviewMedia(work: other, form: .audio, generation: generation)
                    }
                    ReviewBar(work: other, shown: shown[other.latest.path], beside: true, ask: ask)
                }
                .padding(.leading, Space.m)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 2) }
                .task(id: generation) { look(other) }
            }
        }
        .frame(width: item.form == .image ? ImageTile.itemWidth(aspects[lead.latest.path]) : nil, alignment: .leading)
        .frame(maxWidth: item.form == .image ? nil : .infinity, alignment: .leading)
    }
}

/// A work drawn as a person opens it, from the file on disk: a video at its own aspect, audio in a
/// player row, an image at its own aspect, a document as the preview pane renders it, or the
/// file's own icon.
struct ReviewMedia: View {
    var work: Work
    var form: ReviewForm
    /// Read again whenever it changes.
    var generation: Int

    var body: some View {
        let url = URL(fileURLWithPath: work.latest.path)
        switch form {
        case .video: VideoItem(url: url).id(generation)
        case .audio:
            // Audio has no picture: its row is AVKit's controls alone.
            PlayerView(url: url, audio: true).frame(height: 36)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .id(generation)
        case .image: ImageTile(path: work.latest.path, generation: generation, aspect: .constant(nil))
        case .document: DocumentItem(url: url, generation: generation)
        case .file:
            FileIcon(path: work.latest.path, folder: work.kind == .folder, size: 64)
                .frame(maxWidth: .infinity, minHeight: 96)
                .surface(.page)
        }
    }
}

/// A video, played where it is and never copied, at its own aspect, up to a height.
struct VideoItem: View {
    var url: URL
    @State private var aspect: CGFloat?

    static let tallest: CGFloat = 420

    var body: some View {
        PlayerView(url: url, audio: false)
            .aspectRatio(aspect ?? 16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: Self.tallest, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .task(id: url) { aspect = await Self.aspect(url) }
    }

    /// The width over the height of its picture as shown, turned as it is meant to be.
    static func aspect(_ url: URL) async -> CGFloat? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let shown = size.applying(transform)
        return shown.height == 0 ? nil : abs(shown.width / shown.height)
    }
}

/// AVKit's player, for a video or as a row for audio. It starts paused, and stops when it goes.
struct PlayerView: NSViewRepresentable {
    var url: URL
    var audio: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = audio ? .inline : .floating
        view.showsFullScreenToggleButton = !audio
        view.player = AVPlayer(url: url)
        view.setAccessibilityLabel(url.lastPathComponent)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url { view.player = AVPlayer(url: url) }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

/// An image at its own aspect, at the height every image on the page shares, so several stand side
/// by side.
struct ImageTile: View {
    var path: String
    var generation: Int
    /// Its width over its height, once read.
    @Binding var aspect: CGFloat?
    @State private var image: NSImage?

    static let height: CGFloat = 220
    static let widest: CGFloat = 560

    /// The width of an image's item on a page: its picture's at the shared height, and at least
    /// room for its name and actions under it.
    static func itemWidth(_ aspect: CGFloat?) -> CGFloat {
        max(min(height * (aspect ?? 4 / 3), widest), 260)
    }

    var body: some View {
        let aspect = image.map { $0.size.height > 0 ? $0.size.width / $0.size.height : 1 } ?? 4 / 3
        ZStack {
            RoundedRectangle(cornerRadius: Radius.tag).fill(.quaternary.opacity(0.5))
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                FileIcon(path: path, folder: false, size: 48).opacity(0.5)
            }
        }
        .frame(width: min(Self.height * aspect, Self.widest), height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tag))
        .overlay(RoundedRectangle(cornerRadius: Radius.tag).strokeBorder(Color(nsColor: .separatorColor)))
        .task(id: "\(path)|\(generation)") {
            image = await ImageFile.load(path, pixels: 1600)
            self.aspect = image.map { $0.size.height > 0 ? $0.size.width / $0.size.height : 1 }
        }
        .accessibilityElement()
        .accessibilityLabel((path as NSString).lastPathComponent)
        .accessibilityAddTraits(.isImage)
    }
}

/// A document as the preview pane renders it: Markdown and text from their words, as tall as they
/// are up to a height, anything else (a PDF, a page) by Quick Look.
struct DocumentItem: View {
    var url: URL
    var generation: Int
    @State private var text: (text: String, truncated: Bool)?
    @State private var loaded = false
    @State private var height: CGFloat = 0

    var body: some View {
        Group {
            if let text {
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
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                }
                .scrollDisabled(height <= PreviewPane.tallest)
                .frame(height: min(max(height, 64), PreviewPane.tallest))
            } else if loaded {
                QuickLookPreview(url: url).frame(height: 360)
            } else {
                Color.clear.frame(height: 96)
            }
        }
        .frame(maxWidth: .infinity)
        .surface(.page)
        .task(id: generation) {
            let url = url
            text = await Task.detached(priority: .userInitiated) { TextPreview.load(url) }.value
            loaded = true
        }
    }
}

/// A work's name, its four states, and what the person can do: Review ▸ (Approve; Request
/// Changes…; Reject…), Mark Published…, and More, which opens the work's own detail. The states
/// are marks, with words only where something needs a look; every word is in the help tags and
/// for VoiceOver.
struct ReviewBar: View {
    @Environment(LibraryModel.self) private var model
    var work: Work
    /// The file as it was shown; nil when no regular file was there to show.
    var shown: FileStat?
    /// Named beside the work sharing its stem.
    var beside = false
    /// The file's icon before its name, where nothing above shows the file.
    var icon = false
    var ask: (Asking) -> Void

    var body: some View {
        let states = ReviewStates(work: work, model: model)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s) {
                name
                ReviewMarks(states: states)
                Spacer(minLength: Space.s)
                actions
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    name
                    ReviewMarks(states: states)
                }
                HStack(spacing: Space.s) { actions }
            }
        }
        .controlRole(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(work.name)
        .accessibilityValue(states.spoken)
    }

    var name: some View {
        HStack(spacing: Space.xs + 2) {
            if icon { FileIcon(path: work.latest.path, folder: work.kind == .folder, size: 16) }
            if beside { Text("Beside it:").foregroundStyle(.secondary).fixedSize() }
            Text(work.name).fontWeight(beside ? .regular : .semibold).lineLimit(1).truncationMode(.middle)
                .help(Wording.tilde(work.latest.path))
        }
        .font(.callout)
    }

    @ViewBuilder var actions: some View {
        let path = work.latest.path
        let judged = shown.map { [path: $0] } ?? [:]
        Menu("Review") {
            Button("Approve") { ask(Asking(works: [work], kind: .approved, shown: judged)) }
            Button("Request Changes…") { ask(Asking(works: [work], kind: .changesRequested, shown: judged)) }
            Button("Reject…") { ask(Asking(works: [work], kind: .rejected, shown: judged)) }
        }
        .fixedSize()
        .disabled(shown == nil || work.kind == .folder)
        .help(shown == nil || work.kind == .folder ? "No bytes here to judge" : "A verdict on the bytes shown")
        Button("Mark Published…") { ask(Asking(works: [work], kind: .published, shown: judged)) }
            .disabled(shown == nil || work.kind == .folder)
        Button("More") { model.selection = work.id }
            .help("Show its own detail: its versions, its history and where it came from")
    }
}

/// A work's four states for its current file, each from its own source and said on its own:
/// Generated, On this Mac, Reviewed and Published (docs/design/review.md, The four states).
struct ReviewStates {
    var generated: (title: String, detail: String)
    var kept: Bool
    var provider: Provider
    var onThisMac: Statement
    var reviewed: Statement
    var published: Statement

    @MainActor init(work: Work, model: LibraryModel) {
        let current = work.latest.latest
        generated = Wording.generated(current)
        kept = current.kept != nil
        provider = current.provider
        onThisMac = model.onThisMac(work)
        reviewed = work.kind == .folder ? Statement(mark: .na, title: "Not reviewed", detail: "A folder has no bytes of its own to judge.")
            : Wording.verdict(model.verdict(of: work), inUnit: work.unit != nil)
        published = Wording.publishedState(model.published(of: work))
    }

    /// The four, in one sentence for VoiceOver.
    var spoken: String {
        [generated.title, onThisMac.title, reviewed.title, published.title].joined(separator: ", ")
    }
}

/// The four states as marks, in their order. A state as it should be is its mark alone, or
/// nothing; one that needs a look says so in a word or two.
struct ReviewMarks: View {
    var states: ReviewStates

    var body: some View {
        HStack(spacing: Space.s) {
            // Generated: which agent's reply, or the observed mark for a file the person kept.
            Group {
                if states.kept {
                    GlyphView(glyph: Mark.observed.glyph, size: 12).foregroundStyle(.secondary)
                } else {
                    AgentMark(provider: states.provider, size: 12).foregroundStyle(.secondary)
                }
            }
            .help(states.generated.title + ". " + states.generated.detail)
            if states.onThisMac.mark != .done { label(states.onThisMac) }
            if [.awaiting, .attention].contains(states.reviewed.mark) {
                label(states.reviewed)
            } else if states.reviewed.mark != .dashed && states.reviewed.mark != .na {
                StatusMark(mark: states.reviewed.mark, word: states.reviewed.title + ". " + states.reviewed.detail)
            }
            if states.published.mark == .attention {
                label(states.published)
            } else if states.published.mark == .published {
                StatusMark(mark: .published, word: states.published.title + ". " + states.published.detail)
            }
        }
        .font(.caption)
        .accessibilityHidden(true)
    }

    func label(_ statement: Statement) -> some View {
        StatusLabel(mark: statement.mark, text: statement.title, size: 11)
            .lineLimit(1)
            .fixedSize()
            .help(statement.detail)
    }
}

/// A verdict's note, or where a file was published, before it is made. One line of explanation, the
/// field, and Cancel and the default button.
struct NoteSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var asking: Asking
    @State private var note = ""

    var body: some View {
        let what = asking.works.count == 1 ? "“\(asking.works[0].name)”" : Wording.count(asking.works.count, "work")
        VStack(alignment: .leading, spacing: Space.m) {
            Text(asking.kind == .published ? "Mark \(what) Published" : "\(Wording.reviewAction(asking.kind)) \(what)")
                .font(.headline)
            Text(asking.kind == .published ? "Where it was published, in words or a link. Optional."
                 : "A note goes with the verdict, on the bytes shown. Optional.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField(asking.kind == .published ? "Where" : "Note", text: $note,
                      prompt: Text(asking.kind == .published ? "Where it was published" : "What to change"), axis: .vertical)
                .lineLimit(3...6)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Wording.reviewAction(asking.kind)) {
                    let asking = asking, note = note
                    Task { await model.review(asking.works, as: asking.kind, note: note, shown: asking.shown) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 420)
    }
}

/// A work's Review section in its detail: where it is reviewed, its verdict and published mark on
/// the current file, and every verdict and mark made on any of its files, newest first, each with
/// the bytes it binds to and its Undo. Verdicts here are made on the bytes the detail shows, once
/// they are the file's current bytes.
struct ReviewSection: View {
    @Environment(LibraryModel.self) private var model
    var work: Work
    /// The file as the detail shows it, when the detail shows the current file's bytes.
    var shown: FileStat?
    @State private var asking: Asking?

    var body: some View {
        let organization = model.organization
        let states = ReviewStates(work: work, model: model)
        let history = model.reviews.history(of: work)
        let judged = shown.map { [work.latest.path: $0] } ?? [:]
        DetailSection(title: "Review") {
            HStack(spacing: Space.s) {
                Menu("Review") {
                    Button("Approve") { Task { await model.review([work], as: .approved, shown: judged) } }
                    Button("Request Changes…") { asking = Asking(works: [work], kind: .changesRequested, shown: judged) }
                    Button("Reject…") { asking = Asking(works: [work], kind: .rejected, shown: judged) }
                }
                .fixedSize()
                Button("Mark Published…") { asking = Asking(works: [work], kind: .published, shown: judged) }
            }
            .controlRole(.inline)
            .disabled(shown == nil || work.kind == .folder)
            .help(work.kind == .folder ? "A folder has no bytes of its own to judge"
                  : shown == nil ? "Verdicts are made on the bytes shown, once they are the file’s current bytes" : "")
        } content: {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.s + 2) {
                InfoRow(label: "Collection") {
                    HStack(spacing: Space.s) {
                        if let unit = organization.unit(of: work)?.unit {
                            Label { LinkButton(title: Wording.unitPath(unit, in: organization)) { model.place = .unit(unit.key); model.selection = work.id } } icon: {
                                GlyphView(glyph: .collection, size: 14).foregroundStyle(Palette.mark)
                            }
                            Button("Remove") { Task { await model.remove([work], from: unit) } }
                                .controlRole(.inline)
                                .help("Take it out of \(unit.name). No file changes.")
                        } else {
                            Text("None").foregroundStyle(.secondary)
                            Menu("Add to Collection") {
                                CollectionChoices(project: work.project) { unit in
                                    Task { await model.add([work], to: unit) }
                                } new: {
                                    model.startNewUnit(in: work.project, adding: [work.id])
                                }
                            }
                            .controlRole(.inline)
                            .fixedSize()
                        }
                    }
                }
                InfoRow(label: "Reviewed") { state(states.reviewed) }
                InfoRow(label: "Published") { state(states.published) }
            }
            .font(.callout)
            if !history.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(history) { review in
                        HistoryLine(review: review, file: work.files.count > 1 ? (review.path as NSString).lastPathComponent : nil)
                    }
                }
                .padding(.top, Space.xs)
            }
            if let failure = model.reviewFailure {
                StatusLabel(mark: .attention, text: failure).font(.callout)
            }
        }
        .sheet(item: $asking) { NoteSheet(asking: $0) }
    }

    func state(_ statement: Statement) -> some View {
        HStack(spacing: Space.s) {
            StatusLabel(mark: statement.mark, text: statement.title).id(statement.title)
            InfoButton(text: statement.detail)
        }
    }
}

/// One verdict or mark in a work's history: what, when, the bytes it binds to, its note, and its
/// Undo. None is removed by a later one.
struct HistoryLine: View {
    @Environment(LibraryModel.self) private var model
    var review: Review
    /// The file it was made on, when the work has several.
    var file: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            GlyphView(glyph: Wording.reviewMark(review.kind).glyph, size: 12).foregroundStyle(.secondary).frame(width: 14)
            Text(Wording.reviewName(review.kind))
            if let file { Text(file).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            Text(Wording.shortDate(review.madeAt)).foregroundStyle(.secondary).monospacedDigit()
                .help(Wording.date(review.madeAt))
            Text(review.sha256.prefix(8)).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                .help("SHA-256 \(review.sha256)")
            if let note = review.note {
                Text(review.kind == .published ? note : "“\(note)”").foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: Space.s)
            Button("Undo") { Task { await model.undo([review]) } }
                .controlRole(.inline)
                .accessibilityLabel("Undo: \(Wording.historyLine(review, file: file))")
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}
