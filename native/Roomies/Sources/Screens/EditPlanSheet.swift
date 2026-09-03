import SwiftUI

struct EditPlanSheet: View {
    @EnvironmentObject private var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    let plan: PlanEvent

    @State private var title: String
    @State private var shareTitle: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var invitees: Set<String>

    init(plan: PlanEvent) {
        self.plan = plan
        _title = State(initialValue: plan.title ?? "")
        _shareTitle = State(initialValue: plan.title != nil)
        _start = State(initialValue: plan.start)
        _end = State(initialValue: plan.end)
        _invitees = State(initialValue: Set(plan.invitees))
    }

    private var people: [String] { store.state.people }
    private var canSave: Bool { !title.trimmed.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Edit plan", canSave: canSave, onCancel: { dismiss() }, onSave: save)

            ScrollView {
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("What's happening?", text: $title)
                            .textFieldStyle(RoomiesTextFieldStyle())

                        DatePicker("From", selection: $start, displayedComponents: [.date, .hourAndMinute])
                            .font(Fonts.sans(13)).foregroundColor(Theme.textSoft)
                        DatePicker("Until", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                            .font(Fonts.sans(13)).foregroundColor(Theme.textSoft)

                        Toggle(isOn: $shareTitle) {
                            Text(shareTitle ? "Flatmates see the name" : "Flatmates only see that you're away")
                                .font(Fonts.sans(12)).foregroundColor(Theme.textFaint)
                        }
                        .tint(Theme.teal)

                        if people.count > 1 {
                            Text("Invited").font(Fonts.sans(12)).foregroundColor(Color(hex: "666666"))
                            FlowLayout(spacing: 6) {
                                ForEach(people.filter { $0 != plan.owner }, id: \.self) { person in
                                    let on = invitees.contains(person)
                                    Button {
                                        if on { invitees.remove(person) } else { invitees.insert(person) }
                                    } label: {
                                        Text(person)
                                            .font(Fonts.sans(12))
                                            .foregroundColor(on ? Theme.personColor(person, people: people) : Color(hex: "888888"))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(on ? Theme.personColor(person, people: people).opacity(0.15) : Color.clear)
                                            .overlay(Capsule().stroke(on ? Theme.personColor(person, people: people).opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
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
        store.updatePlan(id: plan.id, title: shareTitle ? title.trimmed : nil, start: start, end: end, invitees: Array(invitees))
        dismiss()
    }
}
