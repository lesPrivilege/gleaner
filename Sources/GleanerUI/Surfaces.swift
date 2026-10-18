import AppKit
import SwiftUI

/// What a thing stands on. Things are grouped with space, alignment and type, not boxes in boxes
/// (Praxis references U04), so only these five stand on a surface of their own; everything else
/// stands on the window, and the window's chrome keeps the system's materials and glass: sidebar,
/// toolbar, popovers and sheets.
public enum Surface: CaseIterable, Sendable {
    /// A document's own page, such as the preview and the comparison: the text background with a
    /// hairline edge, as Finder and Mail set a document apart from the window.
    case page
    /// What waits on the person: the accent's wash, edged with the kit's dashed line for "not in
    /// effect yet".
    case awaiting
    /// A statement that needs a look: an amber wash and edge.
    case attention
    /// A statement about something gone: a red wash and edge.
    case lost
    /// A small thing floating over content that scrolls under it, such as "First 64 KB" on a long
    /// preview: Liquid Glass where the system has it, a material before. Under Reduce
    /// Transparency or Increase Contrast it is opaque, edged with a hairline, so it never shows
    /// text through it.
    case floating
}

extension View {
    /// Sets the view on `surface` in a card's rounded rectangle; nil keeps the same structure
    /// with nothing drawn, so a statement can gain or lose its tint without being replaced.
    public func surface(_ surface: Surface?) -> some View {
        self.surface(surface, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    /// Sets the view on `surface` in `shape`.
    public func surface(_ surface: Surface?, in shape: some InsettableShape) -> some View {
        modifier(SurfaceModifier(surface: surface, shape: shape))
    }
}

struct SurfaceModifier<S: InsettableShape>: ViewModifier {
    var surface: Surface?
    var shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        let strong = contrast == .increased
        switch surface {
        case .page?:
            content
                .background(Color(nsColor: .textBackgroundColor), in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor)))
        case .floating?:
            if reduceTransparency || strong {
                content
                    .background(Color(nsColor: .windowBackgroundColor), in: shape)
                    .overlay(shape.strokeBorder(Color(nsColor: .separatorColor)))
            } else if #available(macOS 26, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        default:
            // One structure for the washes and for none, so a change between them eases.
            content
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(edge(strong), style: StrokeStyle(lineWidth: 1, dash: surface == .awaiting ? [5, 4] : [])))
        }
    }

    var fill: Color {
        switch surface {
        case .awaiting?: Palette.awaitingWash
        case .attention?: Palette.attentionFill
        case .lost?: Palette.lostFill
        default: .clear
        }
    }

    /// The edge is a step under the ink, and the ink itself under Increase Contrast.
    func edge(_ strong: Bool) -> Color {
        switch surface {
        case .awaiting?: Palette.awaiting.opacity(strong ? 1 : 0.5)
        case .attention?: Palette.attention.opacity(strong ? 1 : 0.35)
        case .lost?: Palette.lost.opacity(strong ? 1 : 0.3)
        default: .clear
        }
    }
}

extension View {
    /// A wash under the pointer, for a surface that is itself the thing to drag or open, such as
    /// the file at the top of a detail. It eases in at the feedback duration, at once under
    /// Reduce Motion, and is stronger under Increase Contrast. Lists and tables don't wash their
    /// rows: the system's selection is their feedback.
    public func hoverWash(_ enabled: Bool = true) -> some View {
        modifier(HoverWash(enabled: enabled))
    }
}

struct HoverWash: ViewModifier {
    var enabled: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(Self.fill(enabled && hovering, contrast), in: RoundedRectangle(cornerRadius: Radius.card))
            .onHover { hovering in withAnimation(Motion.feedback(reduceMotion)) { self.hovering = hovering } }
    }

    /// The label ink at 6% under the pointer, 12% under Increase Contrast; nothing at rest.
    static func fill(_ hovering: Bool, _ contrast: ColorSchemeContrast) -> Color {
        hovering ? Color.primary.opacity(contrast == .increased ? 0.12 : 0.06) : .clear
    }
}
