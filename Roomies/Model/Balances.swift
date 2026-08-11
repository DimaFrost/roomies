import Foundation

struct Settlement: Identifiable, Equatable {
    let from: String
    let to: String
    let amount: Double

    var id: String { "\(from)>\(to)" }
}

enum Balances {
    /// Half a cent: below this a balance is considered square.
    private static let epsilon = 0.005

    /// Net balance per person: positive means the flat owes them money,
    /// negative means they owe the flat.
    static func compute(people: [String], expenses: [Expense]) -> [String: Double] {
        guard !people.isEmpty else { return [:] }

        var balances = Dictionary(uniqueKeysWithValues: people.map { ($0, 0.0) })

        for expense in expenses {
            let paidBy = expense.payer
            // Expenses attributed to someone no longer in the flat are skipped.
            guard balances[paidBy] != nil else { continue }
            let amount = expense.amount

            switch expense.split {
            case .even:
                let perPerson = amount / Double(people.count)
                for person in people {
                    if person == paidBy {
                        balances[person]? += amount - perPerson
                    } else {
                        balances[person]? -= perPerson
                    }
                }
            case .full:
                guard let debtor = expense.forPerson,
                      debtor != paidBy,
                      balances[debtor] != nil else { continue }
                balances[debtor]? -= amount
                balances[paidBy]? += amount
            }
        }

        return balances
    }

    /// Reduces balances to a minimal set of transfers, largest debts first.
    static func settlements(from balances: [String: Double]) -> [Settlement] {
        var creditors: [(person: String, amount: Double)] = []
        var debtors: [(person: String, amount: Double)] = []

        for (person, balance) in balances {
            if balance > epsilon {
                creditors.append((person, balance))
            } else if balance < -epsilon {
                debtors.append((person, -balance))
            }
        }

        // Swift randomises dictionary iteration order, so ties must be broken
        // explicitly or the rendered list reshuffles between redraws. When two
        // people owe the same amount this pairs them differently from the old
        // JS version (which leaned on insertion order); the transfer count and
        // amounts are identical either way, and everyone still ends square.
        creditors.sort { $0.amount == $1.amount ? $0.person < $1.person : $0.amount > $1.amount }
        debtors.sort { $0.amount == $1.amount ? $0.person < $1.person : $0.amount > $1.amount }

        var settlements: [Settlement] = []
        var i = 0
        var j = 0
        while i < creditors.count, j < debtors.count {
            let amount = min(creditors[i].amount, debtors[j].amount)
            settlements.append(Settlement(from: debtors[j].person, to: creditors[i].person, amount: amount))
            creditors[i].amount -= amount
            debtors[j].amount -= amount
            if creditors[i].amount < epsilon { i += 1 }
            if debtors[j].amount < epsilon { j += 1 }
        }
        return settlements
    }
}
