import AsyncStorage from "@react-native-async-storage/async-storage";
import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { makeId } from "./lib/time";
import { Ask, Expense, HouseholdState } from "./types";

const STORAGE_KEY = "roomies/state/v1";

const DEFAULT_STATE: HouseholdState = {
  people: ["Chris", "Dima"],
  expenses: [],
  asks: [],
};

export const SETTLE_UP_CATEGORY = "🤝 Settle-up";

interface HouseholdActions {
  addExpense: (expense: Omit<Expense, "id" | "createdAt">) => void;
  deleteExpense: (id: string) => void;
  recordSettlement: (from: string, to: string, amount: number) => void;
  addAsk: (ask: Omit<Ask, "id" | "createdAt" | "status">) => void;
  acceptAsk: (id: string, by: string) => void;
  completeAsk: (id: string) => void;
  deleteAsk: (id: string) => void;
}

interface HouseholdContextValue extends HouseholdActions {
  state: HouseholdState;
  hydrated: boolean;
}

const HouseholdContext = createContext<HouseholdContextValue | null>(null);

export function HouseholdProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<HouseholdState>(DEFAULT_STATE);
  const [hydrated, setHydrated] = useState(false);
  const hydratedRef = useRef(false);

  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then((raw) => {
        if (raw) {
          const parsed = JSON.parse(raw) as Partial<HouseholdState>;
          setState({ ...DEFAULT_STATE, ...parsed });
        }
      })
      .catch(() => {
        // Corrupt or unreadable state — start fresh rather than crash.
      })
      .finally(() => {
        hydratedRef.current = true;
        setHydrated(true);
      });
  }, []);

  useEffect(() => {
    if (!hydratedRef.current) return;
    AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(state)).catch(() => {});
  }, [state]);

  const addExpense = useCallback((expense: Omit<Expense, "id" | "createdAt">) => {
    const full: Expense = { ...expense, id: makeId(), createdAt: new Date().toISOString() };
    setState((s) => ({ ...s, expenses: [full, ...s.expenses] }));
  }, []);

  const deleteExpense = useCallback((id: string) => {
    setState((s) => ({ ...s, expenses: s.expenses.filter((e) => e.id !== id) }));
  }, []);

  const recordSettlement = useCallback((from: string, to: string, amount: number) => {
    const full: Expense = {
      id: makeId(),
      createdAt: new Date().toISOString(),
      description: `${from} paid back ${to}`,
      category: SETTLE_UP_CATEGORY,
      amount,
      paidBy: from,
      split: "full",
      forPerson: to,
    };
    setState((s) => ({ ...s, expenses: [full, ...s.expenses] }));
  }, []);

  const addAsk = useCallback((ask: Omit<Ask, "id" | "createdAt" | "status">) => {
    const full: Ask = { ...ask, id: makeId(), createdAt: new Date().toISOString(), status: "open" };
    setState((s) => ({ ...s, asks: [full, ...s.asks] }));
  }, []);

  const acceptAsk = useCallback((id: string, by: string) => {
    setState((s) => ({
      ...s,
      asks: s.asks.map((a) => (a.id === id ? { ...a, status: "accepted" as const, acceptedBy: by } : a)),
    }));
  }, []);

  const completeAsk = useCallback((id: string) => {
    setState((s) => ({
      ...s,
      asks: s.asks.map((a) =>
        a.id === id ? { ...a, status: "done" as const, completedAt: new Date().toISOString() } : a
      ),
    }));
  }, []);

  const deleteAsk = useCallback((id: string) => {
    setState((s) => ({ ...s, asks: s.asks.filter((a) => a.id !== id) }));
  }, []);

  return (
    <HouseholdContext.Provider
      value={{ state, hydrated, addExpense, deleteExpense, recordSettlement, addAsk, acceptAsk, completeAsk, deleteAsk }}
    >
      {children}
    </HouseholdContext.Provider>
  );
}

export function useHousehold(): HouseholdContextValue {
  const ctx = useContext(HouseholdContext);
  if (!ctx) throw new Error("useHousehold must be used within HouseholdProvider");
  return ctx;
}
