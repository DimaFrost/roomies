import AsyncStorage from "@react-native-async-storage/async-storage";
import type { RealtimeChannel } from "@supabase/supabase-js";
import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { supabase } from "./lib/supabase";
import { makeId, uuidv4 } from "./lib/time";
import { Ask, Expense, HouseholdState } from "./types";

const LOCAL_STATE_KEY = "roomies/state/v1";
const DEVICE_CREDS_KEY = "roomies/device-creds/v1";

const DEFAULT_LOCAL_STATE: HouseholdState = {
  people: ["Chris", "Dima"],
  expenses: [],
  asks: [],
};

const EMPTY_STATE: HouseholdState = { people: [], expenses: [], asks: [] };

export const SETTLE_UP_CATEGORY = "🤝 Settle-up";

export type Phase = "loading" | "onboarding" | "ready" | "error";

export interface FlatInfo {
  id: string;
  name: string;
  inviteCode: string;
}

interface HouseholdContextValue {
  /** "cloud" when a Supabase backend is configured, otherwise "local". */
  mode: "local" | "cloud";
  phase: Phase;
  state: HouseholdState;
  flat: FlatInfo | null;
  /** This device's member name (cloud mode only). */
  myName: string | null;
  error: string | null;
  retry: () => void;
  createHousehold: (flatName: string, memberName: string) => Promise<string | null>;
  joinHousehold: (code: string, memberName: string) => Promise<string | null>;
  addExpense: (expense: Omit<Expense, "id" | "createdAt">) => void;
  deleteExpense: (id: string) => void;
  recordSettlement: (from: string, to: string, amount: number) => void;
  addAsk: (ask: Omit<Ask, "id" | "createdAt" | "status">) => void;
  acceptAsk: (id: string, by: string) => void;
  completeAsk: (id: string) => void;
  deleteAsk: (id: string) => void;
}

const HouseholdContext = createContext<HouseholdContextValue | null>(null);

/* ---------- row mapping (snake_case DB rows <-> app types) ---------- */

function rowToExpense(r: Record<string, unknown>): Expense {
  return {
    id: r.id as string,
    description: r.description as string,
    amount: Number(r.amount),
    category: r.category as string,
    paidBy: r.paid_by as string,
    split: r.split as Expense["split"],
    forPerson: (r.for_person as string | null) ?? undefined,
    createdAt: r.created_at as string,
  };
}

function rowToAsk(r: Record<string, unknown>): Ask {
  return {
    id: r.id as string,
    title: r.title as string,
    note: (r.note as string | null) ?? undefined,
    askedBy: r.asked_by as string,
    assignedTo: (r.assigned_to as string | null) ?? undefined,
    status: r.status as Ask["status"],
    acceptedBy: (r.accepted_by as string | null) ?? undefined,
    createdAt: r.created_at as string,
    completedAt: (r.completed_at as string | null) ?? undefined,
  };
}

function byNewest<T extends { createdAt: string }>(a: T, b: T) {
  return a.createdAt < b.createdAt ? 1 : -1;
}

function upsert<T extends { id: string; createdAt: string }>(list: T[], item: T): T[] {
  return [item, ...list.filter((x) => x.id !== item.id)].sort(byNewest);
}

export function HouseholdProvider({ children }: { children: React.ReactNode }) {
  const mode: "local" | "cloud" = supabase ? "cloud" : "local";
  const [state, setState] = useState<HouseholdState>(EMPTY_STATE);
  const [phase, setPhase] = useState<Phase>("loading");
  const [flat, setFlat] = useState<FlatInfo | null>(null);
  const [myName, setMyName] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const flatRef = useRef<FlatInfo | null>(null);
  flatRef.current = flat;
  const channelRef = useRef<RealtimeChannel | null>(null);
  const localHydrated = useRef(false);

  /* ---------- local mode: AsyncStorage persistence ---------- */

  useEffect(() => {
    if (mode !== "local") return;
    AsyncStorage.getItem(LOCAL_STATE_KEY)
      .then((raw) => {
        if (raw) {
          const parsed = JSON.parse(raw) as Partial<HouseholdState>;
          setState({ ...DEFAULT_LOCAL_STATE, ...parsed });
        } else {
          setState(DEFAULT_LOCAL_STATE);
        }
      })
      .catch(() => setState(DEFAULT_LOCAL_STATE))
      .finally(() => {
        localHydrated.current = true;
        setPhase("ready");
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (mode !== "local" || !localHydrated.current) return;
    AsyncStorage.setItem(LOCAL_STATE_KEY, JSON.stringify(state)).catch(() => {});
  }, [mode, state]);

  /* ---------- cloud mode: session, load, realtime ---------- */

  const ensureSession = useCallback(async () => {
    const { data } = await supabase!.auth.getSession();
    if (data.session) return;

    let creds: { email: string; password: string } | null = null;
    const raw = await AsyncStorage.getItem(DEVICE_CREDS_KEY);
    if (raw) creds = JSON.parse(raw);
    if (!creds) {
      creds = {
        email: `device-${uuidv4()}@device.roomies.app`,
        password: `${uuidv4()}${uuidv4()}`,
      };
      await AsyncStorage.setItem(DEVICE_CREDS_KEY, JSON.stringify(creds));
    }

    // Existing device account? Just sign in. Otherwise create it first.
    const first = await supabase!.auth.signInWithPassword(creds);
    if (!first.error) return;

    const { error: fnError } = await supabase!.functions.invoke("roomies-create-device-user", { body: creds });
    if (fnError) throw new Error("Could not reach the sync server");
    const second = await supabase!.auth.signInWithPassword(creds);
    if (second.error) throw new Error(second.error.message);
  }, []);

  const subscribeToHousehold = useCallback((householdId: string) => {
    channelRef.current?.unsubscribe();
    channelRef.current = supabase!
      .channel(`household:${householdId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "roomies_expenses", filter: `household_id=eq.${householdId}` },
        (payload) => {
          setState((s) => {
            if (payload.eventType === "DELETE") {
              const oldId = (payload.old as { id?: string }).id;
              return { ...s, expenses: s.expenses.filter((e) => e.id !== oldId) };
            }
            return { ...s, expenses: upsert(s.expenses, rowToExpense(payload.new)) };
          });
        }
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "roomies_asks", filter: `household_id=eq.${householdId}` },
        (payload) => {
          setState((s) => {
            if (payload.eventType === "DELETE") {
              const oldId = (payload.old as { id?: string }).id;
              return { ...s, asks: s.asks.filter((a) => a.id !== oldId) };
            }
            return { ...s, asks: upsert(s.asks, rowToAsk(payload.new)) };
          });
        }
      )
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "roomies_members", filter: `household_id=eq.${householdId}` },
        (payload) => {
          const name = (payload.new as { name?: string }).name;
          if (name) {
            setState((s) => (s.people.includes(name) ? s : { ...s, people: [...s.people, name] }));
          }
        }
      )
      .subscribe();
  }, []);

  const loadHousehold = useCallback(async (): Promise<boolean> => {
    const { data: userData } = await supabase!.auth.getUser();
    const uid = userData.user?.id;
    if (!uid) throw new Error("no session");

    const { data: membership, error: mErr } = await supabase!
      .from("roomies_members")
      .select("household_id, name, roomies_households(id, name, invite_code)")
      .eq("user_id", uid)
      .limit(1)
      .maybeSingle();
    if (mErr) throw new Error(mErr.message);
    if (!membership) return false;

    const householdId = membership.household_id as string;
    const household = membership.roomies_households as unknown as { id: string; name: string; invite_code: string };

    const [membersRes, expensesRes, asksRes] = await Promise.all([
      supabase!.from("roomies_members").select("name, created_at").eq("household_id", householdId).order("created_at"),
      supabase!.from("roomies_expenses").select("*").eq("household_id", householdId).order("created_at", { ascending: false }),
      supabase!.from("roomies_asks").select("*").eq("household_id", householdId).order("created_at", { ascending: false }),
    ]);
    const anyErr = membersRes.error ?? expensesRes.error ?? asksRes.error;
    if (anyErr) throw new Error(anyErr.message);

    setState({
      people: (membersRes.data ?? []).map((m) => m.name as string),
      expenses: (expensesRes.data ?? []).map(rowToExpense),
      asks: (asksRes.data ?? []).map(rowToAsk),
    });
    setFlat({ id: household.id, name: household.name, inviteCode: household.invite_code });
    setMyName(membership.name as string);
    subscribeToHousehold(householdId);
    return true;
  }, [subscribeToHousehold]);

  const bootstrap = useCallback(async () => {
    setPhase("loading");
    setError(null);
    try {
      await ensureSession();
      const hasHousehold = await loadHousehold();
      setPhase(hasHousehold ? "ready" : "onboarding");
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setPhase("error");
    }
  }, [ensureSession, loadHousehold]);

  useEffect(() => {
    if (mode !== "cloud") return;
    bootstrap();
    return () => {
      channelRef.current?.unsubscribe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /* ---------- household setup (cloud) ---------- */

  const runSetupRpc = useCallback(
    async (fn: "roomies_create_household" | "roomies_join_household", args: Record<string, string>): Promise<string | null> => {
      if (!supabase) return "Sync is not configured in this build";
      const { error: rpcError } = await supabase.rpc(fn, args);
      if (rpcError) {
        if (rpcError.message.includes("invalid invite code")) return "That invite code doesn't match any flat";
        if (rpcError.message.includes("roomies_members_household_id_name_key")) return "Someone in the flat already uses that name";
        return rpcError.message;
      }
      try {
        const ok = await loadHousehold();
        if (!ok) return "Setup succeeded but the flat could not be loaded";
        setPhase("ready");
        return null;
      } catch (e) {
        return e instanceof Error ? e.message : String(e);
      }
    },
    [loadHousehold]
  );

  const createHousehold = useCallback(
    (flatName: string, memberName: string) =>
      runSetupRpc("roomies_create_household", { flat_name: flatName.trim(), member_name: memberName.trim() }),
    [runSetupRpc]
  );

  const joinHousehold = useCallback(
    (code: string, memberName: string) =>
      runSetupRpc("roomies_join_household", { code: code.trim().toUpperCase(), member_name: memberName.trim() }),
    [runSetupRpc]
  );

  /* ---------- writes (optimistic locally, mirrored to DB in cloud mode) ---------- */

  const insertExpense = useCallback((expense: Omit<Expense, "id" | "createdAt">) => {
    const full: Expense = {
      ...expense,
      id: supabase ? uuidv4() : makeId(),
      createdAt: new Date().toISOString(),
    };
    setState((s) => ({ ...s, expenses: [full, ...s.expenses] }));
    if (!supabase) return;
    supabase
      .from("roomies_expenses")
      .insert({
        id: full.id,
        household_id: flatRef.current!.id,
        description: full.description,
        amount: full.amount,
        category: full.category,
        paid_by: full.paidBy,
        split: full.split,
        for_person: full.forPerson ?? null,
        created_at: full.createdAt,
      })
      .then(({ error: e }) => {
        if (e) {
          setError(`Expense didn't sync: ${e.message}`);
          setState((s) => ({ ...s, expenses: s.expenses.filter((x) => x.id !== full.id) }));
        }
      });
  }, []);

  const addExpense = insertExpense;

  const deleteExpense = useCallback((id: string) => {
    setState((s) => ({ ...s, expenses: s.expenses.filter((e) => e.id !== id) }));
    if (!supabase) return;
    supabase
      .from("roomies_expenses")
      .delete()
      .eq("id", id)
      .then(({ error: e }) => {
        if (e) setError(`Delete didn't sync: ${e.message}`);
      });
  }, []);

  const recordSettlement = useCallback(
    (from: string, to: string, amount: number) => {
      insertExpense({
        description: `${from} paid back ${to}`,
        category: SETTLE_UP_CATEGORY,
        amount,
        paidBy: from,
        split: "full",
        forPerson: to,
      });
    },
    [insertExpense]
  );

  const addAsk = useCallback((ask: Omit<Ask, "id" | "createdAt" | "status">) => {
    const full: Ask = {
      ...ask,
      id: supabase ? uuidv4() : makeId(),
      createdAt: new Date().toISOString(),
      status: "open",
    };
    setState((s) => ({ ...s, asks: [full, ...s.asks] }));
    if (!supabase) return;
    supabase
      .from("roomies_asks")
      .insert({
        id: full.id,
        household_id: flatRef.current!.id,
        title: full.title,
        note: full.note ?? null,
        asked_by: full.askedBy,
        assigned_to: full.assignedTo ?? null,
        status: "open",
        created_at: full.createdAt,
      })
      .then(({ error: e }) => {
        if (e) {
          setError(`Ask didn't sync: ${e.message}`);
          setState((s) => ({ ...s, asks: s.asks.filter((x) => x.id !== full.id) }));
        }
      });
  }, []);

  const patchAsk = useCallback((id: string, patch: Partial<Ask>, dbPatch: Record<string, unknown>) => {
    setState((s) => ({ ...s, asks: s.asks.map((a) => (a.id === id ? { ...a, ...patch } : a)) }));
    if (!supabase) return;
    supabase
      .from("roomies_asks")
      .update(dbPatch)
      .eq("id", id)
      .then(({ error: e }) => {
        if (e) setError(`Update didn't sync: ${e.message}`);
      });
  }, []);

  const acceptAsk = useCallback(
    (id: string, by: string) => patchAsk(id, { status: "accepted", acceptedBy: by }, { status: "accepted", accepted_by: by }),
    [patchAsk]
  );

  const completeAsk = useCallback(
    (id: string) => {
      const completedAt = new Date().toISOString();
      patchAsk(id, { status: "done", completedAt }, { status: "done", completed_at: completedAt });
    },
    [patchAsk]
  );

  const deleteAsk = useCallback((id: string) => {
    setState((s) => ({ ...s, asks: s.asks.filter((a) => a.id !== id) }));
    if (!supabase) return;
    supabase
      .from("roomies_asks")
      .delete()
      .eq("id", id)
      .then(({ error: e }) => {
        if (e) setError(`Delete didn't sync: ${e.message}`);
      });
  }, []);

  return (
    <HouseholdContext.Provider
      value={{
        mode,
        phase,
        state,
        flat,
        myName,
        error,
        retry: bootstrap,
        createHousehold,
        joinHousehold,
        addExpense,
        deleteExpense,
        recordSettlement,
        addAsk,
        acceptAsk,
        completeAsk,
        deleteAsk,
      }}
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
