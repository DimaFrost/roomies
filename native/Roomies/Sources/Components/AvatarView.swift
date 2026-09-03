import SwiftUI

struct AvatarView: View {
    var name: String
    var people: [String]
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(Theme.personColor(name, people: people))
            .frame(width: size, height: size)
            .overlay(
                Text(name.prefix(1).uppercased())
                    .font(Fonts.sans(size * 0.42, weight: .bold))
                    .foregroundColor(Color(hex: "1a1a2e"))
            )
    }
}
