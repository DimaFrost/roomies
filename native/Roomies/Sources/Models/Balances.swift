import Foundation

private let EPSILON = 0.005

/// Net balance per person: positive means the household owes them money,
/// negative means they owe the household.
func computeBalances(people: [String], expenses: [Expense]) -> [String: Double] {
    var balances: [String: Double] = [:]
    for p in people { balances[p] = 0 }

    for expense in expenses {
        guard balances[expense.paidBy] != nil else { continue }
        switch expense.split {
        case .even:
            let perPerson = expense.amount / Double(people.count)
            for p in people {
                if p != expense.paidBy {
                    balances[p, default: 0] -= perPerson
                } else {
                    balances[p, default: 0] += expense.amount - perPerson
                }
            }
        case .full:
            if let forPerson = expense.forPerson, forPerson != expense.paidBy, balances[forPerson] != nil {
                balances[forPerson, default: 0] -= expense.amount
                balances[expense.paidBy, default: 0] += expense.amount
            }
        }
    }

    return balances
}

struct Settlement: Identifiable, Equatable {
    var from: String
    var to: String
    var amount: Double
    var id: String { "\(from)->\(to)" }
}

/// Reduce balances to a minimal set of transfers.
func computeSettlements(balances: [String: Double]) -> [Settlement] {
    var creditors: [(person: String, amount: Double)] = []
    var debtors: [(person: String, amount: Double)] = []

    for (person, bal) in balances {
        if bal > EPSILON { creditors.append((person, bal)) }
        else if bal < -EPSILON { debtors.append((person, -bal)) }
    }

    creditors.sort { $0.amount > $1.amount }
    debtors.sort { $0.amount > $1.amount }

    var settlements: [Settlement] = []
    var i = 0
    var j = 0
    while i < creditors.count && j < debtors.count {
        let amount = min(creditors[i].amount, debtors[j].amount)
        settlements.append(Settlement(from: debtors[j].person, to: creditors[i].person, amount: amount))
        creditors[i].amount -= amount
        debtors[j].amount -= amount
        if creditors[i].amount < EPSILON { i += 1 }
        if debtors[j].amount < EPSILON { j += 1 }
    }
    return settlements
}
