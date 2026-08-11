import SwiftUI

struct SplitView: View {
    private enum SubTab: String, CaseIterable, Identifiable {
        case add
        case history

        var id: String { rawValue }
    }

    @ObservedObject var household: Household
    let people: [String]
    let expenses: [Expense]

    @EnvironmentObject private var store: HouseholdStore

    @State private var subTab: SubTab = .add
    @State private var amountText = ""
    @State private var descriptionText = ""
    @State private var category = expenseCategories[0]
    @State private var paidBy = ""
    @State private var split: SplitType = .even
    @State private var forPerson: String?
    @State private var justAdded = false
    @State private var pendingDelete: Expense?
    @State private var pendingSettlement: Settlement?

    private var balances: [String: Double] { Balances.compute(people: people, expenses: expenses) }
    private var settlements: [Settlement] { Balances.settlements(from: balances) }
    private var hasOthers: Bool { people.count > 1 }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var canAdd: Bool {
        guard let amount = parsedAmount, amount > 0 else { return false }
        guard !descriptionText.trimmed.isEmpty else { return false }
        return split == .even || forPerson != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            subTabBar
                .padding(.bottom, 16)

            switch subTab {
            case .add: addForm
            case .history: history
            }

            settlementPanel
                .padding(.top, 12)
        }
        .onAppear(perform: ensureDefaults)
        .onChange(of: people) { _, _ in ensureDefaults() }
        .confirmationDialog(
            "Delete expense?",
            isPresented: presenting($pendingDelete),
            titleVisibility: .visible
        ) {
            if let expense = pendingDelete {
                Button("Delete", role: .destructive) { store.delete(expense) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let expense = pendingDelete {
                Text("\"\(expense.displayTitle)\" · \(expense.amount.euros)")
            }
        }
        .confirmationDialog(
            "Settle up?",
            isPresented: presenting($pendingSettlement),
            titleVisibility: .visible
        ) {
            if let settlement = pendingSettlement {
                Button("Settle") {
                    store.recordSettlement(
                        in: household,
                        from: settlement.from,
                        to: settlement.to,
                        amount: settlement.amount
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let settlement = pendingSettlement {
                Text("Record that \(settlement.from) paid \(settlement.to) \(settlement.amount.euros). Balances will reset to even.")
            }
        }
    }

    // MARK: - Defaults

    private func ensureDefaults() {
        if paidBy.isEmpty || !people.contains(paidBy) {
            paidBy = people.contains(store.myName) ? store.myName : (people.first ?? "")
        }
        if forPerson == nil || forPerson == paidBy || !people.contains(forPerson ?? "") {
            forPerson = people.first { $0 != paidBy }
        }
        if !hasOthers { split = .even }
    }

    private func selectPaidBy(_ person: String) {
        paidBy = person
        if forPerson == person {
            forPerson = people.first { $0 != person }
        }
    }

    // MARK: - Sub tabs

    private var subTabBar: some View {
        HStack(spacing: 4) {
            ForEach(SubTab.allCases) { item in
                Button {
                    subTab = item
                } label: {
                    Text(title(for: item))
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(subTab == item ? .white : Theme.textFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(subTab == item ? Color.white.opacity(0.1) : .clear)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func title(for tab: SubTab) -> String {
        switch tab {
        case .add: return "Add Expense"
        case .history: return expenses.isEmpty ? "History" : "History (\(expenses.count))"
        }
    }

    // MARK: - Add

    private var addForm: some View {
        ScrollView {
            VStack(spacing: 12) {
                CardView(verticalPadding: 16, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("€")
                            .font(.mono(22))
                            .foregroundStyle(Theme.textMuted)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.display(32))
                            .foregroundStyle(.white)
                            .tint(Theme.coral)
                    }

                    TextField("What was this for?", text: $descriptionText)
                        .roomiesField()
                }

                CardView(spacing: 10) {
                    SectionLabel("Category")
                    FlowLayout(spacing: 6) {
                        ForEach(expenseCategories, id: \.self) { item in
                            ChipButton(label: item, isActive: category == item) {
                                category = item
                            }
                        }
                    }
                }

                CardView(spacing: 10) {
                    SectionLabel("Paid by")
                    PersonPicker(options: people, people: people, selected: paidBy) { selectPaidBy($0) }
                }

                CardView(spacing: 10) {
                    SectionLabel("Split")
                    HStack(spacing: 8) {
                        splitOption(
                            emoji: "⚖️",
                            title: "Split evenly",
                            subtitle: "everyone shares",
                            color: Theme.teal,
                            isActive: split == .even
                        ) { split = .even }

                        if hasOthers {
                            splitOption(
                                emoji: "💸",
                                title: "Full amount",
                                subtitle: "one person owes",
                                color: Theme.yellow,
                                isActive: split == .full
                            ) { split = .full }
                        }
                    }

                    if split == .full {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Who owes \(paidBy)?")
                                .font(.sans(12))
                                .foregroundStyle(Theme.textMuted)
                            PersonPicker(
                                options: people.filter { $0 != paidBy },
                                people: people,
                                selected: forPerson,
                                avatarSize: 26
                            ) { forPerson = $0 }
                        }
                        .padding(.top, 12)
                    }
                }

                PrimaryButton(title: justAdded ? "✓ Added!" : "Log Expense", isEnabled: canAdd) {
                    logExpense()
                }
            }
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func splitOption(
        emoji: String,
        title: String,
        subtitle: String,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(emoji).font(.system(size: 18))
                Text(title)
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(isActive ? color : Theme.textMuted)
                Text(subtitle)
                    .font(.sans(10))
                    .foregroundStyle(isActive ? color.opacity(0.7) : Theme.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? color.opacity(0.12) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? color.opacity(0.5) : Theme.cardBorder)
            }
        }
        .buttonStyle(.plain)
    }

    private func logExpense() {
        guard canAdd, let amount = parsedAmount else { return }

        store.addExpense(
            to: household,
            title: descriptionText,
            amount: amount,
            category: category,
            paidBy: paidBy,
            split: split,
            forPerson: forPerson
        )

        amountText = ""
        descriptionText = ""
        justAdded = true
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            justAdded = false
        }
    }

    // MARK: - History

    private var history: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if expenses.isEmpty {
                    Text("No expenses yet")
                        .font(.sans(14))
                        .foregroundStyle(Theme.textGhost)
                        .padding(.vertical, 40)
                } else {
                    ForEach(expenses, id: \.objectID) { expense in
                        expenseRow(expense)
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDelete = expense
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func expenseRow(_ expense: Expense) -> some View {
        CardView(horizontalPadding: 16) {
            HStack(spacing: 12) {
                AvatarView(name: expense.payer, people: people)

                VStack(alignment: .leading, spacing: 3) {
                    Text(expense.displayTitle)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    FlowLayout(spacing: 6) {
                        TagView(label: expense.displayCategory)
                        TagView(label: expense.splitSummary)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(expense.amount.euros)
                        .font(.mono(15, weight: .medium))
                        .foregroundStyle(Theme.personColor(expense.payer, in: people))
                    Text(RelativeTime.string(for: expense.createdAt))
                        .font(.sans(10))
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
    }

    // MARK: - Settlements

    private var settlementPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("WHO OWES WHAT")
                    .font(.mono(10))
                    .tracking(1)
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                Text(settlements.isEmpty
                     ? "all settled 🎉"
                     : "\(settlements.count) transfer\(settlements.count > 1 ? "s" : "")")
                    .font(.mono(10))
                    .foregroundStyle(Theme.textFaint)
            }

            if settlements.isEmpty {
                Text("Everyone's square ✓")
                    .font(.sans(14, weight: .bold))
                    .foregroundStyle(Theme.teal)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(settlements) { settlement in
                        HStack(spacing: 10) {
                            AvatarView(name: settlement.from, people: people, size: 28)

                            HStack(spacing: 6) {
                                Text(settlement.from)
                                    .font(.sans(13, weight: .medium))
                                    .foregroundStyle(Theme.textSoft)
                                Text("owes")
                                    .font(.sans(12))
                                    .foregroundStyle(Theme.textGhost)
                                Text(settlement.to)
                                    .font(.sans(13, weight: .medium))
                                    .foregroundStyle(Theme.personColor(settlement.to, in: people))
                            }

                            Spacer(minLength: 0)

                            Text(settlement.amount.euros)
                                .font(.mono(15, weight: .medium))
                                .foregroundStyle(Theme.coral)

                            Button {
                                pendingSettlement = settlement
                            } label: {
                                Text("Settle")
                                    .font(.sans(11, weight: .medium))
                                    .foregroundStyle(Theme.teal)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                            .strokeBorder(Theme.teal.opacity(0.4))
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1))
        }
    }
}

/// Bridges an optional selection to the `isPresented` binding a dialog wants.
func presenting<T>(_ item: Binding<T?>) -> Binding<Bool> {
    Binding(
        get: { item.wrappedValue != nil },
        set: { if !$0 { item.wrappedValue = nil } }
    )
}
