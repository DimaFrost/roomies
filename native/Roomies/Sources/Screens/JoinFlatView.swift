import SwiftUI

struct JoinFlatView: View {
    @EnvironmentObject private var store: HouseholdStore
    @State private var pastedLink = ""
    @State private var busy = false
    @State private var errorText: String?

    private var canSubmit: Bool { !pastedLink.trimmed.isEmpty }

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Invite link")
                TextField("Paste the link your flatmate sent you", text: $pastedLink)
                    .textFieldStyle(RoomiesTextFieldStyle())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if let errorText {
                    Text(errorText)
                        .font(Fonts.sans(13))
                        .foregroundColor(Theme.coral)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Text(busy ? "Joining…" : "Join Flat")
                        .font(Fonts.display(15))
                        .foregroundColor(canSubmit && !busy ? .white : Color(hex: "444444"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(canSubmit && !busy ? Theme.coral : Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canSubmit || busy)
            }
        }
    }

    private func submit() async {
        guard canSubmit, !busy else { return }
        busy = true
        errorText = nil
        errorText = await store.acceptInvite(pastedText: pastedLink)
        busy = false
    }
}
