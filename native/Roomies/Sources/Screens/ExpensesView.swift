import SwiftUI

let CATEGORIES = ["🍕 Food", "🛒 Groceries", "🧹 Cleaning", "⚡ Utilities", "🎉 Fun", "🚗 Transport", "🏠 Rent", "💊 Other"]

private enum ExpenseSubTab { case add, history }

struct ExpensesView: View {
    @EnvironmentObject private var store: HouseholdStore
    @State private var subTab: ExpenseSubTab = .add
    @State private var amountText = ""
    @State private var description = ""
    @State private var category = CATEGORIES[0]
    @State private var paidBy: String?
    @State private var split: SplitType = .even
    @State private var forPerson: String?
    @State private var added = false
    @State private var deleteTarget: Expense?
    @State private var editTarget: Expense?
    @State private var spentOn = Date()

    private var people: [String] { store.state.people }
    private var expenses: [Expense] { store.state.expenses }
    private var balances: [String: Double] { computeBalances(people: people, expenses: expenses) }
    private var settlements: [Settlement] { computeSettlements(balances: balances) }
    private var hasOthers: Bool { people.count > 1 }

    private var resolvedPaidBy: String { paidBy ?? store.myName ?? people.first ?? "" }
    private var parsedAmount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }
    private var canAdd: Bool {
        guard let amount = parsedAmount, amount > 0 else { return false }
        guard !description.trimmed.isEmpty else { return false }
        if split == .full && forPerson == nil { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 12) {
            subTabBar

            if subTab == .add {
                ScrollView { addForm.padding(.bottom, 16) }
            } else {
                historyList
            }

            settlePanel
        }
        .onAppear {
            if paidBy == nil { paidBy = store.myName ?? people.first }
            if forPerson == nil { forPerson = people.first { $0 != resolvedPaidBy } }
        }
        .alert("Delete expense?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let t = deleteTarget { store.deleteExpense(id: t.id) }
                deleteTarget = nil
            }
        } message: {
            if let t = deleteTarget {
                Text("\"\(t.description)\" · €\(String(format: "%.2f", t.amount))")
            }
        }
        .sheet(item: $editTarget) { expense in
            EditExpenseSheet(expense: expense)
        }
    }

    private var subTabBar: some View {
        HStack(spacing: 4) {
            subTabButton("Add Expense", .add)
            subTabButton(expenses.isEmpty ? "History" : "History (\(expenses.count))", .history)
        }
        .padding(4)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func subTabButton(_ label: String, _ value: ExpenseSubTab) -> some View {
        Button { subTab = value } label: {
            Text(label)
                .font(Fonts.sans(13, weight: .medium))
                .foregroundColor(subTab == value ? .white : Theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(subTab == value ? Color.white.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    private var addForm: some View {
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
                    DatePicker("When", selection: $spentOn, in: ...Date(), displayedComponents: .date)
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
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(active ? Theme.coral.opacity(0.15) : Color.clear)
                                    .overlay(Capsule().stroke(active ? Theme.coral.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            CardView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Paid by")
                    PersonPickerView(options: people, people: people, selected: resolvedPaidBy) { p in
                        paidBy = p
                        if forPerson == p { forPerson = people.first { $0 != p } }
                    }
                }
            }

            CardView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Split")
                    HStack(spacing: 8) {
                        splitOption(emoji: "⚖️", title: "Split evenly", subtitle: "everyone shares", color: Theme.teal, active: split == .even) { split = .even }
                        if hasOthers {
                            splitOption(emoji: "💸", title: "Full amount", subtitle: "one person owes", color: Theme.yellow, active: split == .full) { split = .full }
                        }
                    }
                    if split == .full {
                        Text("Who owes \(resolvedPaidBy)?")
                            .font(Fonts.sans(12))
                            .foregroundColor(Color(hex: "666666"))
                        PersonPickerView(options: people.filter { $0 != resolvedPaidBy }, people: people, selected: forPerson, onSelect: { forPerson = $0 }, avatarSize: 26)
                    }
                }
            }

            Button {
                handleAdd()
            } label: {
                Text(added ? "✓ Added!" : "Log Expense")
                    .font(Fonts.display(15))
                    .foregroundColor(canAdd ? .white : Color(hex: "444444"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canAdd ? Theme.coral : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canAdd)
        }
    }

    private func splitOption(emoji: String, title: String, subtitle: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(emoji).font(.system(size: 18))
                Text(title).font(Fonts.sans(13, weight: .medium)).foregroundColor(active ? color : Color(hex: "666666"))
                Text(subtitle).font(Fonts.sans(10)).foregroundColor(active ? color.opacity(0.7) : Color(hex: "555555"))
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(active ? color.opacity(0.12) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? color.opacity(0.5) : Theme.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func handleAdd() {
        guard canAdd, let amount = parsedAmount else { return }
        store.addExpense(description: description.trimmed, amount: amount, category: category, paidBy: resolvedPaidBy, split: split, forPerson: split == .full ? forPerson : nil, date: spentOn)
        amountText = ""
        description = ""
        spentOn = Date()
        added = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { added = false }
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if expenses.isEmpty {
                    Text("No expenses yet")
                        .font(Fonts.sans(14))
                        .foregroundColor(Theme.textGhost)
                        .padding(.vertical, 40)
                }
                ForEach(expenses) { exp in
                    let editable = exp.paidBy == store.myName && exp.category != SETTLE_UP_CATEGORY
                    CardView {
                        HStack(spacing: 12) {
                            AvatarView(name: exp.paidBy, people: people)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exp.description).font(Fonts.sans(14, weight: .medium)).foregroundColor(Theme.text).lineLimit(1)
                                HStack(spacing: 6) {
                                    TagView(label: exp.category)
                                    TagView(label: exp.split == .full && exp.forPerson != nil ? "\(exp.forPerson!) owes all" : "split evenly")
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("€\(String(format: "%.2f", exp.amount))")
                                    .font(Fonts.mono(15, weight: .medium))
                                    .foregroundColor(Theme.personColor(exp.paidBy, people: people))
                                Text(editable ? "\(timeAgo(exp.createdAt)) · edit" : timeAgo(exp.createdAt))
                                    .font(Fonts.sans(10)).foregroundColor(Theme.textFaint)
                            }
                            // Only the person who paid can remove it — everyone else's balance
                            // depends on the entry staying put.
                            if exp.paidBy == store.myName {
                                Button {
                                    deleteTarget = exp
                                } label: {
                                    Text("✕")
                                        .font(Fonts.sans(13))
                                        .foregroundColor(Theme.textFaint)
                                        .padding(.leading, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if editable { editTarget = exp } }
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var settlePanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("WHO OWES WHAT").font(Fonts.mono(10)).foregroundColor(Theme.textFaint).tracking(1)
                Spacer()
                Text(settlements.isEmpty ? "all settled 🎉" : "\(settlements.count) transfer\(settlements.count > 1 ? "s" : "")")
                    .font(Fonts.mono(10)).foregroundColor(Theme.textFaint)
            }
            if settlements.isEmpty {
                Text("Everyone's square ✓").font(Fonts.sans(14, weight: .bold)).foregroundColor(Theme.teal).padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(settlements) { s in
                        HStack(spacing: 10) {
                            AvatarView(name: s.from, people: people, size: 28)
                            HStack(spacing: 6) {
                                Text(s.from).font(Fonts.sans(13, weight: .medium)).foregroundColor(Theme.textSoft)
                                Text("owes").font(Fonts.sans(12)).foregroundColor(Theme.textGhost)
                                Text(s.to).font(Fonts.sans(13, weight: .medium)).foregroundColor(Theme.personColor(s.to, people: people))
                            }
                            Spacer()
                            Text("€\(String(format: "%.2f", s.amount))").font(Fonts.mono(15, weight: .medium)).foregroundColor(Theme.coral)
                            Button {
                                store.recordSettlement(from: s.from, to: s.to, amount: s.amount)
                            } label: {
                                Text("Settle")
                                    .font(Fonts.sans(11, weight: .medium))
                                    .foregroundColor(Theme.teal)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .overlay(Capsule().stroke(Theme.teal.opacity(0.4), lineWidth: 1))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
