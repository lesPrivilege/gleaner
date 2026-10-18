import SwiftUI

/// A relation as the kit's relation grammar draws one (`foundations/relations.md`): a line that is
/// solid while the relation is in effect and dashed while it is not, ending in what it says of
/// its far end: confirmed (filled), not confirmed (hollow), or declined (a cross).
public enum RelationEnd: Sendable {
    case solid, hollow, cross

    var glyph: Glyph {
        switch self {
        case .solid: .endSolid
        case .hollow: .endHollow
        case .cross: .endCross
        }
    }
}

/// A relation drawn across: from what is beside it on the left, to its end on the right, if it
/// has one. Between two marks, such as an agent and the provider it sends to, it has none.
public struct RelationLine: View {
    public var inEffect: Bool
    public var end: RelationEnd?
    public var length: CGFloat

    public init(inEffect: Bool, end: RelationEnd? = nil, length: CGFloat = 20) {
        self.inEffect = inEffect
        self.end = end
        self.length = length
    }

    public var body: some View {
        // The line stops short of an end, so the end reads as its own shape.
        let reach = end == nil ? length : length - 6
        ZStack(alignment: .leading) {
            Path { $0.move(to: CGPoint(x: 0, y: 6)); $0.addLine(to: CGPoint(x: reach, y: 6)) }
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: inEffect ? [] : [2, 3]))
            if let end {
                GlyphView(glyph: end.glyph, size: 8).offset(x: length - 7)
            }
        }
        .frame(width: length, height: 12, alignment: .leading)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

/// One node on a relation drawn down a list, such as a work's files in the order they arrived:
/// the line into it from the row above, the line out of it to the row below, and its end. The
/// line stops at the end's edge, so the end reads as one shape. The rows set its height.
public struct RelationNode: View {
    public var into: Bool
    public var out: Bool
    public var end: RelationEnd

    public init(into: Bool, out: Bool, end: RelationEnd = .solid) {
        self.into = into
        self.out = out
        self.end = end
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 8) {
                Rectangle().fill(into ? Color.secondary : Color.clear).frame(width: 1.5)
                Rectangle().fill(out ? Color.secondary : Color.clear).frame(width: 1.5)
            }
            GlyphView(glyph: end.glyph, size: 12).foregroundStyle(.secondary)
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }
}
