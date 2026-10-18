import AppKit
import SwiftUI

/// Gleaner's few colors, each with one role (Praxis kit): amber means "needs your look", red means
/// gone, the change colors mark changed text and only that, and the one accent marks what waits
/// on the person. Everything else is the system's: label inks, separators, selection, materials.
///
/// Each color has a light and a dark value, and a stronger one for each under Increase Contrast;
/// washes keep their value there, and the ink and edge on them get stronger instead. The values
/// follow the window's appearance, so the contrast ones show only with the system's setting on.
public enum Palette {
    public static let attention = color(.attention)
    public static let attentionFill = color(.attentionFill)
    public static let lost = color(.lost)
    public static let lostFill = color(.lostFill)
    /// Changed text, and only that (Courtwork's change language): the line color, the solid block
    /// on new words, and the dark ink inside that block.
    public static let change = color(.change)
    public static let changeBlock = color(.changeBlock)
    public static let changeInk = color(.changeInk)
    /// Marks beside their words, in a plain color that holds on any material.
    public static let mark = Color(nsColor: .secondaryLabelColor)
    /// The one accent: what waits on the person's decision, and only that (standing.md). Links are
    /// ink with an underline, so they never borrow it.
    public static let awaiting = color(.awaiting)
    public static let awaitingWash = color(.awaitingWash)

    typealias RGB = (Double, Double, Double)

    /// Each color's values, for the window and for the gallery, which can't take the system's
    /// Increase Contrast and so draws those values from here.
    enum Tone: String, CaseIterable {
        case attention, attentionFill, lost, lostFill, awaiting, awaitingWash, change, changeBlock, changeInk

        var values: (light: RGB, dark: RGB, contrast: RGB, darkContrast: RGB) {
            switch self {
            case .attention: ((0.54, 0.29, 0.0), (1.0, 0.72, 0.36), (0.42, 0.21, 0.0), (1.0, 0.8, 0.5))
            case .attentionFill: ((1.0, 0.96, 0.92), (0.24, 0.16, 0.07), (1.0, 0.93, 0.85), (0.24, 0.16, 0.07))
            case .lost: ((0.63, 0.17, 0.17), (1.0, 0.52, 0.5), (0.5, 0.08, 0.08), (1.0, 0.66, 0.64))
            case .lostFill: ((1.0, 0.96, 0.96), (0.26, 0.1, 0.1), (1.0, 0.92, 0.92), (0.26, 0.1, 0.1))
            case .awaiting: ((0.11, 0.35, 0.81), (0.45, 0.63, 1.0), (0.07, 0.25, 0.68), (0.62, 0.76, 1.0))
            case .awaitingWash: ((0.94, 0.96, 1.0), (0.11, 0.15, 0.24), (0.9, 0.93, 1.0), (0.11, 0.15, 0.24))
            // The comparison's colors are Courtwork's, kept as adopted: dark has no stronger value.
            case .change: ((0.63, 0.24, 0.21), (0.89, 0.55, 0.51), (0.5, 0.14, 0.12), (0.89, 0.55, 0.51))
            case .changeBlock: ((0.87, 0.44, 0.41), (0.83, 0.41, 0.37), (0.75, 0.3, 0.27), (0.83, 0.41, 0.37))
            case .changeInk: ((0.09, 0.13, 0.15), (0.07, 0.09, 0.11), (0.0, 0.0, 0.0), (0.07, 0.09, 0.11))
            }
        }

        /// The value for one appearance.
        func value(dark: Bool, contrast: Bool) -> Color {
            let v = values
            let rgb = dark ? (contrast ? v.darkContrast : v.dark) : (contrast ? v.contrast : v.light)
            return Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2)
        }
    }

    private static func color(_ tone: Tone) -> Color {
        let v = tone.values
        return Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let rgb = switch match {
            case .darkAqua?: v.dark
            case .accessibilityHighContrastDarkAqua?: v.darkContrast
            case .accessibilityHighContrastAqua?: v.contrast
            default: v.light
            }
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}
