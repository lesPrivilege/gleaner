import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Gleaner's spacing, radii and motion, after the Praxis kit's values (`kit/design/marks/tokens.css`)
/// read for a native window: spacing on a 4-point step, one radius for tags and one for cards, and
/// three durations that each name what they show. Text sizes stay the system's text styles.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let tag: CGFloat = 4
    static let card: CGFloat = 10
}

/// Motion only shows a state switching, something arriving or leaving, or where it went
/// (`kit/design/motion`). It follows the model, which has already changed: a new click reverses
/// or replaces it, and nothing waits for it. Under Reduce Motion there is none; the words and
/// marks still change.
enum Motion {
    /// Hover and press.
    static func feedback(_ reduce: Bool) -> Animation? {
        reduce ? nil : .timingCurve(0.2, 0, 0, 1, duration: 0.12)
    }

    /// A state switching, something appearing or leaving.
    static func state(_ reduce: Bool) -> Animation? {
        reduce ? nil : .timingCurve(0.2, 0, 0, 1, duration: 0.2)
    }

    /// Something moving to where it now is.
    static func move(_ reduce: Bool) -> Animation? {
        reduce ? nil : .timingCurve(0.45, 0, 0.25, 1, duration: 0.24)
    }

    /// Arrives rising a little as it fades in; leaves by fading only. Under Reduce Motion it only
    /// fades, whichever transaction carries it.
    static func arrive(_ reduce: Bool) -> AnyTransition {
        reduce ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }
}

/// Says a result aloud to VoiceOver, once, where the action left focus.
@MainActor func announce(_ text: String) {
    AccessibilityNotification.Announcement(text).post()
}

/// A command that copies text, then says "Copied" in its place for a moment, with the done mark:
/// the word carries the result, the mark repeats it. Both labels take the same room, so nothing
/// beside it moves; a second click starts the moment again.
struct CopyButton: View {
    var title: String
    var text: String
    var copy: (String) -> Void
    @State private var copied = false
    @State private var reset: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            copy(text)
            withAnimation(Motion.state(reduceMotion)) { copied = true }
            announce("Copied")
            reset?.cancel()
            reset = Task {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.state(reduceMotion)) { copied = false }
            }
        } label: {
            ZStack {
                Label { Text("Copied") } icon: { GlyphView(glyph: .done, size: 13) }.opacity(copied ? 1 : 0)
                Text(title).opacity(copied ? 0 : 1)
            }
        }
        .onDisappear { reset?.cancel() }
    }
}

/// A link: ink with a standing underline, never the accent's blue, which marks only what waits on
/// the person. The underline darkens under the pointer, and the pointer is a hand.
struct LinkButton: View {
    var title: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title).underline(true, color: hovering ? .primary : Color(nsColor: .tertiaryLabelColor))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
    }
}

/// A label whose icon is one of Gleaner's marks: native chrome keeps its own symbols, and a mark is
/// used where it carries one of Gleaner's meanings. In a sidebar it follows the row: the size the
/// person chose for sidebar icons, and white on an emphasized selection.
struct GlyphLabel: View {
    var title: String
    var glyph: Glyph
    var size: CGFloat?

    var body: some View {
        Label { Text(title) } icon: { RowGlyph(glyph: glyph, size: size) }
    }
}

/// A mark sized and colored as an SF Symbol in the same row would be.
struct RowGlyph: View {
    var glyph: Glyph
    var size: CGFloat?
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.sidebarRowSize) private var rowSize

    var body: some View {
        GlyphView(glyph: glyph, size: size ?? sidebarSize)
            .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(Palette.mark))
    }

    var sidebarSize: CGFloat {
        switch rowSize {
        case .small: 14
        case .large: 20
        default: 16
        }
    }
}

/// An empty or waiting state: its mark drawn large, a short title, and the next step as a
/// control. A line under the title only for a fact the person needs, never how to use the window.
struct EmptyState<Actions: View>: View {
    var title: String
    var glyph: Glyph
    var description: String? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        ContentUnavailableView {
            Label { Text(title) } icon: { GlyphView(glyph: glyph, size: 40).foregroundStyle(.secondary) }
        } description: {
            if let description { Text(description) }
        } actions: {
            actions
        }
    }
}

extension EmptyState where Actions == EmptyView {
    init(title: String, glyph: Glyph, description: String? = nil) {
        self.init(title: title, glyph: glyph, description: description) { EmptyView() }
    }
}

/// A file's own icon, as Finder draws it for its type: the extension stays in the file's name, so
/// the icon needs no words of its own.
struct FileIcon: View {
    var path: String
    var folder = false
    var size: CGFloat

    var body: some View {
        Image(nsImage: Self.icon(path, folder: folder))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func icon(_ path: String, folder: Bool) -> NSImage {
        let ext = (path as NSString).pathExtension.lowercased()
        let key = folder ? "/" : ext
        if let image = cache[key] { return image }
        let type = folder ? UTType.folder : UTType(filenameExtension: ext) ?? .data
        let image = NSWorkspace.shared.icon(for: type)
        cache[key] = image
        return image
    }
}

/// The sentence behind a short label, one click away: a popover, also in the help tag and read
/// by VoiceOver, so nothing needed is hover-only.
struct InfoButton: View {
    var text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").imageScale(.small)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(text)
        .accessibilityLabel("More Info")
        .accessibilityValue(text)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(Space.m)
        }
    }
}

/// A section of the detail, titled as Finder's preview pane titles its own: a heading, then its
/// content, with room above it that sets it apart from the section before.
struct DetailSection<Trailing: View, Content: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(title).font(.headline)
                Spacer(minLength: Space.s)
                trailing
            }
            Divider()
            content
        }
    }
}

extension DetailSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// One line of facts, labeled as Get Info labels them: the label right-aligned in its column, the
/// value after it.
struct InfoRow<Value: View>: View {
    var label: String
    @ViewBuilder var value: Value

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension InfoRow where Value == Text {
    init(_ label: String, _ value: String) {
        self.init(label: label) { Text(value) }
    }
}
