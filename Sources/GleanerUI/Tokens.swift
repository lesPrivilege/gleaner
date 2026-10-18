import SwiftUI

/// Gleaner's spacing, after the Praxis kit's values (`kit/design/marks/tokens.css`) read for a
/// native window: a 4-point step. Sections of a detail stand `xl` apart and the items inside
/// them `s`. Text sizes stay the system's text styles.
public enum Space {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

/// Two radii: one for tags and small rows, one for cards (a page, a panel, a banner).
public enum Radius {
    public static let tag: CGFloat = 4
    public static let card: CGFloat = 10
}

/// Motion only shows a state switching, something arriving or leaving, or where it went
/// (`kit/design/motion`). It follows the model, which has already changed: a new click reverses
/// or replaces it, and nothing waits for it. Under Reduce Motion there is none; the words and
/// marks still change.
///
/// Each token is called with the person's Reduce Motion setting and gives its animation, or nil:
///
///     withAnimation(Motion.state(reduceMotion)) { copied = true }
public enum Motion: CaseIterable, Sendable {
    /// Hover and press: 120 ms.
    case feedback
    /// A state switching, something appearing or leaving: 200 ms.
    case state
    /// Something moving to where it now is: 240 ms.
    case move

    public var duration: Double {
        switch self {
        case .feedback: 0.12
        case .state: 0.2
        case .move: 0.24
        }
    }

    /// The cubic Bézier's two control points: out for feedback and state, in-out for a move.
    public var curve: (x1: Double, y1: Double, x2: Double, y2: Double) {
        switch self {
        case .feedback, .state: (0.2, 0, 0, 1)
        case .move: (0.45, 0, 0.25, 1)
        }
    }

    /// The token's animation, or none under Reduce Motion.
    public func callAsFunction(_ reduce: Bool) -> Animation? {
        reduce ? nil : .timingCurve(curve.x1, curve.y1, curve.x2, curve.y2, duration: duration)
    }

    /// Arrives rising a little as it fades in; leaves by fading only. Under Reduce Motion it only
    /// fades, whichever transaction carries it.
    public static func arrive(_ reduce: Bool) -> AnyTransition {
        reduce ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }
}

/// Says a result aloud to VoiceOver, once, where the action left focus.
@MainActor public func announce(_ text: String) {
    AccessibilityNotification.Announcement(text).post()
}
