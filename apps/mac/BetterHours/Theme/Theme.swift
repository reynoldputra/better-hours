import BetterHoursCore
import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 40
}

enum Radius {
    static let block: CGFloat = 4
    static let control: CGFloat = 6
    static let panel: CGFloat = 10
}

enum Metrics {
    static let controlHeight: CGFloat = 32
    static let hourHeight: CGFloat = 56
    static let minBlockHeight: CGFloat = 14
    static let gutterWidth: CGFloat = 56
    static let dayHeaderHeight: CGFloat = 48
}

enum Theme {
    static let background = Color("Background")
    static let surface = Color("Surface")
    static let sunken = Color("Sunken")
    static let line = Color("Line")
    static let text = Color("Text")
    static let muted = Color("Muted")
    static let accent = Color("Accent")
    static let onAccent = Color("OnAccent")
    static let accentSoft = Color("AccentSoft")
    static let accentText = Color("AccentText")
    static let danger = Color("Danger")
    static let strong = Color("Strong")
    static let onStrong = Color("OnStrong")
    static let shadow = Color("Shadow")
}

enum Fonts {
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let bodySemibold = Font.system(size: 13, weight: .semibold)
    static let heading = Font.system(size: 15, weight: .semibold)
    static let blockTitle = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let mono = Font.system(size: 11, design: .monospaced)
    static let monoMedium = Font.system(size: 13, weight: .medium, design: .monospaced)
}

extension PaletteColor {
    private var assetName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var fill: Color { Color("Project\(assetName)Fill") }
    var ink: Color { Color("Project\(assetName)Ink") }
}
