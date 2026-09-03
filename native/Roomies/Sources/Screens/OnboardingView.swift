import SwiftUI

private enum OnboardingMode { case create, join }

struct OnboardingView: View {
    @State private var mode: OnboardingMode = .create

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    (Text("at our ").foregroundColor(Theme.text) + Text("place").foregroundColor(Theme.coral))
                        .font(Fonts.display(40, weight: .black))
                    Text("your flat, one app")
                        .font(Fonts.mono(12))
                        .foregroundColor(Color(hex: "666666"))
                }
                .padding(.top, 40)

                HStack(spacing: 4) {
                    modeButton("Start a flat", .create)
                    modeButton("Join a flat", .join)
                }
                .padding(4)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if mode == .create {
                    CreateFlatView()
                } else {
                    JoinFlatView()
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
    }

    private func modeButton(_ label: String, _ value: OnboardingMode) -> some View {
        Button { mode = value } label: {
            Text(label)
                .font(Fonts.sans(13, weight: .medium))
                .foregroundColor(mode == value ? .white : Theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(mode == value ? Color.white.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
}
