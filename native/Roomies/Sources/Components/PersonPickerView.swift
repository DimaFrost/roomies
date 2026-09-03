import SwiftUI

/// Row of selectable flatmate buttons, colored per person.
struct PersonPickerView: View {
    var options: [String]
    var people: [String]
    var selected: String?
    var onSelect: (String) -> Void
    var avatarSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { person in
                let active = selected == person
                let color = Theme.personColor(person, people: people)
                Button {
                    onSelect(person)
                } label: {
                    VStack(spacing: 6) {
                        AvatarView(name: person, people: people, size: avatarSize)
                        Text(person)
                            .font(Fonts.sans(12, weight: .medium))
                            .foregroundColor(active ? color : Color(hex: "666666"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background(active ? color.opacity(0.13) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(active ? color.opacity(0.4) : Theme.cardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
