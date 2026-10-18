import SwiftUI

/// Gleaner's marks, drawn natively from SVG geometry on a 24-point grid with a 1.5 stroke that
/// scales with the size. Each repeats a word written beside it and is never the only carrier of a
/// meaning (Praxis `kit/design/marks`, grammar §2). The kit's glyphs are copied from its
/// `glyphs.svg`; `repository` and `work` are Gleaner's own, drawn to the same grid.
enum Glyph: CaseIterable {
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
struct GlyphView: View {
    var glyph: Glyph
    var size: CGFloat = 16

    var body: some View {
        let spec = glyph.spec
        let scale = size / spec.viewBox.width
        let transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -spec.viewBox.minX, y: -spec.viewBox.minY)
        ZStack {
            ForEach(Array(spec.elements.enumerated()), id: \.offset) { _, element in
                let path = element.path.applying(transform)
                if element.filled {
                    path.fill()
                } else {
                    path.stroke(style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round,
                                                   dash: element.dash.map { $0 * scale }))
                }
            }
        }
        .frame(width: size, height: size * spec.viewBox.height / spec.viewBox.width)
        .accessibilityHidden(true)
    }
}

/// Reads SVG path data (M L H V C S Q T A Z, absolute and relative) into a Path. Elliptical arcs
/// become cubic curves (SVG 1.1, F.6).
enum SVGPath {
    static func parse(_ data: String) -> Path {
        var tokens = Tokens(data)
        var path = Path()
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?, lastQuadratic: CGPoint?
        var command: Character = "M"
        while let next = tokens.command() ?? (tokens.hasNumber ? command : nil) {
            command = next
            let relative = command.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            var control: CGPoint?, quadratic: CGPoint?
            switch command.uppercased() {
            case "M":
                current = point(tokens.number(), tokens.number())
                start = current
                path.move(to: current)
                // Further pairs after a move are lines.
                command = relative ? "l" : "L"
            case "L":
                current = point(tokens.number(), tokens.number())
                path.addLine(to: current)
            case "H":
                let x = tokens.number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V":
                let y = tokens.number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "C":
                let c1 = point(tokens.number(), tokens.number()), c2 = point(tokens.number(), tokens.number())
                let end = point(tokens.number(), tokens.number())
                path.addCurve(to: end, control1: c1, control2: c2)
                control = c2
                current = end
            case "S":
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(tokens.number(), tokens.number()), end = point(tokens.number(), tokens.number())
                path.addCurve(to: end, control1: c1, control2: c2)
                control = c2
                current = end
            case "Q":
                let c = point(tokens.number(), tokens.number()), end = point(tokens.number(), tokens.number())
                path.addQuadCurve(to: end, control: c)
                quadratic = c
                current = end
            case "T":
                let c = lastQuadratic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let end = point(tokens.number(), tokens.number())
                path.addQuadCurve(to: end, control: c)
                quadratic = c
                current = end
            case "A":
                let rx = tokens.number(), ry = tokens.number(), rotation = tokens.number()
                let large = tokens.flag(), sweep = tokens.flag()
                let end = point(tokens.number(), tokens.number())
                arc(&path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end
            case "Z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
            lastControl = control
            lastQuadratic = quadratic
        }
        return path
    }

    /// SVG 1.1 F.6.5: endpoint to center parameters, then quarter-turn cubic segments.
    static func arc(_ path: inout Path, from p1: CGPoint, to p2: CGPoint, rx: CGFloat, ry: CGFloat,
                    rotation: CGFloat, large: Bool, sweep: Bool) {
        guard p1 != p2 else { return }
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0 else { path.addLine(to: p2); return }
        let phi = rotation * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = sqrt(max(0, numerator / denominator))
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry, cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p1.x + p2.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p1.y + p2.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let sign: CGFloat = ux * vy - uy * vx < 0 ? -1 : 1
            let dot = (ux * vx + uy * vy) / (sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy))
            return sign * acos(min(1, max(-1, dot)))
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = Int(ceil(abs(delta) / (.pi / 2)))
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        func at(_ t: CGFloat) -> (point: CGPoint, tangent: CGPoint) {
            let x = rx * cos(t), y = ry * sin(t), tx = -rx * sin(t), ty = ry * cos(t)
            return (CGPoint(x: cx + cosPhi * x - sinPhi * y, y: cy + sinPhi * x + cosPhi * y),
                    CGPoint(x: cosPhi * tx - sinPhi * ty, y: sinPhi * tx + cosPhi * ty))
        }
        var t = theta1
        for _ in 0..<segments {
            let a = at(t), b = at(t + step)
            path.addCurve(to: b.point,
                          control1: CGPoint(x: a.point.x + k * a.tangent.x, y: a.point.y + k * a.tangent.y),
                          control2: CGPoint(x: b.point.x - k * b.tangent.x, y: b.point.y - k * b.tangent.y))
            t += step
        }
    }

    /// Commands and numbers as SVG writes them: "1.5.5" is two numbers, "-2-2" two, arc flags one digit.
    struct Tokens {
        private let chars: [Character]
        private var index = 0

        init(_ data: String) { chars = Array(data) }

        private mutating func skip() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index].isNewline { index += 1 }
        }

        var hasNumber: Bool {
            var probe = self
            probe.skip()
            guard probe.index < probe.chars.count else { return false }
            return "+-.0123456789".contains(probe.chars[probe.index])
        }

        mutating func command() -> Character? {
            skip()
            guard index < chars.count, chars[index].isLetter, chars[index] != "e", chars[index] != "E" else { return nil }
            defer { index += 1 }
            return chars[index]
        }

        mutating func flag() -> Bool {
            skip()
            guard index < chars.count else { return false }
            defer { index += 1 }
            return chars[index] == "1"
        }

        mutating func number() -> CGFloat {
            skip()
            var text = "", seenDot = false, seenExponent = false
            while index < chars.count {
                let c = chars[index]
                if c == "-" || c == "+" {
                    guard text.isEmpty || text.last == "e" || text.last == "E" else { break }
                } else if c == "." {
                    guard !seenDot, !seenExponent else { break }
                    seenDot = true
                } else if c == "e" || c == "E" {
                    guard !seenExponent, !text.isEmpty else { break }
                    seenExponent = true
                } else if !c.isNumber {
                    break
                }
                text.append(c)
                index += 1
            }
            return CGFloat(Double(text) ?? 0)
        }
    }
}
