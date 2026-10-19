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
/// order, each with the files beside it whose names in its folder differ from its own only by their
/// extension (`chart-4x3.png`, `chart-4x3.svg`); then what a program reads. Files that share no more
/// than a stem (`intro.mp4`, `intro.poster-4x3.png`, `intro.notes.md`) are each drawn in their own
/// form. Files shown together claim nothing about which was made from which (SPEC §5.3).
struct ReviewLayout {
    struct Item: Identifiable {
        /// Drawn in its form: of the files that differ only by extension, the first a person sees
        /// (a video before an image, an image before a document, a document before audio), else
        /// the first in list order.
        var lead: Work
        /// The others, each named beside it.
        var beside: [Work]
        var form: ReviewForm
        var id: Work.ID { lead.id }
    }

    var items: [Item] = []
    var others: [Work] = []

    /// `works` in list order, as a unit holds them.
    init(_ works: [Work]) {
        others = works.filter { ReviewForm($0) == nil }
        var groups: [String: [Work]] = [:], order: [String] = []
        for work in works where ReviewForm(work) != nil {
            // Compared without case, as the disk compares names.
            let key = (work.latest.path as NSString).deletingPathExtension.lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(work)
        }
        for key in order {
            let group = groups[key]!
            let lead = group.enumerated().min { (ReviewForm($0.element)!, $0.offset) < (ReviewForm($1.element)!, $1.offset) }!.element
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
    /// Where it was asked for, where a refusal is said: a collection's key, or a work's id.
    var place: String? = nil
    var id: String { kind.rawValue + "\n" + works.map(\.id).joined(separator: "\n") }
}

/// What Review All acts on (docs/design/review.md, The review page): each image and document the
/// page drew whole, with a file there, that hasn't that verdict on these bytes already. Videos and
/// audio each need a verdict of their own, since a file played isn't a file watched or heard (A07):
/// they never pass with others, and the menu says how many wait one by one: all of the page's,
/// drawn yet or not, as To Review counts them.
struct ReviewAll {
    var approve: [Work] = [], changes: [Work] = [], reject: [Work] = []
    /// The videos and the audio files on the page with a file there and no verdict on its bytes.
    var videos = 0, audio = 0

    /// `works` as the page lists them; `drawn` the files drawn whole, `shown` each file as drawn;
    /// `hasFile` whether a regular file is at a work's file, as the library last found it.
    init(_ works: [Work], drawn: Set<String>, shown: [String: FileStat], hasFile: (Work) -> Bool, verdict: (Work) -> Standing) {
        for work in works where work.kind != .folder {
            switch ReviewForm(work) {
            case let form? where form == .video || form == .audio:
                // Counted from what the library knows, not from the page: one not scrolled to yet waits too.
                guard hasFile(work) else { continue }
                if case .current = verdict(work) { continue }
                if form == .video { videos += 1 } else { audio += 1 }
            case .image?, .document?:
                guard shown[work.latest.path] != nil, drawn.contains(work.latest.path) else { continue }
                let standing = verdict(work)
                func has(_ kind: Review.Kind) -> Bool { if case .current(let review) = standing { review.kind == kind } else { false } }
                if !has(.approved) { approve.append(work) }
                if !has(.changesRequested) { changes.append(work) }
                if !has(.rejected) { reject.append(work) }
            default:
                // A model, a build, or what a program reads: drawn as its icon, judged on its own.
                continue
            }
        }
    }

    /// Nothing for any of its verdicts to act on.
    var isEmpty: Bool { approve.isEmpty && changes.isEmpty && reject.isEmpty }
    /// What it leaves to each one's own verdict, in a line of its menu.
    var oneByOne: String? { Wording.oneByOne(videos: videos, audio: audio) }
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
    /// The files drawn whole in their form: played, shown large enough to see, or rendered, as
    /// each form says once it did. What Review All acts on. A file named beside another, under
    /// Other Files, drawn as its icon, cut off, by Quick Look, or that couldn't be drawn is judged
    /// on its own (A10).
    @State private var drawn: Set<String> = []
    /// Bumped by Look Again: each item reads its file again.
    @State private var generation = 0
    @State private var asking: Asking?
    @State private var othersOpen = false

    var body: some View {
        let organization = model.organization
        let layout = ReviewLayout(organization.works(in: unit.key))
        let inner = organization.units(inside: unit.key)
        let refusal = model.reviewRefusal.flatMap { $0.place == unit.key ? $0 : nil }
        ScrollView {
            // Drawn as it scrolls into view, row by row: a long collection plays and reads only
            // what is shown, and Review All acts on that.
            LazyVStack(alignment: .leading, spacing: Space.xl) {
                header(layout)
                // Several asked for at once: what was recorded and what wasn't, by Review All.
                if let refusal, refusal.made + refusal.refused.count > 1 {
                    StatusPanel(statement: Wording.refusal(refusal)) {
                        Button("Look Again", action: lookAgain)
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
                ForEach(layout.items.filter { $0.form < .image }) { item($0, refusal) }
                if !images.isEmpty {
                    // Each row of images is made as it scrolls into view.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: ImageTile.width), spacing: Space.l, alignment: .topLeading)],
                              alignment: .leading, spacing: Space.l) {
                        ForEach(images) { item($0, refusal) }
                    }
                }
                ForEach(layout.items.filter { $0.form > .image }) { item($0, refusal) }
                if !layout.others.isEmpty {
                    DisclosureGroup(isExpanded: $othersOpen) {
                        VStack(alignment: .leading, spacing: Space.s) {
                            ForEach(layout.others) { work in
                                ReviewBar(work: work, shown: shown[work.latest.path], icon: true,
                                          refused: refusal?.reason(work.latest.path), ask: ask, lookAgain: lookAgain)
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
    /// on each work the page drew, on the bytes there now.
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
            let all = ReviewAll(layout.works, drawn: drawn, shown: shown, hasFile: { !model.hasNoFile($0) }, verdict: model.verdict)
            // Each verdict only while some image or document drawn hasn't been given it on these bytes.
            Menu("Review All") {
                Button("Approve All") { make(.approved, all.approve, note: nil) }
                    .disabled(all.approve.isEmpty)
                Button("Request Changes to All…") { ask(Asking(works: all.changes, kind: .changesRequested, shown: shown, place: unit.key)) }
                    .disabled(all.changes.isEmpty)
                Button("Reject All…") { ask(Asking(works: all.reject, kind: .rejected, shown: shown, place: unit.key)) }
                    .disabled(all.reject.isEmpty)
                if let oneByOne = all.oneByOne {
                    Divider()
                    Text(oneByOne)
                }
            }
            .fixedSize()
            .disabled(all.isEmpty && all.oneByOne == nil)
            .help("A verdict on each image and document shown whole here, bound to the bytes hashed as it is made. Videos and audio each need their own; files only named, or that couldn’t be drawn whole, are judged on their own.")
        }
    }

    func make(_ kind: Review.Kind, _ works: [Work], note: String?) {
        let shown = shown, place = unit.key
        guard !works.isEmpty else { return }
        Task { await model.review(works, as: kind, note: note, shown: shown, from: place) }
    }

    func ask(_ asking: Asking) {
        if asking.kind == .approved {
            Task { await model.review(asking.works, as: .approved, shown: asking.shown, from: asking.place) }
        } else if !asking.works.isEmpty {
            self.asking = asking
        }
    }

    /// Draws every item again from disk, and clears what was refused.
    func lookAgain() {
        drawn = []
        generation += 1
        model.lookAgain()
    }

    /// Takes the file as it is now, as its item is drawn: a verdict made on it is made only while
    /// the file is still so, and the marks and To Review say what the page drew.
    func look(_ work: Work) {
        let path = work.latest.path, file = FileStat(path)
        shown[path] = file
        model.noteShown(path, file)
    }

    /// A work in place, its states and actions under it, and the files beside it.
    @ViewBuilder func item(_ item: ReviewLayout.Item, _ refusal: ReviewRefusal?) -> some View {
        let lead = item.lead
        VStack(alignment: .leading, spacing: Space.s) {
            ReviewMedia(work: lead, form: item.form, generation: generation) { drawn.insert(lead.latest.path) }
                .task(id: generation) { look(lead) }
            ReviewBar(work: lead, shown: shown[lead.latest.path], refused: refusal?.reason(lead.latest.path), ask: ask, lookAgain: lookAgain)
            ForEach(item.beside) { other in
                VStack(alignment: .leading, spacing: Space.xs) {
                    // Audio beside plays in its own row; anything else is named beside it.
                    if ReviewForm(other) == .audio {
                        ReviewMedia(work: other, form: .audio, generation: generation) { drawn.insert(other.latest.path) }
                    }
                    ReviewBar(work: other, shown: shown[other.latest.path], beside: true, refused: refusal?.reason(other.latest.path),
                              ask: ask, lookAgain: lookAgain)
                }
                .padding(.leading, Space.m)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 2) }
                .task(id: generation) { look(other) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            // Files shown together, as the person chooses: a collection of exactly them, inside this
            // one, or beside it when it is itself inside another.
            if !item.beside.isEmpty {
                NewCollectionFromThese(works: [lead] + item.beside, inside: unit.parent ?? unit.key)
            }
        }
    }
}

/// A work drawn as a person opens it, from the file on disk: a video at its own aspect, audio in a
/// player row, an image at its own aspect, a document as the preview pane renders it, or the
/// file's own icon. With no file Gleaner can read there, or one it can't play, it is the file's
/// icon and why, compact. `rendered` is called once the file is drawn whole in its form.
struct ReviewMedia: View {
    @Environment(LibraryModel.self) private var model
    var work: Work
    var form: ReviewForm
    /// Read again whenever it changes.
    var generation: Int
    var rendered: () -> Void

    var body: some View {
        let url = URL(fileURLWithPath: work.latest.path)
        if model.hasNoFile(work) && work.kind != .folder {
            Undrawn(path: work.latest.path, reason: model.onThisMac(work).detail)
        } else {
            switch form {
            case .video, .audio: PlayedItem(url: url, audio: form == .audio, rendered: rendered).id(generation)
            case .image: ImageTile(path: work.latest.path, generation: generation, rendered: rendered)
            case .document: DocumentItem(url: url, generation: generation, rendered: rendered)
            case .file:
                FileIcon(path: work.latest.path, folder: work.kind == .folder, size: 64)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .surface(.page)
            }
        }
    }
}

/// In place of a file that can't be drawn: its icon and why, compact, so it never stands as large
/// as one that can.
struct Undrawn: View {
    var path: String
    var reason: String

    var body: some View {
        HStack(spacing: Space.m) {
            FileIcon(path: path, folder: false, size: 32).opacity(0.6)
            Text(reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(.page)
    }
}

/// A video, played where it is and never copied, at its own aspect, up to a height; or audio, as a
/// row of AVKit's controls alone. Played only once AVFoundation finds a track it can play;
/// otherwise the file's icon says it can't be played here.
struct PlayedItem: View {
    var url: URL
    var audio: Bool
    var rendered: () -> Void
    /// Nil until the file is looked at; then its picture's width over its height (1 for audio), or
    /// nothing it can play.
    @State private var playable: CGFloat??

    static let tallest: CGFloat = 420

    var body: some View {
        Group {
            switch playable {
            case .some(.none): Undrawn(path: url.path, reason: Wording.unplayable)
            case .some(.some(let aspect)) where !audio:
                PlayerView(url: url, audio: false)
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.tallest, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            case .some(.some):
                PlayerView(url: url, audio: true).frame(height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            case .none:
                Color.clear.frame(height: audio ? 36 : 96)
            }
        }
        .task(id: url) {
            playable = .some(await Self.aspect(url, audio: audio))
            if playable != .some(.none) { rendered() }
        }
    }

    /// The width over the height of a video's picture as shown, turned as it is meant to be; 1 for
    /// audio with a sound track. Nil when there is no track AVFoundation can play.
    static func aspect(_ url: URL, audio: Bool) async -> CGFloat? {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true,
              let track = try? await asset.loadTracks(withMediaType: audio ? .audio : .video).first else { return nil }
        if audio { return 1 }
        guard let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
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

/// An image at its own aspect, fitted to its tile: a page's images stand side by side in tiles of
/// one height, as wide as the page gives each.
struct ImageTile: View {
    var path: String
    var generation: Int
    /// Called once the image is drawn large enough to see.
    var rendered: () -> Void = {}
    /// Nil until the file is read; then the image, or nil when neither ImageIO nor AppKit can draw it.
    @State private var image: NSImage??
    @Environment(\.displayScale) private var scale

    static let height: CGFloat = 220
    /// The least width of a tile, which leaves room for its name and actions under it.
    static let width: CGFloat = 360
    /// The widest a tile is drawn, alone in a row of a narrow page.
    static let widest: CGFloat = 720

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.tag).fill(.quaternary.opacity(0.5))
            switch image {
            case .some(.some(let image)):
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            case .some(.none):
                // Said as itself, never left looking like one still being read (A20); why, behind ⓘ.
                VStack(spacing: Space.s) {
                    FileIcon(path: path, folder: false, size: 48).opacity(0.6)
                    HStack(spacing: Space.xs) {
                        StatusLabel(mark: Wording.undrawable.mark, text: Wording.undrawable.title, size: 11)
                        InfoButton(text: Wording.undrawable.detail)
                    }
                    .font(.caption)
                }
                .help(Wording.undrawable.detail)
            case .none:
                FileIcon(path: path, folder: false, size: 48).opacity(0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tag))
        .overlay(RoundedRectangle(cornerRadius: Radius.tag).strokeBorder(Color(nsColor: .separatorColor)))
        .task(id: "\(path)|\(generation)") {
            // No more pixels than the widest tile shows.
            let loaded = await ImageFile.load(path, pixels: Int((Self.widest * scale).rounded(.up)))
            image = .some(loaded)
            if let loaded, Self.legible(loaded.size) { rendered() }
        }
        .accessibilityElement()
        .accessibilityLabel((path as NSString).lastPathComponent)
        .accessibilityValue(image == .some(nil) ? Wording.undrawable.title + ". " + Wording.undrawable.detail : "")
        .accessibilityAddTraits(.isImage)
    }

    /// Whether a picture of `size` is drawn large enough to see in the narrowest tile: one far
    /// taller or wider than that (a long scroll, a thin banner) is a sliver there, and is judged on
    /// its own.
    static func legible(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let scale = min(width / size.width, height / size.height)
        return min(size.width, size.height) * scale >= height / 5
    }
}

/// A document as the preview pane renders it: Markdown and text from their words, as tall as they
/// are up to a height, anything else (a PDF, a page) by Quick Look. Text past the first 64 KB isn't
/// shown, and the page says so.
struct DocumentItem: View {
    var url: URL
    var generation: Int
    /// Called once the words are drawn whole. Gleaner can't tell what Quick Look drew, nor is a
    /// document cut off drawn whole.
    var rendered: () -> Void
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
                .overlay(alignment: .bottomTrailing) {
                    if text.truncated {
                        Text("First 64 KB").font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, Space.s).padding(.vertical, 2)
                            .surface(.floating, in: Capsule())
                            .padding(Space.s)
                            .help("Only its first 64 KB are shown here, so Review All leaves it to its own Review menu. Open it to read the rest.")
                    }
                }
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
            if let text, !text.truncated { rendered() }
        }
    }
}

/// A work's name, its four states, and what the person can do: Review ▸ (Approve; Request
/// Changes…; Reject…), Mark Published…, and More, which opens the work's own detail; with no file
/// Gleaner can read there, Remove from Collection in their place. The states are marks, with words
/// only where something needs a look; every word is in the help tags and for VoiceOver. A verdict
/// or mark refused for this file is said under it.
struct ReviewBar: View {
    @Environment(LibraryModel.self) private var model
    var work: Work
    /// The file as it was shown; nil when no regular file was there to show.
    var shown: FileStat?
    /// Named beside the work whose name differs from its own only by extension.
    var beside = false
    /// The file's icon before its name, where nothing above shows the file.
    var icon = false
    /// Why a verdict or mark asked for here wasn't made.
    var refused: String?
    var ask: (Asking) -> Void
    var lookAgain: () -> Void

    var body: some View {
        let states = ReviewStates(work: work, model: model)
        VStack(alignment: .leading, spacing: Space.xs) {
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
            if let refused {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    StatusLabel(mark: .attention, text: refused, size: 11).fixedSize(horizontal: false, vertical: true)
                    Button("Look Again", action: lookAgain).controlRole(.inline)
                }
                .font(.caption)
            }
        }
        // What Git keeps of a file whose judged bytes Gleaner doesn't, for its label.
        .task(id: states.notKept == nil) { if states.notKept != nil { await model.lookUpGit([work.latest.path]) } }
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
        let path = work.latest.path, place = work.unit
        let judged = shown.map { [path: $0] } ?? [:]
        if model.hasNoFile(work) && work.kind != .folder {
            // Nothing here to judge: what the person can do instead.
            Button("Remove from Collection") { Task { await model.remove([work]) } }
                .help("Take it out of its collection. No file changes.")
        } else {
            Menu("Review") {
                Button("Approve") { ask(Asking(works: [work], kind: .approved, shown: judged, place: place)) }
                Button("Request Changes…") { ask(Asking(works: [work], kind: .changesRequested, shown: judged, place: place)) }
                Button("Reject…") { ask(Asking(works: [work], kind: .rejected, shown: judged, place: place)) }
            }
            .fixedSize()
            .disabled(shown == nil || work.kind == .folder)
            .help(shown == nil || work.kind == .folder ? "No bytes here to judge" : "A verdict on the file as shown, bound to the bytes hashed as you make it")
            Button("Mark Published…") { ask(Asking(works: [work], kind: .published, shown: judged, place: place)) }
                .disabled(shown == nil || work.kind == .folder)
        }
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
    /// That Gleaner keeps no copy of the bytes the current verdict, or else the current published
    /// mark, was made on; nil while it does, or with neither.
    var notKept: Statement?

    @MainActor init(work: Work, model: LibraryModel) {
        let current = work.latest.latest
        generated = Wording.generated(current)
        kept = current.kept != nil
        provider = current.provider
        onThisMac = model.onThisMac(work)
        reviewed = work.kind == .folder ? Statement(mark: .na, title: "Not reviewed", detail: "A folder has no bytes of its own to judge.")
            : Wording.verdict(model.verdict(of: work), inUnit: work.unit != nil, noFile: model.hasNoFile(work))
        published = Wording.publishedState(model.published(of: work))
        notKept = [model.verdict(of: work), model.published(of: work)].lazy.compactMap { standing -> Review? in
            switch standing {
            case .current(let review), .unavailable(let review): review
            default: nil
            }
        }.first.flatMap(model.notKept)
    }

    /// The four, in one sentence for VoiceOver, and whether the bytes judged are kept.
    var spoken: String {
        ([generated.title, onThisMac.title, reviewed.title, published.title] + [notKept?.title].compactMap { $0 }).joined(separator: ", ")
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
            if let notKept = states.notKept { label(notKept) }
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
    /// Save a Copy: on at first for Request Changes, since the changes will be made over the file.
    @State private var save: Bool

    init(asking: Asking) {
        self.asking = asking
        _save = State(initialValue: Self.savesByDefault(asking.kind))
    }

    /// Whether Save a Copy starts on: for Request Changes, since the changes will be made over the
    /// file, and the bytes judged with them.
    static func savesByDefault(_ kind: Review.Kind) -> Bool { kind == .changesRequested }

    var body: some View {
        // The bytes this verdict wouldn't keep unless the person asks (docs/design/review.md, Keeping
        // what was judged).
        let unkept = model.wouldNotKeep(asking.works, shown: asking.shown)
        VStack(alignment: .leading, spacing: Space.m) {
            Text(Wording.reviewTitle(asking.kind, names: asking.works.map(\.name)))
                .font(.headline)
            Text(asking.kind == .published ? "The mark is bound to the bytes Gleaner hashes as you make it. Where, in words or a link, is optional."
                 : "The verdict is bound to the bytes Gleaner hashes as you make it, never to the file’s later bytes. A note is optional.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField(asking.kind == .published ? "Where" : "Note", text: $note,
                      prompt: Text(asking.kind == .published ? "Where it was published" : "What to change"), axis: .vertical)
                .lineLimit(3...6)
            if !unkept.isEmpty {
                let one = unkept.count == 1 ? unkept[0] : nil
                let statement = Wording.wontKeep(count: unkept.count, size: unkept.map(\.size).reduce(0, +),
                                                 git: one.flatMap { model.gitState(of: $0.work.latest.path, as: $0.file) },
                                                 worktree: one?.work.latest.inWorktree ?? false)
                // What would be lost, then what keeps it.
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    StatusLabel(mark: statement.mark, text: statement.title, size: 11).font(.caption)
                    InfoButton(text: statement.detail)
                    Spacer(minLength: Space.s)
                    Toggle(unkept.count == 1 ? "Save a Copy" : "Save Copies", isOn: $save)
                        .help("Keep the bytes you judge, as Save a Copy keeps a delivery’s")
                }
                .task { await model.lookUpGit(unkept.map(\.work.latest.path)) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Wording.reviewAction(asking.kind)) {
                    let asking = asking, note = note, save = save && !unkept.isEmpty
                    Task { await model.review(asking.works, as: asking.kind, note: note, shown: asking.shown, save: save, from: asking.place) }
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
        let judged = shown.map { [work.latest.path: $0] } ?? [:], place = work.id
        DetailSection(title: "Review") {
            HStack(spacing: Space.s) {
                Menu("Review") {
                    Button("Approve") { Task { await model.review([work], as: .approved, shown: judged, from: place) } }
                    Button("Request Changes…") { asking = Asking(works: [work], kind: .changesRequested, shown: judged, place: place) }
                    Button("Reject…") { asking = Asking(works: [work], kind: .rejected, shown: judged, place: place) }
                }
                .fixedSize()
                Button("Mark Published…") { asking = Asking(works: [work], kind: .published, shown: judged, place: place) }
            }
            .controlRole(.inline)
            .disabled(shown == nil || work.kind == .folder)
            .help(work.kind == .folder ? "A folder has no bytes of its own to judge"
                  : shown == nil ? "A verdict is bound to the bytes hashed as it is made: show the file’s current bytes to judge them" : "")
        } content: {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.s + 2) {
                InfoRow(label: "Collection") {
                    HStack(spacing: Space.s) {
                        if let unit = organization.unit(of: work)?.unit {
                            Label { LinkButton(title: Wording.unitPath(unit, in: organization)) { model.place = .unit(unit.key); model.selection = work.id } } icon: {
                                GlyphView(glyph: .collection, size: 14).foregroundStyle(Palette.mark)
                            }
                            Button("Remove") { Task { await model.remove([work]) } }
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
                // A state as it should be says nothing: no verdict outside a collection, no mark.
                if work.unit != nil || model.verdict(of: work) != .none {
                    InfoRow(label: "Reviewed") { state(states.reviewed) }
                }
                if model.published(of: work) != .none {
                    InfoRow(label: "Published") { state(states.published) }
                }
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
            // Refused here, said here, until the person shows another work.
            if let refusal = model.reviewRefusal, refusal.place == work.id {
                StatusLabel(mark: .attention, text: refusal.refused.map(\.reason).joined(separator: " ")).font(.callout)
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
    /// Why Save a Copy couldn't keep its bytes.
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            line
            // Bytes Gleaner holds no copy of: said, with the way to keep them while the file has them.
            if let notKept = model.notKept(review) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    StatusLabel(mark: notKept.mark, text: notKept.title, size: 11)
                    InfoButton(text: notKept.detail)
                    if model.mayStillHold(review) {
                        Button("Save a Copy") { Task { failure = await model.saveCopy(of: review) } }
                            .controlRole(.inline)
                            .help("Keep the bytes this was made on, while the file still holds them")
                    }
                    if let failure { Text(failure).foregroundStyle(.secondary) }
                }
                .font(.caption)
                .padding(.leading, 14 + Space.s)
                .task(id: review.id) { await model.lookUpGit([review.path]) }
            }
        }
    }

    var line: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            judged
            Spacer(minLength: Space.s)
            // Kept bytes no revision recorded, beside other bytes on disk now: what was judged
            // beside what is there. Bytes a revision recorded are compared under Versions.
            if let ends = model.reviewComparison(review) {
                Button("Compare") { model.comparison = ends }
                    .controlRole(.inline)
                    .help("Compare the bytes this was made on, from Gleaner’s saved copy, with the file on disk now")
            }
            Button("Undo") { Task { await model.undo([review]) } }
                .controlRole(.inline)
                .accessibilityLabel("Undo: \(Wording.historyLine(review, file: file))")
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    /// What it is, when, the bytes it binds to, and its note. While Gleaner keeps those bytes, it is
    /// the file to drag (docs/design/components.md): it washes under the pointer, takes the grab
    /// pointer, and hands them over as any version is, staged and hashed. Otherwise it offers no drag.
    @ViewBuilder var judged: some View {
        let summary = HStack(alignment: .firstTextBaseline, spacing: Space.s) {
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
        }
        if model.hasSaved(review.sha256) {
            summary
                // The wash reaches past the text by its own padding, which the line doesn't take.
                .padding(.horizontal, Space.xs)
                .hoverWash()
                .padding(.horizontal, -Space.xs)
                .pointerStyle(.grabIdle)
                .onDrag { model.reviewItem(review) ?? NSItemProvider() }
                .help("Drag to hand over the bytes this was made on, from Gleaner’s saved copy")
        } else {
            summary
        }
    }
}
