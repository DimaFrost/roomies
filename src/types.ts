export type SplitType = "even" | "full";

export interface Expense {
  id: string;
  description: string;
  amount: number;
  category: string;
  paidBy: string;
  split: SplitType;
  /** Who owes the full amount when split is "full". */
  forPerson?: string;
  createdAt: string; // ISO timestamp
}

export type AskStatus = "open" | "accepted" | "done";

export interface Ask {
  id: string;
  title: string;
  note?: string;
  askedBy: string;
  /** Specific flatmate the ask is directed at; undefined = anyone. */
  assignedTo?: string;
  status: AskStatus;
  acceptedBy?: string;
  createdAt: string; // ISO timestamp
  completedAt?: string; // ISO timestamp
}

export interface HouseholdState {
  people: string[];
  expenses: Expense[];
  asks: Ask[];
}
