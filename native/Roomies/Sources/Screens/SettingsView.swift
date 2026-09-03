import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: HouseholdStore

    @State private var flatName = ""
    @State private var rentText = ""
    @State private var rentDayText = ""
    @State private var savedFlash = false
    @State private var removeTarget: String?
    @State private var confirmingLeave = false
    @State private var leaving = false
    @State private var leaveError: String?

    @State private var billTitle = ""
    @State private var billAmount = ""
    @State private var billDay = ""

    private var people: [String] { store.state.people }
    private var canAddBill: Bool {
        !billTitle.trimmed.isEmpty
            && (Double(billAmount.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
            && (Int(billDay).map { (1...31).contains($0) } ?? false)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                flatCard
                groundTruthCard
                billsCard
                flatmatesCard
                leaveCard
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            flatName = store.flat?.name ?? ""
            rentText = store.flat?.rentAmount.map { String(format: "%.2f", $0) } ?? ""
            rentDayText = store.flat?.rentDueDay.map(String.init) ?? ""
        }
        .alert("Remove flatmate?", isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } })) {
            Button("Cancel", role: .cancel) { removeTarget = nil }
            Button("Remove", role: .destructive) {
                if let t = removeTarget { store.removeMember(name: t) }
                removeTarget = nil
            }
        } message: {
            if let t = removeTarget {
                Text("\(t) will lose access to this flat. Their expenses and asks stay in the history.")
            }
        }
        .sheet(isPresented: Binding(get: { store.pendingShare != nil }, set: { if !$0 { store.pendingShare = nil } })) {
            if let share = store.pendingShare {
                InviteLinkView(share: share)
            }
        }
        .alert(store.isOwner ? "Delete this flat?" : "Leave this flat?", isPresented: $confirmingLeave) {
            Button("Cancel", role: .cancel) {}
            Button(store.isOwner ? "Delete" : "Leave", role: .destructive) {
                Task { await leave() }
            }
        } message: {
            Text(store.isOwner
                ? "You created this flat, so leaving deletes it for everyone — your flatmates lose access and all data goes with it. This can't be undone."
                : "You'll lose access to \(store.flat?.name ?? "this flat"). Your expenses and asks stay in its history for everyone else.")
        }
    }

    private var flatCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Flat name")
                TextField("Your flat", text: $flatName)
                    .textFieldStyle(RoomiesTextFieldStyle())
                Button {
                    store.renameHousehold(flatName.trimmed)
                    flash()
                } label: {
                    Text(savedFlash ? "✓ Saved" : "Save name")
                        .font(Fonts.sans(13, weight: .medium))
                        .foregroundColor(Theme.teal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.teal.opacity(0.4), lineWidth: 1))
                }
                .disabled(flatName.trimmed.isEmpty)

                Divider().overlay(Theme.cardBorder)

                Button {
                    Task { await store.presentInvite() }
                } label: {
                    HStack {
                        Text("＋ Invite a flatmate")
                            .font(Fonts.sans(14, weight: .medium))
                            .foregroundColor(Theme.coral)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                Text("Shows a link to copy and send — they paste it into Roomies under \"Join a flat.\"")
                    .font(Fonts.sans(11))
                    .foregroundColor(Theme.textFaint)
            }
        }
    }

    private var groundTruthCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Rent")
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly amount").font(Fonts.sans(11)).foregroundColor(Theme.textFaint)
                        TextField("0.00", text: $rentText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoomiesTextFieldStyle())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Due day").font(Fonts.sans(11)).foregroundColor(Theme.textFaint)
                        TextField("1", text: $rentDayText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoomiesTextFieldStyle())
                    }
                    .frame(width: 90)
                }
                Button {
                    store.saveRentSettings(
                        amount: Double(rentText.replacingOccurrences(of: ",", with: ".")),
                        dueDay: Int(rentDayText).flatMap { (1...31).contains($0) ? $0 : nil }
                    )
                    flash()
                } label: {
                    Text(savedFlash ? "✓ Saved" : "Save rent")
                        .font(Fonts.sans(13, weight: .medium))
                        .foregroundColor(Theme.teal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.teal.opacity(0.4), lineWidth: 1))
                }
            }
        }
    }

    private var billsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Recurring bills")

                if store.state.bills.isEmpty {
                    Text("Nothing recurring yet — add the ones that hit every month.")
                        .font(Fonts.sans(12))
                        .foregroundColor(Theme.textFaint)
                }

                ForEach(store.state.bills) { bill in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bill.title).font(Fonts.sans(14, weight: .medium)).foregroundColor(Theme.text)
                            Text("due the \(bill.dueDay)\(ordinalSuffix(bill.dueDay))\(bill.paidBy.map { " · \($0) pays" } ?? "")")
                                .font(Fonts.mono(10)).foregroundColor(Theme.textFaint)
                        }
                        Spacer()
                        Text("€\(String(format: "%.2f", bill.amount))")
                            .font(Fonts.mono(14, weight: .medium)).foregroundColor(Theme.textSoft)
                        Button {
                            store.deleteBill(id: bill.id)
                        } label: {
                            Text("✕").font(Fonts.sans(13)).foregroundColor(Theme.textFaint)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Divider().overlay(Theme.cardBorder)

                TextField("Bill name (internet, electricity…)", text: $billTitle)
                    .textFieldStyle(RoomiesTextFieldStyle())
                HStack(spacing: 8) {
                    TextField("0.00", text: $billAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoomiesTextFieldStyle())
                    TextField("day", text: $billDay)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoomiesTextFieldStyle())
                        .frame(width: 80)
                }
                Button {
                    store.addBill(
                        title: billTitle.trimmed,
                        amount: Double(billAmount.replacingOccurrences(of: ",", with: ".")) ?? 0,
                        dueDay: Int(billDay) ?? 1,
                        paidBy: nil
                    )
                    billTitle = ""; billAmount = ""; billDay = ""
                } label: {
                    Text("Add bill")
                        .font(Fonts.sans(13, weight: .medium))
                        .foregroundColor(canAddBill ? Theme.yellow : Theme.textGhost)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(canAddBill ? Theme.yellow.opacity(0.4) : Theme.cardBorder, lineWidth: 1))
                }
                .disabled(!canAddBill)
            }
        }
    }

    private var flatmatesCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Flatmates")
                ForEach(people, id: \.self) { person in
                    HStack(spacing: 12) {
                        AvatarView(name: person, people: people, size: 32)
                        Text(person).font(Fonts.sans(14, weight: .medium)).foregroundColor(Theme.text)
                        if person == store.myName {
                            Text("you").font(Fonts.mono(10)).foregroundColor(Theme.textFaint)
                        }
                        Spacer()
                        Button {
                            removeTarget = person
                        } label: {
                            Text("Remove")
                                .font(Fonts.sans(11, weight: .medium))
                                .foregroundColor(Theme.coral)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .overlay(Capsule().stroke(Theme.coral.opacity(0.35), lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    private var leaveCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    confirmingLeave = true
                } label: {
                    Text(leaving ? "Leaving…" : (store.isOwner ? "Delete this flat" : "Leave this flat"))
                        .font(Fonts.sans(14, weight: .medium))
                        .foregroundColor(Theme.coral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .disabled(leaving)

                if let leaveError {
                    Text(leaveError).font(Fonts.sans(12)).foregroundColor(Theme.coral)
                }
            }
        }
    }

    private func leave() async {
        leaving = true
        leaveError = await store.leaveHousehold()
        leaving = false
    }

    private func flash() {
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
    }
}

func ordinalSuffix(_ day: Int) -> String {
    switch day % 100 {
    case 11, 12, 13: return "th"
    default:
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
