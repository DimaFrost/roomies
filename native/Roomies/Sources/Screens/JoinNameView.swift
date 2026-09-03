import SwiftUI

struct JoinNameView: View {
    @EnvironmentObject private var store: HouseholdStore
    @State private var name = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var leaving = false

    var canSubmit: Bool { !name.trimmed.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    (Text("at our ").foregroundColor(Theme.text) + Text("place").foregroundColor(Theme.coral))
                        .font(Fonts.display(40, weight: .black))
                    if let flat = store.flat {
                        Text(store.isOwner ? "finish setting up \(flat.name)" : "you're joining \(flat.name)")
                            .font(Fonts.mono(12))
                            .foregroundColor(Color(hex: "666666"))
                    }
                }
                .padding(.top, 40)

                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Your name")
                        TextField("What your flatmates call you", text: $name)
                            .textFieldStyle(RoomiesTextFieldStyle())

                        if let errorText {
                            Text(errorText)
                                .font(Fonts.sans(13))
                                .foregroundColor(Theme.coral)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Text(busy ? "Saving…" : (store.isOwner ? "Continue" : "Join Flat"))
                                .font(Fonts.display(15))
                                .foregroundColor(canSubmit && !busy ? .white : Color(hex: "444444"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(canSubmit && !busy ? Theme.coral : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!canSubmit || busy)
                        .padding(.top, 4)
                    }
                }

                if !store.isOwner {
                    Button {
                        Task { await abort() }
                    } label: {
                        Text(leaving ? "Leaving…" : "Not the right flat? Start over")
                            .font(Fonts.sans(13))
                            .foregroundColor(Theme.textFaint)
                    }
                    .disabled(leaving || busy)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
    }

    private func abort() async {
        guard !leaving else { return }
        leaving = true
        errorText = await store.leaveHousehold()
        leaving = false
    }

    private func submit() async {
        guard canSubmit, !busy else { return }
        busy = true
        errorText = nil
        errorText = await store.joinHousehold(memberName: name.trimmed)
        busy = false
    }
}
