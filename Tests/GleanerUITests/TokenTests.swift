import SwiftUI
import Testing
@testable import GleanerUI

@Suite struct TokenTests {
    /// The kit's durations the window uses, and none at all under Reduce Motion.
    @Test func motionIsTheKitsDurationsAndOffUnderReduceMotion() {
        #expect(Motion.allCases.map(\.duration) == [0.12, 0.2])
        for motion in Motion.allCases {
            #expect(motion(true) == nil)
            #expect(motion(false) != nil)
        }
    }

    /// Under Increase Contrast an ink moves away from its background: darker on light, lighter on
    /// dark, and never the other way. A wash deepens a little in light and keeps its value in dark.
    @Test func increaseContrastOnlyStrengthensInks() {
        func luminance(_ rgb: Palette.RGB) -> Double { 0.2126 * rgb.0 + 0.7152 * rgb.1 + 0.0722 * rgb.2 }
        let inks: [Palette.Tone] = [.attention, .lost, .awaiting, .change]
        for tone in inks {
            let v = tone.values
            #expect(luminance(v.contrast) < luminance(v.light), "\(tone)")
            #expect(luminance(v.darkContrast) >= luminance(v.dark), "\(tone)")
        }
        for tone in [Palette.Tone.attentionFill, .lostFill, .awaitingWash] {
            let v = tone.values
            #expect(luminance(v.contrast) < luminance(v.light), "\(tone)")
            #expect(luminance(v.light) - luminance(v.contrast) < 0.1, "\(tone)")
            #expect(v.darkContrast == v.dark, "\(tone)")
        }
    }
}
