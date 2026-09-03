import SwiftUI

struct EditExpenseSheet: View {
    @EnvironmentObject private var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    let expense: Expense

    @State private var amountText: String
    @State private var description: String
    @State private var category: String
    @State private var split: SplitType
    @State private var forPerson: String?
    @State private var date: Date

    init(expense: Expense) {
        self.expense = expense
        _amountText = State(initialValue: String(format: "%.2f", expense.amount))
        _description = State(initialValue: expense.description)
        _category = State(initialValue: expense.category)
        _split = State(initialValue: expense.split)
        _forPerson = State(initialValue: expense.forPerson)
        _date = State(initialValue: expense.createdAt)
    }

    private var people: [String] { store.state.people }
    private var parsedAmount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }
    private var canSave: Bool {
        guard let amount = parsedAmount, amount > 0 else { return false }
        guard !description.trimmed.isEmpty else { return false }
        if split == .full && forPerson == nil { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Edit expense", canSave: canSave, onCancel: { dismiss() }, onSave: save)

            ScrollView {
                VStack(spacing: 12) {
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Text("€").font(Fonts.mono(22)).foregroundColor(Color(hex: "666666"))
                                TextField("0.00", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .font(Fonts.display(32, weight: .black))
                                    .foregroundColor(.white)
                            }
                            TextField("What was this for?", text: $description)
                                .textFieldStyle(RoomiesTextFieldStyle())
                            DatePicker("When", selection: $date, in: ...Date(), displayedComponents: .date)
                                .font(Fonts.sans(13))
                                .foregroundColor(Theme.textSoft)
                                .tint(Theme.coral)
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Category")
                            FlowLayout(spacing: 6) {
                                ForEach(CATEGORIES, id: \.self) { cat in
                                    let active = category == cat
                                    Button { category = cat } label: {
                                        Text(cat)
                                            .font(Fonts.sans(12))
                                            .foregroundColor(active ? Theme.coral : Color(hex: "888888"))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(active ? Theme.coral.opacity(0.15) : Color.clear)
                                            .overlay(Capsule().stroke(active ? Theme.coral.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    if people.count > 1 {
                        CardView {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel("Split")
                                HStack(spacing: 8) {
                                    splitOption(title: "Split evenly", color: Theme.teal, active: split == .even) { split = .even }
                                    splitOption(title: "Full amount", color: Theme.yellow, active: split == .full) { split = .full }
                                }
                                if split == .full {
                                    Text("Who owes \(expense.paidBy)?").font(Fonts.sans(12)).foregroundColor(Color(hex: "666666"))
                                    PersonPickerView(options: people.filter { $0 != expense.paidBy }, people: people, selected: forPerson, onSelect: { forPerson = $0 }, avatarSize: 26)
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

    private func splitOption(title: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.sans(13, weight: .medium))
                .foregroundColor(active ? color : Color(hex: "666666"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(active ? color.opacity(0.12) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(active ? color.opacity(0.5) : Theme.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
    }

    private func save() {
        guard canSave, let amount = parsedAmount else { return }
        store.updateExpense(id: expense.id, description: description.trimmed, amount: amount, category: category, split: split, forPerson: split == .full ? forPerson : nil, date: date)
        dismiss()
    }
}

/// Shared Cancel/title/Save bar for edit sheets — the app has no navigation bars elsewhere.
struct SheetHeader: View {
    var title: String
    var canSave: Bool
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(Fonts.sans(14))
                .foregroundColor(Color(hex: "888888"))
            Spacer()
            Text(title).font(Fonts.display(15)).foregroundColor(Theme.text)
            Spacer()
            Button("Save", action: onSave)
                .font(Fonts.sans(14, weight: .bold))
                .foregroundColor(canSave ? Theme.coral : Theme.textGhost)
                .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.panel)
        .overlay(Rectangle().fill(Theme.cardBorder).frame(height: 1), alignment: .bottom)
    }
}
