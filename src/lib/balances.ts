import { Expense } from "../types";

const EPSILON = 0.005;

/**
 * Net balance per person: positive means the household owes them money,
 * negative means they owe the household.
 */
export function computeBalances(people: string[], expenses: Expense[]): Record<string, number> {
  const balances: Record<string, number> = {};
  people.forEach((p) => (balances[p] = 0));

  for (const { paidBy, amount, split, forPerson } of expenses) {
    if (!(paidBy in balances)) continue;
    if (split === "even") {
      const perPerson = amount / people.length;
      for (const p of people) {
        if (p !== paidBy) balances[p] -= perPerson;
        else balances[p] += amount - perPerson;
      }
    } else if (forPerson && forPerson !== paidBy && forPerson in balances) {
      balances[forPerson] -= amount;
      balances[paidBy] += amount;
    }
  }

  return balances;
}

export interface Settlement {
  from: string;
  to: string;
  amount: number;
}

/** Reduce balances to a minimal set of transfers. */
export function computeSettlements(balances: Record<string, number>): Settlement[] {
  const creditors: { person: string; amount: number }[] = [];
  const debtors: { person: string; amount: number }[] = [];

  for (const [person, bal] of Object.entries(balances)) {
    if (bal > EPSILON) creditors.push({ person, amount: bal });
    else if (bal < -EPSILON) debtors.push({ person, amount: -bal });
  }

  creditors.sort((a, b) => b.amount - a.amount);
  debtors.sort((a, b) => b.amount - a.amount);

  const settlements: Settlement[] = [];
  let i = 0;
  let j = 0;
  while (i < creditors.length && j < debtors.length) {
    const c = creditors[i];
    const d = debtors[j];
    const amount = Math.min(c.amount, d.amount);
    settlements.push({ from: d.person, to: c.person, amount });
    c.amount -= amount;
    d.amount -= amount;
    if (c.amount < EPSILON) i++;
    if (d.amount < EPSILON) j++;
  }
  return settlements;
}
