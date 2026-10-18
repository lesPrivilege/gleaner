import SwiftUI

/// A short line between two ends of a relation, as the kit's relation grammar draws one: solid
/// while it is in effect, dashed while it is not (`foundations/relations.md`).
public struct RelationLine: View {
    public var inEffect: Bool

    public init(inEffect: Bool) {
        self.inEffect = inEffect
    }

    public var body: some View {
        Path { $0.move(to: CGPoint(x: 0, y: 1)); $0.addLine(to: CGPoint(x: 20, y: 1)) }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: inEffect ? [] : [2, 3]))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 2)
    }
}
