import CoreData
import Foundation

/// How an expense is divided.
enum SplitType: String {
    /// Everyone in the flat shares the cost.
    case even
    /// One flatmate owes the whole amount.
    case full
}

enum AskStatus: String {
    case open
    case accepted
    case done
}

/// Category used for the synthetic expense that records a payback.
let settleUpCategory = "🤝 Settle-up"

let expenseCategories = [
    "🍕 Food",
    "🛒 Groceries",
    "🧹 Cleaning",
    "⚡ Utilities",
    "🎉 Fun",
    "🚗 Transport",
    "🏠 Rent",
    "💊 Other",
]

let quickAsks = [
    "🌱 Water my plants",
    "🛒 Pick something up",
    "🗑 Take out the trash",
    "🍳 Cook tonight",
    "📦 Accept a delivery",
    "🔑 Let someone in",
]

// The Core Data classes are generated from the model; these extensions add the
// typed accessors the UI works with.

extension Expense {
    var split: SplitType {
        get { SplitType(rawValue: splitRaw ?? "") ?? .even }
        set { splitRaw = newValue.rawValue }
    }

    var displayTitle: String { title ?? "" }
    var displayCategory: String { category ?? "" }
    var payer: String { paidBy ?? "" }

    /// What the split reads as in a list row.
    var splitSummary: String {
        if split == .full, let debtor = forPerson, !debtor.isEmpty {
            return "\(debtor) owes all"
        }
        return "split evenly"
    }
}

extension Ask {
    var status: AskStatus {
        get { AskStatus(rawValue: statusRaw ?? "") ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var displayTitle: String { title ?? "" }
    var requester: String { askedBy ?? "" }

    /// Who the ask is aimed at; nil means anyone can pick it up.
    var target: String? {
        guard let assignedTo, !assignedTo.isEmpty else { return nil }
        return assignedTo
    }
}

extension Household {
    /// Members in join order, which is also the order the colour palette follows.
    var sortedMembers: [Member] {
        let all = (members as? Set<Member>) ?? []
        return all.sorted { lhs, rhs in
            let l = lhs.createdAt ?? .distantPast
            let r = rhs.createdAt ?? .distantPast
            if l == r { return (lhs.name ?? "") < (rhs.name ?? "") }
            return l < r
        }
    }

    var memberNames: [String] {
        sortedMembers.compactMap { (member: Member) -> String? in
            guard let value = member.name, !value.isEmpty else { return nil }
            return value
        }
    }
}
