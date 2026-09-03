import SwiftUI

struct TagView: View {
    var label: String

    var body: some View {
        Text(label)
            .font(Fonts.mono(11))
            .foregroundColor(Color(hex: "aaaaaa"))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.chipBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
