import CoreGraphics
import SwiftUI
import Testing
@testable import Gleaner

@Suite struct GlyphTests {
    /// Every mark draws something, inside its own grid: a path copied in wrong shows here, not as
    /// a blank or a hang the first time the window draws it.
    @Test func everyMarkDrawsInsideItsGrid() {
        for glyph in Glyph.allCases {
            let spec = glyph.spec
            let bounds = spec.elements.map(\.path.boundingRect).reduce(CGRect.null) { $0.union($1) }
            #expect(!bounds.isEmpty, "\(glyph)")
            #expect(spec.viewBox.insetBy(dx: -0.01, dy: -0.01).contains(bounds), "\(glyph): \(bounds)")
        }
        for path in [ProviderMark.claudeCode, ProviderMark.codex, ProviderMark.codexTile] {
            #expect(!path.boundingRect.isEmpty)
            #expect(CGRect(x: 0, y: 0, width: 24, height: 24).insetBy(dx: -0.01, dy: -0.01).contains(path.boundingRect))
        }
    }

    @Test func pathDataTheParserCantFollowEndsTheShape() {
        // Numbers after a close can't repeat it: the shape stops there.
        let closed = SVGPath.parse("M0 0h5v5z 1 1")
        #expect(closed.boundingRect == CGRect(x: 0, y: 0, width: 5, height: 5))
        // Tabs and line breaks separate numbers as spaces do.
        #expect(SVGPath.parse("M0 0\tL5\n5").boundingRect == CGRect(x: 0, y: 0, width: 5, height: 5))
        // Arc flags written without a separator.
        #expect(!SVGPath.parse("M2 2a2 2 0 014 0").boundingRect.isEmpty)
    }
}
