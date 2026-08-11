import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Theme {
    static let bg = Color(hex: 0x0F0F1A)
    static let panel = Color(hex: 0x141424).opacity(0.96)
    static let card = Color.white.opacity(0.04)
    static let cardBorder = Color.white.opacity(0.08)
    static let chipBorder = Color.white.opacity(0.12)

    static let text = Color(hex: 0xF0F0F0)
    static let textSoft = Color(hex: 0xDDDDDD)
    static let textTag = Color(hex: 0xAAAAAA)
    static let textDim = Color(hex: 0x888888)
    static let textMuted = Color(hex: 0x666666)
    static let textFaint = Color(hex: 0x555555)
    static let textGhost = Color(hex: 0x444444)

    static let coral = Color(hex: 0xFF6B6B)
    static let teal = Color(hex: 0x4ECDC4)
    static let yellow = Color(hex: 0xFFE66D)

    /// Ink used on top of the bright accent colours.
    static let onAccent = Color(hex: 0x1A1A2E)

    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 10
        static let pill: CGFloat = 8
    }

    /// Stable palette for flatmates, assigned by join order.
    private static let memberPalette: [Color] = [
        Color(hex: 0xFF6B6B),
        Color(hex: 0x4ECDC4),
        Color(hex: 0xFFE66D),
        Color(hex: 0xA78BFA),
        Color(hex: 0x6BCB77),
        Color(hex: 0xF49AC2),
    ]

    static func personColor(_ name: String, in people: [String]) -> Color {
        let index = people.firstIndex(of: name) ?? people.count
        return memberPalette[index % memberPalette.count]
    }
}

// The original used DM Sans / DM Mono / Syne from Google Fonts. On iOS the system
// faces cover the same roles without bundling files, and they bring Dynamic Type
// and correct optical sizing along for free.
extension Font {
    /// Wordmark and primary buttons.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Numerals and small uppercase labels, where alignment matters.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
