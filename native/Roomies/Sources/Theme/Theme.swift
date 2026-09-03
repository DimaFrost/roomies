import SwiftUI

extension Color {
    init(hex: String, opacity: Double = 1) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }
}

enum Theme {
    static let bg = Color(hex: "0f0f1a")
    static let panel = Color(hex: "141424", opacity: 0.96)
    static let card = Color.white.opacity(0.04)
    static let cardBorder = Color.white.opacity(0.08)
    static let chipBorder = Color.white.opacity(0.12)
    static let text = Color(hex: "f0f0f0")
    static let textSoft = Color(hex: "dddddd")
    static let textDim = Color(hex: "888888")
    static let textFaint = Color(hex: "555555")
    static let textGhost = Color(hex: "444444")
    static let coral = Color(hex: "FF6B6B")
    static let teal = Color(hex: "4ECDC4")
    static let yellow = Color(hex: "FFE66D")

    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let pillRadius: CGFloat = 8

    /// Stable palette for household members; assigned by join order.
    private static let memberPalette: [Color] = [coral, teal, yellow, Color(hex: "A78BFA"), Color(hex: "6BCB77"), Color(hex: "F49AC2")]

    static func personColor(_ name: String, people: [String]) -> Color {
        let idx = people.firstIndex(of: name) ?? people.count
        return memberPalette[idx % memberPalette.count]
    }
}

enum Fonts {
    // Placeholder: system rounded design until the DM Sans / DM Mono / Syne
    // font files are added to the project and registered in Info.plist.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
