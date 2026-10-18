import SwiftUI

/// Each agent by its own mark, in place of its name where the name would repeat on every row.
/// The name stays in the help tag and for VoiceOver.
///
/// The drawings are lobe-icons' `claudecode` and `codex` (github.com/lobehub/lobe-icons, MIT), the
/// set Magpie also bundles for agents and model vendors. The marks belong to Anthropic and OpenAI;
/// Gleaner uses them only to say which agent's logs a delivery came from.
public struct AgentMark: View {
    /// The agents Gleaner reads, by the names their makers give them.
    public enum Agent: CaseIterable, Sendable {
        case claudeCode
        case codex

        public var name: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            }
        }
    }

    public var agent: Agent
    public var size: CGFloat
    /// The agent's own colors, for where it is named on its own; otherwise one ink, as list marks are.
    public var color: Bool

    public init(_ agent: Agent, size: CGFloat = 14, color: Bool = false) {
        self.agent = agent
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 24
            context.scaleBy(x: scale, y: scale)
            switch agent {
            case .claudeCode:
                context.fill(Self.claudeCode, with: color ? .color(Self.claudeOrange) : .foreground, style: FillStyle(eoFill: true))
            case .codex:
                if color {
                    context.fill(Self.codexTile, with: .color(.white))
                    context.stroke(Self.codexTile, with: .color(.black.opacity(0.08)), lineWidth: 0.5 / scale)
                    context.fill(Self.codex, with: .linearGradient(Self.codexGradient, startPoint: CGPoint(x: 12, y: 3), endPoint: CGPoint(x: 12, y: 21)),
                                 style: FillStyle(eoFill: true))
                } else {
                    context.fill(Self.codex, with: .foreground, style: FillStyle(eoFill: true))
                }
            }
        }
        .frame(width: size, height: size)
        .help(agent.name)
        .accessibilityElement()
        .accessibilityLabel(agent.name)
    }

    static let claudeOrange = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    static let codexGradient = Gradient(stops: [
        .init(color: Color(red: 0xB1 / 255, green: 0xA7 / 255, blue: 1), location: 0),
        .init(color: Color(red: 0x7A / 255, green: 0x9D / 255, blue: 1), location: 0.5),
        .init(color: Color(red: 0x39 / 255, green: 0x41 / 255, blue: 1), location: 1),
    ])

    static let claudeCode = SVGPath.parse(
        "M20.998 10.949H24v3.102h-3v3.028h-1.487V20H18v-2.921h-1.487V20H15v-2.921H9V20H7.488v-2.921H6V20H4.487v-2.921H3V14.05H0V10.95h3V5h17.998v5.949zM6 10.949h1.488V8.102H6v2.847zm10.51 0H18V8.102h-1.49v2.847z")

    static let codexTile = SVGPath.parse(
        "M19.503 0H4.496A4.496 4.496 0 000 4.496v15.007A4.496 4.496 0 004.496 24h15.007A4.496 4.496 0 0024 19.503V4.496A4.496 4.496 0 0019.503 0z")

    static let codex = SVGPath.parse(
        "M9.064 3.344a4.578 4.578 0 012.285-.312c1 .115 1.891.54 2.673 1.275.01.01.024.017.037.021a.09.09 0 00.043 0 4.55 4.55 0 013.046.275l.047.022.116.057a4.581 4.581 0 012.188 2.399c.209.51.313 1.041.315 1.595a4.24 4.24 0 01-.134 1.223.123.123 0 00.03.115c.594.607.988 1.33 1.183 2.17.289 1.425-.007 2.71-.887 3.854l-.136.166a4.548 4.548 0 01-2.201 1.388.123.123 0 00-.081.076c-.191.551-.383 1.023-.74 1.494-.9 1.187-2.222 1.846-3.711 1.838-1.187-.006-2.239-.44-3.157-1.302a.107.107 0 00-.105-.024c-.388.125-.78.143-1.204.138a4.441 4.441 0 01-1.945-.466 4.544 4.544 0 01-1.61-1.335c-.152-.202-.303-.392-.414-.617a5.81 5.81 0 01-.37-.961 4.582 4.582 0 01-.014-2.298.124.124 0 00.006-.056.085.085 0 00-.027-.048 4.467 4.467 0 01-1.034-1.651 3.896 3.896 0 01-.251-1.192 5.189 5.189 0 01.141-1.6c.337-1.112.982-1.985 1.933-2.618.212-.141.413-.251.601-.33.215-.089.43-.164.646-.227a.098.098 0 00.065-.066 4.51 4.51 0 01.829-1.615 4.535 4.535 0 011.837-1.388zm3.482 10.565a.637.637 0 000 1.272h3.636a.637.637 0 100-1.272h-3.636zM8.462 9.23a.637.637 0 00-1.106.631l1.272 2.224-1.266 2.136a.636.636 0 101.095.649l1.454-2.455a.636.636 0 00.005-.64L8.462 9.23z")
}
