import SwiftUI

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
                // Numbers can't repeat a close: stop rather than close forever.
                if tokens.hasNumber { return path }
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
            while index < chars.count, chars[index] == "," || chars[index].isWhitespace { index += 1 }
        }

        /// True once every character was read.
        var isAtEnd: Bool {
            var probe = self
            probe.skip()
            return probe.index >= probe.chars.count
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
