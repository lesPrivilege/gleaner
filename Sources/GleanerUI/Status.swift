import SwiftUI

/// A state is said in three tiers, each only as far as it is needed:
/// - **the mark alone** (`StatusMark`), for a state that is as it should be: its word is in the
///   help tag and is what VoiceOver reads;
/// - **the mark and its label** (`StatusLabel`), one to three words, for a state that needs a look;
/// - **the sentence:** why, behind the label's info button or in a `StatusPanel`, in its help and
///   to VoiceOver.
/// Each mark is a shape that stays apart from the others in grey: an endpoint for whether the
/// bytes were confirmed, brackets for a missing value and a cross between them for one gone, a
/// triangle for a look, an octagon for a failed read, a diamond for what waits on the person, a
/// line to an open circle for what was only observed, an open arrow for what was asked again, and
/// an arrow leaving a tray for what the person sent out (Praxis kit, foundations/standing.md;
/// macOS lists mark the exception, not the rule).
public enum Mark: CaseIterable, Sendable {
    /// Confirmed: the filled endpoint.
    case solid
    /// Not confirmed (first seen later): the hollow endpoint.
    case hollow
    /// No value here, nothing lost: brackets.
    case dashed
    /// Doesn't apply here, such as a version of a folder: the slashed square.
    case na
    /// Needs a look: the triangle, amber.
    case attention
    /// Gone for good: a cross between brackets, red.
    case cross
    /// Tried to read it and couldn't: the octagon, amber.
    case failed
    /// Waits on the person's decision: the diamond, the one accent.
    case awaiting
    /// The person declined it; it stays shown: the crossed circle. A pair kept apart, a file rejected.
    case declined
    /// Under way, for as long as it takes: three dots, never a percentage.
    case running
    /// Done, such as read, copied or approved: the check.
    case done
    /// Observed on the disk during a session, not handed over and not checked: the kit's
    /// unverified mark, a line to an open circle.
    case observed
    /// The person asked for it again, with changes: the open arrow.
    case revise
    /// The person marked it sent out, published: an arrow leaving a tray.
    case published

    public var glyph: Glyph {
        switch self {
        case .solid: .endSolid
        case .hollow: .endHollow
        case .dashed: .missing
        case .cross: .lost
        case .na: .na
        case .attention: .warning
        case .failed: .error
        case .awaiting: .awaiting
        case .declined: .rejected
        case .running: .running
        case .done: .done
        case .observed: .unverified
        case .revise: .retry
        case .published: .published
        }
    }

    public var color: Color {
        switch self {
        case .solid, .hollow, .done, .revise, .published: .primary
        case .dashed, .na, .declined, .running, .observed: .secondary
        case .attention, .failed: Palette.attention
        case .cross: Palette.lost
        case .awaiting: Palette.awaiting
        }
    }

    /// The tinted surface a statement with this mark stands on when it stands alone: amber for a
    /// look, red for gone. A state that needs no look stands on nothing.
    public var surface: Surface? {
        switch self {
        case .attention, .failed: .attention
        case .cross: .lost
        default: nil
        }
    }
}

/// A state: its mark, its label, and the sentence that says why.
public struct Statement: Equatable, Sendable {
    public var mark: Mark
    public var title: String
    public var detail: String

    public init(mark: Mark, title: String, detail: String) {
        self.mark = mark
        self.title = title
        self.detail = detail
    }
}

/// The first tier: a state that is as it should be, said by its mark alone, as a Mac list marks
/// only the exception. Its word is the help tag, and what VoiceOver reads.
public struct StatusMark: View {
    public var mark: Mark
    public var word: String
    public var size: CGFloat

    public init(mark: Mark, word: String, size: CGFloat = 12) {
        self.mark = mark
        self.word = word
        self.size = size
    }

    public var body: some View {
        GlyphView(glyph: mark.glyph, size: size)
            .foregroundStyle(mark.color)
            .help(word)
            .accessibilityElement()
            .accessibilityLabel(word)
    }
}

/// The second tier: a state's mark and label, in the mark's color. The label is what VoiceOver reads; the mark is
/// hidden from it.
public struct StatusLabel: View {
    public var mark: Mark
    public var text: String
    /// The mark's size: caption text takes 11 or 12, a heading 14 or 15.
    public var size: CGFloat

    public init(mark: Mark, text: String, size: CGFloat = 12) {
        self.mark = mark
        self.text = text
        self.size = size
    }

    public var body: some View {
        Label {
            Text(text)
        } icon: {
            GlyphView(glyph: mark.glyph, size: size)
        }
        .foregroundStyle(mark.color)
    }
}

/// A state that needs more than its label: the mark and label, the sentence, then what to do. It
/// stands on a tinted surface only when the person needs to look (amber) or something is gone
/// (red); otherwise it is plain text in its place, so boxes don't stack inside boxes. A new
/// statement takes the old one's place rather than stacking under it.
public struct StatusPanel<Actions: View>: View {
    public var statement: Statement
    public var actions: Actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(statement: Statement, @ViewBuilder actions: () -> Actions) {
        self.statement = statement
        self.actions = actions()
    }

    public var body: some View {
        let surface = statement.mark.surface
        VStack(alignment: .leading, spacing: Space.s) {
            ZStack(alignment: .leading) {
                StatusLabel(mark: statement.mark, text: statement.title, size: 14).font(.headline)
                    .id(statement.title).transition(.opacity)
            }
            Text(statement.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) { actions }
        }
        .padding(surface == nil ? 0 : Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(surface)
        .animation(Motion.state(reduceMotion), value: statement.title)
    }
}

extension StatusPanel where Actions == EmptyView {
    public init(statement: Statement) {
        self.init(statement: statement) { EmptyView() }
    }
}
