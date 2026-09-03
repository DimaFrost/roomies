import SwiftUI

struct CreateFlatView: View {
    @EnvironmentObject private var store: HouseholdStore
    @State private var flatName = ""
    @State private var name = ""
    @State private var busy = false
    @State private var errorText: String?

    var canSubmit: Bool { !flatName.trimmed.isEmpty && !name.trimmed.isEmpty }

    var body: some View {
        VStack(spacing: 16) {
            CardView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Name your flat")
                    TextField("e.g. Sonnenallee 42", text: $flatName)
                        .textFieldStyle(RoomiesTextFieldStyle())

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
                        Text(busy ? "Setting up…" : "Create Flat")
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

            Text("You'll get an invite link to send your flatmates — they paste it in under \"Join a flat.\"")
                .font(Fonts.sans(12))
                .foregroundColor(Theme.textFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .sheet(isPresented: Binding(get: { store.pendingShare != nil }, set: { if !$0 { store.pendingShare = nil } })) {
            if let share = store.pendingShare {
                InviteLinkView(share: share)
            }
        }
    }

    private func submit() async {
        guard canSubmit, !busy else { return }
        busy = true
        errorText = nil
        errorText = await store.createHousehold(flatName: flatName.trimmed, memberName: name.trimmed)
        busy = false
    }
}

struct RoomiesTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(Fonts.sans(15))
            .foregroundColor(Theme.textSoft)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
