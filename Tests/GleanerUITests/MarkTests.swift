import CoreGraphics
import SwiftUI
import Testing
@testable import GleanerUI

@Suite struct MarkTests {
    /// Every mark draws something, inside its own grid: a path copied in wrong shows here, not as
    /// a blank or a hang the first time the window draws it.
    @Test func everyMarkDrawsInsideItsGrid() {
        for glyph in Glyph.allCases {
            let spec = glyph.spec
            let bounds = spec.elements.map(\.path.boundingRect).reduce(CGRect.null) { $0.union($1) }
            #expect(!bounds.isEmpty, "\(glyph)")
            #expect(spec.viewBox.insetBy(dx: -0.01, dy: -0.01).contains(bounds), "\(glyph): \(bounds)")
        }
        for path in [AgentMark.claudeCode, AgentMark.codex, AgentMark.codexTile] + ModelVendor.allCases.flatMap(\.paths) {
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

    /// A model is matched to its vendor by its family, through a gateway's reference and its
    /// suffixes; a model matched to none has no vendor, never a guessed one.
    @Test func aModelIsMatchedToItsVendorByItsFamily() {
        #expect(ModelVendor.of(model: "claude-fable-5") == .claude)
        #expect(ModelVendor.of(model: "gpt-5-codex") == .openai)
        #expect(ModelVendor.of(model: "o3") == .openai)
        #expect(ModelVendor.of(model: "o3-mini") == .openai)
        #expect(ModelVendor.of(model: "deepseek/deepseek-chat") == .deepseek)
        #expect(ModelVendor.of(model: "moonshot/kimi-k2.5") == .kimi)
        #expect(ModelVendor.of(model: "glm-5.2") == .zhipu)
        #expect(ModelVendor.of(model: "deepseek-v4-flash[1m]") == .deepseek)
        #expect(ModelVendor.of(model: "o30-lab") == nil)
        #expect(ModelVendor.of(model: "local-llama") == nil)
        #expect(ModelVendor.of(model: nil) == nil)
    }
}
