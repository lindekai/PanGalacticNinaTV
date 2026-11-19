import PanGalacticCore
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Design tokens of the dashboard (spec: "Visual system"). Teal is the only signal
/// colour; amber and red appear only for real warnings and faults.
enum Theme {
    static let bg = Color(hex: 0x161D21)
    static let surface = Color(hex: 0x1E272C)
    static let raised = Color(hex: 0x253036)
    static let line = Color(hex: 0x2E3A40)
    static let text = Color(hex: 0xDCE3E6)
    static let text2 = Color(hex: 0x8C9AA2)
    static let text3 = Color(hex: 0x5D6A71)
    static let accent = Color(hex: 0x34B89C)
    static let warn = Color(hex: 0xE3A23B)
    static let fault = Color(hex: 0xE0584D)
    static let focus = Color(hex: 0xF2F5F6)

    static let margin: CGFloat = 56
    static let marginVertical: CGFloat = 36
    static let imageWidth: CGFloat = 1024
    static let columnGap: CGFloat = 40
    static let moduleGap: CGFloat = 24
    static let meridianTileWidth: CGFloat = 190
    static let filterTileWidth: CGFloat = 190
    static let radius: CGFloat = 12

    static func color(for light: StatusLight) -> Color {
        switch light {
        case .normal: accent
        case .warning: warn
        case .fault: fault
        case .unknown: text3
        }
    }

    /// Guide chart lines (PHD2-like: RA blue, Dec orange).
    static let guideRA = Color(hex: 0x6CB4EE)
    static let guideDec = Color(hex: 0xE58A6F)

    /// Traffic-light colour of the total guide error; plain text when ungraded (pixels).
    static func color(for grade: RMSGrade?) -> Color {
        switch grade {
        case .good: accent
        case .fair: warn
        case .poor: fault
        case nil: text
        }
    }
}

extension Font {
    static let pgDisplay = Font.system(size: 52, weight: .semibold)
    static let pgKeyFigure = Font.system(size: 72, weight: .medium).monospacedDigit()
    static let pgKeyUnit = Font.system(size: 34, weight: .regular)
    static let pgTileValue = Font.system(size: 40, weight: .medium).monospacedDigit()
    static let pgValue = Font.system(size: 28, weight: .medium).monospacedDigit()
    static let pgLabel = Font.system(size: 22, weight: .regular)
    static let pgRubric = Font.system(size: 18, weight: .semibold)
}
