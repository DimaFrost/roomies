import SwiftUI

struct EditAskSheet: View {
    @EnvironmentObject private var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    let ask: Ask

    @State private var title: String
    @State private var note: String
    @State private var target: String

    private static let anyone = "anyone"

    init(ask: Ask) {
        self.ask = ask
        _title = State(initialValue: ask.title)
        _note = State(initialValue: ask.note ?? "")
        _target = State(initialValue: ask.assignedTo ?? Self.anyone)
    }

    private var people: [String] { store.state.people }
    private var canSave: Bool { !title.trimmed.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Edit ask", canSave: canSave, onCancel: { dismiss() }, onSave: save)

            ScrollView {
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("What do you need?", text: $title)
                            .textFieldStyle(RoomiesTextFieldStyle())
                        TextField("Details (optional)", text: $note)
                            .textFieldStyle(RoomiesTextFieldStyle())

                        Text("Who should do it?").font(Fonts.sans(12)).foregroundColor(Color(hex: "666666"))
                        HStack(spacing: 8) {
                            Button { target = Self.anyone } label: {
                                Text("🙋 Anyone")
                                    .font(Fonts.sans(12, weight: .medium))
                                    .foregroundColor(target == Self.anyone ? Theme.yellow : Color(hex: "666666"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(target == Self.anyone ? Theme.yellow.opacity(0.1) : Color.clear)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(target == Self.anyone ? Theme.yellow.opacity(0.5) : Theme.cardBorder, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
                            }
                            .frame(maxWidth: .infinity)

                            PersonPickerView(
                                options: people.filter { $0 != ask.askedBy },
                                people: people,
                                selected: target == Self.anyone ? nil : target,
                                onSelect: { target = $0 },
                                avatarSize: 24
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func save() {
        guard canSave else { return }
        store.updateAsk(id: ask.id, title: title.trimmed, note: note.trimmed.isEmpty ? nil : note.trimmed, assignedTo: target == Self.anyone ? nil : target)
        dismiss()
    }
}
