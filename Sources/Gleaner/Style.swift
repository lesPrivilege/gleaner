import SwiftUI

/// Gleaner's spacing, radii and motion, after the Praxis kit's values (`kit/design/marks/tokens.css`)
/// read for a native window: spacing on a 4-point step, one radius for tags and one for cards, and
/// three durations that each name what they show. Text sizes stay the system's text styles.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Radius {
    static let tag: CGFloat = 4
    static let control: CGFloat = 6
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

    /// Arrives rising a little as it fades in; leaves by fading only, without moving.
    static var arrive: AnyTransition { .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity) }
}

/// Says a result aloud to VoiceOver, once, where the action left focus.
@MainActor func announce(_ text: String) {
    AccessibilityNotification.Announcement(text).post()
}

/// A command that copies text, then says "Copied" in its place for a moment, with the done mark:
/// the word carries the result, the mark repeats it.
struct CopyButton: View {
    var title: String
    var text: String
    var copy: (String) -> Void
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            copy(text)
            withAnimation(Motion.state(reduceMotion)) { copied = true }
            announce("Copied")
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(Motion.state(reduceMotion)) { copied = false }
            }
        } label: {
            if copied {
                Label { Text("Copied") } icon: { GlyphView(glyph: .done, size: 13) }
                    .transition(.opacity)
            } else {
                Text(title).transition(.opacity)
            }
        }
    }
}

/// A link-styled button that underlines under the pointer: color is not the only sign it goes
/// somewhere.
struct LinkButton: View {
    var title: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) { Text(title).underline(hovering) }
            .buttonStyle(.link)
            .onHover { hovering = $0 }
    }
}

/// A label whose icon is one of Gleaner's marks, in the secondary label color: native chrome keeps
/// its own symbols, and a mark is used where it carries one of Gleaner's meanings. The color is a
/// plain one, not the hierarchical style, which the sidebar's material would blend away.
struct GlyphLabel: View {
    var title: String
    var glyph: Glyph
    var size: CGFloat = 16

    var body: some View {
        Label { Text(title) } icon: { GlyphView(glyph: glyph, size: size).foregroundStyle(Palette.mark) }
    }
}

/// An empty or waiting state with its mark drawn large, its words, and what to do.
struct EmptyState<Actions: View>: View {
    var title: String
    var glyph: Glyph
    var description: String
    @ViewBuilder var actions: Actions

    var body: some View {
        ContentUnavailableView {
            Label { Text(title) } icon: { GlyphView(glyph: glyph, size: 40).foregroundStyle(.secondary) }
        } description: {
            Text(description)
        } actions: {
            actions
        }
    }
}

extension EmptyState where Actions == EmptyView {
    init(title: String, glyph: Glyph, description: String) {
        self.init(title: title, glyph: glyph, description: description) { EmptyView() }
    }
}
