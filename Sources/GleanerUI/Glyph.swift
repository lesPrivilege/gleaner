import SwiftUI

/// Gleaner's marks, drawn natively from SVG geometry on a 24-point grid with a 1.5 stroke that
/// scales with the size. Each repeats a word written beside it and is never the only carrier of a
/// meaning (Praxis `kit/design/marks`, grammar §2). The kit's glyphs are copied from its
/// `glyphs.svg`; `repository` and `work` are Gleaner's own, drawn to the same grid.
public enum Glyph: CaseIterable, Sendable {
    // Objects
    case file, artifact, work, folder, repository, person, agent, terminal, database, checkpoint
    // States: what the person must know about a thing, each with its word
    case done, running, awaiting, rejected, error, warning, unknown, unverified, missing, na, outside
    // Flows: what a decision does
    case branch, merge, retry, rollback
    // Relation endpoints: confirmed, not confirmed, declined
    case endSolid, endHollow, endCross

    struct Spec {
        var viewBox: CGRect
        var elements: [GlyphElement]
    }

    var spec: Spec {
        switch self {
        case .repository: Spec(viewBox: CGRect(x: 0, y: 0, width: 24, height: 24), elements: [
            .circle(7, 5.5, 2), .circle(7, 18.5, 2), .circle(17, 7.5, 2),
            .path("M7 7.5v9M17 9.5c0 4-10 3-10 7"),
        ])
        case .work: Spec(viewBox: CGRect(x: 0, y: 0, width: 24, height: 24), elements: [
            .path("M9.5 5h5.5l4 4v10a2 2 0 0 1-2 2H9.5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z"),
            .path("M15 5v4h4"),
            .path("M4.5 16.5V5a2 2 0 0 1 2-2h5"),
        ])
        case .file: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M7 3h7l5 5v11a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"),
            .path("M14 3v5h5"),
            .path("M8.5 13h7M8.5 16.5h4.5"),
        ])
        case .artifact: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M7 3h7l5 5v11a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"),
            .path("M14 3v5h5"),
            .path("M8.5 15h6.5M12.5 12.5L15 15l-2.5 2.5"),
        ])
        case .folder: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M3.5 7a2 2 0 0 1 2-2h3.7l2 2.5h7.3a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"),
        ])
        case .person: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .circle(12.0, 8.0, 3.5),
            .path("M5 20c0-3.9 3.1-7 7-7s7 3.1 7 7"),
        ])
        case .agent: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .rect(5.0, 8.0, 14.0, 11.5, 3.0),
            .path("M12 8V5.5M9.5 12.75v1.75M14.5 12.75v1.75"),
            .circle(12.0, 4.25, 1.25),
        ])
        case .terminal: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .rect(3.0, 4.5, 18.0, 15.0, 2.0),
            .path("M7 9.5l3 2.5-3 2.5M12.5 15h4.5"),
        ])
        case .database: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .ellipse(12.0, 6.0, 7.0, 3.0),
            .path("M5 6v12c0 1.66 3.13 3 7 3s7-1.34 7-3V6M5 12c0 1.66 3.13 3 7 3s7-1.34 7-3"),
        ])
        case .checkpoint: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M3 18.5h18M9 18.5V4.5l8.5 3.25L9 11"),
        ])
        case .done: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .circle(12.0, 12.0, 8.5),
            .path("M8 12.3l2.8 2.8L16 9.5"),
        ])
        case .running: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .circle(12.0, 12.0, 8.5),
            .circle(8.0, 12.0, 1.1, filled: true),
            .circle(12.0, 12.0, 1.1, filled: true),
            .circle(16.0, 12.0, 1.1, filled: true),
        ])
        case .awaiting: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M12 2.8l9.2 9.2-9.2 9.2L2.8 12z"),
            .path("M10.2 9.5v5M13.8 9.5v5"),
        ])
        case .rejected: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .circle(12.0, 12.0, 8.5),
            .path("M9 9l6 6M15 9l-6 6"),
        ])
        case .error: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M8.3 3.5h7.4l4.8 4.8v7.4l-4.8 4.8H8.3l-4.8-4.8V8.3z"),
            .path("M12 8v5"),
            .circle(12.0, 16.2, 1.1, filled: true),
        ])
        case .warning: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M12 3.5l9.3 16H2.7z"),
            .path("M12 10v4.5"),
            .circle(12.0, 17.0, 1.1, filled: true),
        ])
        case .unknown: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .circle(12.0, 12.0, 8.5),
            .path("M9.6 9.7a2.5 2.5 0 1 1 3.7 2.2c-.8.45-1.3 1-1.3 1.9"),
            .circle(12.0, 16.4, 1.1, filled: true),
        ])
        case .unverified: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M2.5 12h8"),
            .circle(15.5, 12.0, 5.0),
        ])
        case .branch: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M3.5 12H8c4 0 3.5-6 7.5-6H20M8 12c4 0 3.5 6 7.5 6H20M17.5 3.5L20 6l-2.5 2.5M17.5 15.5L20 18l-2.5 2.5"),
        ])
        case .merge: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M3.5 6H6c4 0 3.5 6 7.5 6H20M3.5 18H6c4 0 3.5-6 7.5-6M17.5 9.5L20 12l-2.5 2.5"),
        ])
        case .retry: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M19.5 12a7.5 7.5 0 1 1-2.2-5.3M17.6 2.9v4h-4"),
        ])
        case .rollback: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M4.5 5.5v13M20 12H8.5M12.5 8l-4 4 4 4"),
        ])
        case .missing: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M9 6H6v12h3M15 6h3v12h-3"),
        ])
        case .na: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .rect(4.5, 4.5, 15.0, 15.0, 2.0),
            .path("M8 16l8-8"),
        ])
        case .outside: Spec(viewBox: CGRect(x: 0.0, y: 0.0, width: 24.0, height: 24.0), elements: [
            .path("M5 4.5h5v15H5"),
            .circle(16.5, 12.0, 2.5),
        ])
        case .endSolid: Spec(viewBox: CGRect(x: -6.0, y: -6.0, width: 12.0, height: 12.0), elements: [
            .circle(0, 0, 3.25, filled: true),
        ])
        case .endHollow: Spec(viewBox: CGRect(x: -6.0, y: -6.0, width: 12.0, height: 12.0), elements: [
            .circle(0, 0, 3.25),
        ])
        case .endCross: Spec(viewBox: CGRect(x: -6.0, y: -6.0, width: 12.0, height: 12.0), elements: [
            .path("M-3-3l6 6M3-3l-6 6"),
        ])
        }
    }
}

/// One drawn part of a glyph: stroked unless filled; dashed when the kit dashes it.
enum GlyphElement {
    case path(String, filled: Bool = false, dash: [CGFloat] = [])
    case circle(CGFloat, CGFloat, CGFloat, filled: Bool = false, dash: [CGFloat] = [])
    case ellipse(CGFloat, CGFloat, CGFloat, CGFloat, filled: Bool = false, dash: [CGFloat] = [])
    case rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, filled: Bool = false, dash: [CGFloat] = [])

    var filled: Bool {
        switch self {
        case .path(_, let f, _), .circle(_, _, _, let f, _), .ellipse(_, _, _, _, let f, _), .rect(_, _, _, _, _, let f, _): f
        }
    }

    var dash: [CGFloat] {
        switch self {
        case .path(_, _, let d), .circle(_, _, _, _, let d), .ellipse(_, _, _, _, _, let d), .rect(_, _, _, _, _, _, let d): d
        }
    }

    /// The element in glyph units.
    var path: Path {
        switch self {
        case .path(let data, _, _): SVGPath.parse(data)
        case .circle(let x, let y, let r, _, _): Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        case .ellipse(let x, let y, let rx, let ry, _, _): Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry))
        case .rect(let x, let y, let w, let h, let r, _, _):
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }
    }
}

/// A glyph at `size` points, in the current foreground style. Hidden from VoiceOver: the word
/// beside it is what is read.
public struct GlyphView: View {
    public var glyph: Glyph
    public var size: CGFloat

    public init(glyph: Glyph, size: CGFloat = 16) {
        self.glyph = glyph
        self.size = size
    }

    /// Each glyph's parts, read from their SVG once: lists draw many marks, many times.
    private static let parts: [Glyph: [(element: GlyphElement, path: Path)]] =
        Dictionary(uniqueKeysWithValues: Glyph.allCases.map { glyph in (glyph, glyph.spec.elements.map { ($0, $0.path) }) })

    public var body: some View {
        let spec = glyph.spec
        let scale = size / spec.viewBox.width
        let transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -spec.viewBox.minX, y: -spec.viewBox.minY)
        ZStack {
            ForEach(Array((Self.parts[glyph] ?? []).enumerated()), id: \.offset) { _, part in
                let element = part.element, path = part.path.applying(transform)
                if element.filled {
                    path.fill()
                } else {
                    // Never under a point: a caption-sized mark keeps the weight of the endpoints beside it.
                    path.stroke(style: StrokeStyle(lineWidth: max(1.5 * scale, 1), lineCap: .round, lineJoin: .round,
                                                   dash: element.dash.map { $0 * scale }))
                }
            }
        }
        .frame(width: size, height: size * spec.viewBox.height / spec.viewBox.width)
        .accessibilityHidden(true)
    }
}

/// A label whose icon is one of Gleaner's marks: native chrome keeps its own symbols, and a mark is
/// used where it carries one of Gleaner's meanings. In a sidebar it follows the row: the size the
/// person chose for sidebar icons, and white on an emphasized selection.
public struct GlyphLabel: View {
    public var title: String
    public var glyph: Glyph
    public var size: CGFloat?

    public init(title: String, glyph: Glyph, size: CGFloat? = nil) {
        self.title = title
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
        Label { Text(title) } icon: { RowGlyph(glyph: glyph, size: size) }
    }
}

/// A mark sized and colored as an SF Symbol in the same row would be.
public struct RowGlyph: View {
    public var glyph: Glyph
    public var size: CGFloat?
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.sidebarRowSize) private var rowSize

    public init(glyph: Glyph, size: CGFloat? = nil) {
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
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
