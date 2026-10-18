import SwiftUI

/// A state is said in three tiers, each only as far as it is needed:
/// - **the mark:** a shape that stays apart from the others in grey: an endpoint for whether
///   the bytes were confirmed, brackets for a missing value, a triangle for a look, an octagon
///   for a failed read, a diamond for what waits on the person;
/// - **the label:** one to three words beside the mark, for a state that needs a look;
/// - **the sentence:** why, behind the label's info button, in its help and to VoiceOver.
/// A state that is as it should be draws its mark alone, or nothing (Praxis kit,
/// foundations/standing.md; macOS lists mark the exception, not the rule).
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
    /// Gone for good: brackets, red.
    case cross
    /// Tried to read it and couldn't: the octagon, amber.
    case failed
    /// Waits on the person's decision: the diamond, the one accent.
    case awaiting
    /// The person declined it; it stays shown: the crossed circle.
    case declined
    /// Under way, for as long as it takes: three dots, never a percentage.
    case running
    /// Done, such as read or copied: the check.
    case done

    public var glyph: Glyph {
        switch self {
        case .solid: .endSolid
        case .hollow: .endHollow
        case .dashed, .cross: .missing
        case .na: .na
        case .attention: .warning
        case .failed: .error
        case .awaiting: .awaiting
        case .declined: .rejected
        case .running: .running
        case .done: .done
        }
    }

    public var color: Color {
        switch self {
        case .solid, .hollow, .done: .primary
        case .dashed, .na, .declined, .running: .secondary
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

/// A state's mark and label, in the mark's color. The label is what VoiceOver reads; the mark is
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
