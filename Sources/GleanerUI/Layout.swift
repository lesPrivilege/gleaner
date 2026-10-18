import SwiftUI

/// A section of a detail, titled as Finder's preview pane titles its own: a heading, then its
/// content, with room above it that sets it apart from the section before.
public struct DetailSection<Trailing: View, Content: View>: View {
    public var title: String
    public var trailing: Trailing
    public var content: Content

    public init(title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(title).font(.headline)
                Spacer(minLength: Space.s)
                trailing
            }
            Divider()
            content
        }
    }
}

extension DetailSection where Trailing == EmptyView {
    public init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// One line of facts in a `Grid`, labeled as Get Info labels them: the label right-aligned in its
/// column, the value after it.
public struct InfoRow<Value: View>: View {
    public var label: String
    public var value: Value

    public init(label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    public var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension InfoRow where Value == Text {
    public init(_ label: String, _ value: String) {
        self.init(label: label) { Text(value) }
    }
}

/// An empty or waiting state: its mark drawn large, a short title, one line, and what to do.
public struct EmptyState<Actions: View>: View {
    public var title: String
    public var glyph: Glyph
    public var description: String
    public var actions: Actions

    public init(title: String, glyph: Glyph, description: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.glyph = glyph
        self.description = description
        self.actions = actions()
    }

    public var body: some View {
        ContentUnavailableView {
            Label { Text(title) } icon: { GlyphView(glyph: glyph, size: 40).foregroundStyle(.secondary) }
        } description: {
            Text(description)
        } actions: {
            actions
        }
    }
}

extension EmptyState where Actions == EmptyView {
    public init(title: String, glyph: Glyph, description: String) {
        self.init(title: title, glyph: glyph, description: description) { EmptyView() }
    }
}

/// Lays its views out in rows, wrapping to the width it is given.
public struct FlowLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var width: CGFloat = 0, height: CGFloat = 0
        for (index, row) in rows(subviews, width: proposal.width ?? .infinity).enumerated() {
            let sizes = row.map { $0.sizeThatFits(.unspecified) }
            let rowWidth: CGFloat = sizes.reduce(0) { $0 + $1.width } + CGFloat(row.count - 1) * spacing
            width = max(width, rowWidth)
            height += (sizes.map(\.height).max() ?? 0) + (index > 0 ? spacing / 2 : 0)
        }
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + spacing / 2
        }
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]], x: CGFloat = 0
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if x > 0, x + w > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append(view)
            x += w + spacing
        }
        return rows.filter { !$0.isEmpty }
    }
}
