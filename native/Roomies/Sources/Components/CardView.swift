import SwiftUI

struct CardView<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

struct SectionLabel: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Fonts.mono(11))
            .foregroundColor(Color(hex: "666666"))
            .tracking(1)
    }
}
