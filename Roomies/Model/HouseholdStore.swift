import CloudKit
import CoreData
import SwiftUI

/// Mutations for the flat, plus the one piece of device-local state:
/// which member *this* phone belongs to.
@MainActor
final class HouseholdStore: ObservableObject {
    private static let myNameKey = "roomies.myName"

    private let persistence: Persistence
    private var context: NSManagedObjectContext { persistence.viewContext }

    /// The member name chosen on this device. Empty until onboarding finishes.
    /// Written only through `setMyName` so the default keeps in step; a `didSet`
    /// observer on a `@Published` property is not worth relying on.
    @Published private(set) var myName: String

    @Published var errorMessage: String?

    /// `nonisolated` so SwiftUI can build it in `@StateObject` initialisation,
    /// which is not main-actor isolated.
    nonisolated init(persistence: Persistence = .shared) {
        self.persistence = persistence
        self.myName = UserDefaults.standard.string(forKey: Self.myNameKey) ?? ""
    }

    private func setMyName(_ name: String) {
        myName = name
        UserDefaults.standard.set(name, forKey: Self.myNameKey)
    }

    // MARK: - Household

    @discardableResult
    func createHousehold(named flatName: String, memberName: String) -> Household {
        let household = Household(context: context)
        household.id = UUID()
        household.name = flatName.trimmed
        household.createdAt = .now

        addMember(named: memberName, to: household)
        setMyName(memberName.trimmed)
        persistence.save()
        return household
    }

    /// Adds a flatmate by name, ignoring duplicates.
    func addMember(named name: String, to household: Household) {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty, !household.memberNames.contains(trimmed) else { return }

        let member = Member(context: context)
        member.id = UUID()
        member.name = trimmed
        member.createdAt = .now
        member.household = household
        persistence.save()
    }

    /// Called after accepting an invite: claim a name inside the shared flat.
    func claimName(_ name: String, in household: Household) {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return }
        addMember(named: trimmed, to: household)
        setMyName(trimmed)
    }

    // MARK: - Expenses

    func addExpense(
        to household: Household,
        title: String,
        amount: Double,
        category: String,
        paidBy: String,
        split: SplitType,
        forPerson: String?
    ) {
        let expense = Expense(context: context)
        expense.id = UUID()
        expense.title = title.trimmed
        expense.amount = amount
        expense.category = category
        expense.paidBy = paidBy
        expense.split = split
        expense.forPerson = split == .full ? forPerson : nil
        expense.createdAt = .now
        expense.household = household
        persistence.save()
    }

    func delete(_ expense: Expense) {
        context.delete(expense)
        persistence.save()
    }

    /// A payback is stored as a normal expense so it nets the balance to zero
    /// and stays visible in history.
    func recordSettlement(in household: Household, from: String, to: String, amount: Double) {
        addExpense(
            to: household,
            title: "\(from) paid back \(to)",
            amount: amount,
            category: settleUpCategory,
            paidBy: from,
            split: .full,
            forPerson: to
        )
    }

    // MARK: - Asks

    func addAsk(to household: Household, title: String, note: String?, askedBy: String, assignedTo: String?) {
        let ask = Ask(context: context)
        ask.id = UUID()
        ask.title = title.trimmed
        let trimmedNote = note?.trimmed
        ask.note = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        ask.askedBy = askedBy
        ask.assignedTo = assignedTo
        ask.status = .open
        ask.createdAt = .now
        ask.household = household
        persistence.save()
    }

    func accept(_ ask: Ask, by person: String) {
        ask.status = .accepted
        ask.acceptedBy = person
        persistence.save()
    }

    func complete(_ ask: Ask) {
        ask.status = .done
        ask.completedAt = .now
        persistence.save()
    }

    func delete(_ ask: Ask) {
        context.delete(ask)
        persistence.save()
    }

    // MARK: - Sharing

    func isShared(_ household: Household) -> Bool { persistence.isShared(household) }
    func isOwner(of household: Household) -> Bool { persistence.isOwner(of: household) }

    func share(_ household: Household) async -> (CKShare, CKContainer)? {
        do {
            return try await persistence.share(household)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Owner stops sharing; a participant leaves the flat.
    func stopSharing(_ household: Household) async {
        do {
            try await persistence.stopSharing(household)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
