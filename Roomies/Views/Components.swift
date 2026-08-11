import SwiftUI

struct AvatarView: View {
    let name: String
    let people: [String]
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(Theme.personColor(name, in: people))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
            }
    }

    private var initial: String {
        guard let first = name.first else { return "?" }
        return String(first).uppercased()
    }
}

struct CardView<Content: View>: View {
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 14
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.cardBorder)
        }
    }
}

struct SectionLabel: View {
    private let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.mono(11))
            .tracking(1)
            .foregroundStyle(Theme.textMuted)
    }
}

struct TagView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.mono(11))
            .foregroundStyle(Theme.textTag)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.chipBorder)
            }
    }
}

/// Pill toggle used for categories and quick asks.
struct ChipButton: View {
    let label: String
    let isActive: Bool
    var activeColor: Color = Theme.coral
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.sans(12))
                .foregroundStyle(isActive ? activeColor : Theme.textDim)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .fill(isActive ? activeColor.opacity(0.15) : .clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .strokeBorder(isActive ? activeColor.opacity(0.6) : Color.white.opacity(0.1))
                }
        }
        .buttonStyle(.plain)
    }
}

/// Row of selectable flatmates, coloured per person.
struct PersonPicker: View {
    let options: [String]
    let people: [String]
    let selected: String?
    var avatarSize: CGFloat = 28
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { person in
                let isActive = selected == person
                let color = Theme.personColor(person, in: people)

                Button {
                    onSelect(person)
                } label: {
                    VStack(spacing: 6) {
                        AvatarView(name: person, people: people, size: avatarSize)
                        Text(person)
                            .font(.sans(12, weight: .medium))
                            .foregroundStyle(isActive ? color : Theme.textMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(isActive ? color.opacity(0.13) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(isActive ? color.opacity(0.4) : Theme.cardBorder)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Full-width accent button used for the primary action on each screen.
struct PrimaryButton: View {
    let title: String
    var color: Color = Theme.coral
    var titleColor: Color = .white
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.display(15))
                .tracking(0.3)
                .foregroundStyle(isEnabled ? titleColor : Theme.textGhost)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isEnabled ? color : Color.white.opacity(0.06))
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// Text field styled to match the dark cards.
struct FieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.sans(14))
            .foregroundStyle(Theme.textSoft)
            .tint(Theme.coral)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.cardBorder)
            }
    }
}

extension View {
    func roomiesField() -> some View { modifier(FieldBackground()) }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = []
        var current: [(index: Int, size: CGSize)] = []
        var x: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.isEmpty ? size.width : size.width + spacing
            if x + needed > maxWidth, !current.isEmpty {
                rows.append(current)
                current = [(index, size)]
                x = size.width
            } else {
                current.append((index, size))
                x += needed
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)

        let height = rows.reduce(CGFloat.zero) { $0 + ($1.map(\.size.height).max() ?? 0) }
            + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map { row in
            row.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
        }.max() ?? 0

        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map(\.size.height).max() ?? 0
            for item in row {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += rowHeight + spacing
        }
    }
}
