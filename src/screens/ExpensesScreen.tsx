import React, { useMemo, useState } from "react";
import {
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { Avatar } from "../components/Avatar";
import { Card, SectionLabel } from "../components/Card";
import { PersonPicker } from "../components/PersonPicker";
import { Tag } from "../components/Tag";
import { computeBalances, computeSettlements } from "../lib/balances";
import { confirmAction } from "../lib/confirm";
import { timeAgo } from "../lib/time";
import { useHousehold } from "../store";
import { COLORS, FONTS, RADII, personColor } from "../theme";
import { Expense, SplitType } from "../types";

const CATEGORIES = [
  "🍕 Food",
  "🛒 Groceries",
  "🧹 Cleaning",
  "⚡ Utilities",
  "🎉 Fun",
  "🚗 Transport",
  "🏠 Rent",
  "💊 Other",
];

type SubTab = "add" | "history";

export function ExpensesScreen() {
  const { state, addExpense, deleteExpense, recordSettlement, myName } = useHousehold();
  const { people, expenses } = state;

  const [subTab, setSubTab] = useState<SubTab>("add");
  const [amount, setAmount] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState(CATEGORIES[0]);
  const [paidBy, setPaidBy] = useState(myName ?? people[0]);
  const [split, setSplit] = useState<SplitType>("even");
  const [forPerson, setForPerson] = useState<string | undefined>(people.find((p) => p !== (myName ?? people[0])));
  const [added, setAdded] = useState(false);

  const balances = useMemo(() => computeBalances(people, expenses), [people, expenses]);
  const settlements = useMemo(() => computeSettlements(balances), [balances]);
  const hasOthers = people.length > 1;

  const parsedAmount = parseFloat(amount.replace(",", "."));
  const canAdd =
    !Number.isNaN(parsedAmount) &&
    parsedAmount > 0 &&
    description.trim().length > 0 &&
    (split === "even" || !!forPerson);

  function selectPaidBy(p: string) {
    setPaidBy(p);
    if (forPerson === p) {
      const other = people.find((x) => x !== p);
      if (other) setForPerson(other);
    }
  }

  function handleAdd() {
    if (!canAdd) return;
    addExpense({
      description: description.trim(),
      amount: parsedAmount,
      category,
      paidBy,
      split,
      forPerson: split === "full" ? forPerson : undefined,
    });
    setAmount("");
    setDescription("");
    setAdded(true);
    setTimeout(() => setAdded(false), 1500);
  }

  function confirmDelete(exp: Expense) {
    confirmAction(
      "Delete expense?",
      `"${exp.description}" · €${exp.amount.toFixed(2)}`,
      "Delete",
      () => deleteExpense(exp.id),
      true
    );
  }

  function confirmSettle(from: string, to: string, settleAmount: number) {
    confirmAction(
      "Settle up?",
      `Record that ${from} paid ${to} €${settleAmount.toFixed(2)}. Balances will reset to even.`,
      "Settle",
      () => recordSettlement(from, to, settleAmount)
    );
  }

  return (
    <KeyboardAvoidingView
      style={{ flex: 1 }}
      behavior={Platform.OS === "ios" ? "padding" : undefined}
    >
      {/* Sub-tabs */}
      <View style={styles.tabBar}>
        {(["add", "history"] as SubTab[]).map((tab) => (
          <Pressable
            key={tab}
            onPress={() => setSubTab(tab)}
            style={[styles.tabBtn, subTab === tab && styles.tabBtnActive]}
          >
            <Text style={[styles.tabLabel, subTab === tab && styles.tabLabelActive]}>
              {tab === "add" ? "Add Expense" : `History${expenses.length ? ` (${expenses.length})` : ""}`}
            </Text>
          </Pressable>
        ))}
      </View>

      {subTab === "add" ? (
        <ScrollView
          style={{ flex: 1 }}
          contentContainerStyle={{ gap: 12, paddingBottom: 16 }}
          keyboardShouldPersistTaps="handled"
        >
          <Card style={{ gap: 12, paddingVertical: 16 }}>
            <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
              <Text style={{ fontFamily: FONTS.mono, fontSize: 22, color: "#666" }}>€</Text>
              <TextInput
                keyboardType="decimal-pad"
                placeholder="0.00"
                placeholderTextColor="#444"
                value={amount}
                onChangeText={setAmount}
                style={styles.amountInput}
              />
            </View>
            <TextInput
              placeholder="What was this for?"
              placeholderTextColor="#555"
              value={description}
              onChangeText={setDescription}
              style={styles.descriptionInput}
            />
          </Card>

          <Card>
            <SectionLabel>Category</SectionLabel>
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6 }}>
              {CATEGORIES.map((cat) => {
                const active = category === cat;
                return (
                  <Pressable
                    key={cat}
                    onPress={() => setCategory(cat)}
                    style={[styles.categoryChip, active && styles.categoryChipActive]}
                  >
                    <Text style={{ fontSize: 12, fontFamily: FONTS.sans, color: active ? COLORS.coral : "#888" }}>
                      {cat}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </Card>

          <Card>
            <SectionLabel>Paid by</SectionLabel>
            <PersonPicker options={people} people={people} selected={paidBy} onSelect={selectPaidBy} />
          </Card>

          <Card>
            <SectionLabel>Split</SectionLabel>
            <View style={{ flexDirection: "row", gap: 8 }}>
              <SplitOption
                emoji="⚖️"
                title="Split evenly"
                subtitle="everyone shares"
                color={COLORS.teal}
                active={split === "even"}
                onPress={() => setSplit("even")}
              />
              {hasOthers && (
                <SplitOption
                  emoji="💸"
                  title="Full amount"
                  subtitle="one person owes"
                  color={COLORS.yellow}
                  active={split === "full"}
                  onPress={() => setSplit("full")}
                />
              )}
            </View>

            {split === "full" && (
              <View style={{ marginTop: 12 }}>
                <Text style={{ fontFamily: FONTS.sans, fontSize: 12, color: "#666", marginBottom: 8 }}>
                  Who owes {paidBy}?
                </Text>
                <PersonPicker
                  options={people.filter((p) => p !== paidBy)}
                  people={people}
                  selected={forPerson}
                  onSelect={setForPerson}
                  avatarSize={26}
                />
              </View>
            )}
          </Card>

          <Pressable
            onPress={handleAdd}
            disabled={!canAdd}
            style={({ pressed }) => [
              styles.addBtn,
              !canAdd && styles.addBtnDisabled,
              pressed && canAdd && { transform: [{ scale: 0.97 }] },
            ]}
          >
            <Text style={[styles.addBtnLabel, !canAdd && { color: "#444" }]}>
              {added ? "✓ Added!" : "Log Expense"}
            </Text>
          </Pressable>
        </ScrollView>
      ) : (
        <FlatList
          style={{ flex: 1 }}
          data={expenses}
          keyExtractor={(e) => e.id}
          contentContainerStyle={{ gap: 10, paddingBottom: 16 }}
          ListEmptyComponent={
            <Text style={styles.emptyText}>No expenses yet</Text>
          }
          renderItem={({ item: exp }) => (
            <Pressable onLongPress={() => confirmDelete(exp)}>
              <Card style={styles.expenseRow}>
                <Avatar name={exp.paidBy} people={people} />
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Text numberOfLines={1} style={styles.expenseTitle}>
                    {exp.description}
                  </Text>
                  <View style={{ flexDirection: "row", gap: 6, flexWrap: "wrap", alignItems: "center" }}>
                    <Tag label={exp.category} />
                    <Tag label={exp.split === "full" && exp.forPerson ? `${exp.forPerson} owes all` : "split evenly"} />
                  </View>
                </View>
                <View style={{ alignItems: "flex-end" }}>
                  <Text style={[styles.expenseAmount, { color: personColor(exp.paidBy, people) }]}>
                    €{exp.amount.toFixed(2)}
                  </Text>
                  <Text style={styles.expenseDate}>{timeAgo(exp.createdAt)}</Text>
                </View>
              </Card>
            </Pressable>
          )}
        />
      )}

      {/* Settlements panel */}
      <View style={styles.settlePanel}>
        <View style={styles.settleHeader}>
          <Text style={styles.settleHeaderLabel}>Who owes what</Text>
          <Text style={styles.settleHeaderCount}>
            {settlements.length === 0
              ? "all settled 🎉"
              : `${settlements.length} transfer${settlements.length > 1 ? "s" : ""}`}
          </Text>
        </View>

        {settlements.length === 0 ? (
          <Text style={styles.allSquare}>Everyone's square ✓</Text>
        ) : (
          <View style={{ gap: 8 }}>
            {settlements.map(({ from, to, amount: settleAmount }, i) => (
              <View key={i} style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
                <Avatar name={from} people={people} size={28} />
                <View style={{ flex: 1, flexDirection: "row", alignItems: "center", gap: 6 }}>
                  <Text style={styles.settleName}>{from}</Text>
                  <Text style={{ fontFamily: FONTS.sans, fontSize: 12, color: COLORS.textGhost }}>owes</Text>
                  <Text style={[styles.settleName, { color: personColor(to, people) }]}>{to}</Text>
                </View>
                <Text style={styles.settleAmount}>€{settleAmount.toFixed(2)}</Text>
                <Pressable onPress={() => confirmSettle(from, to, settleAmount)} style={styles.settleBtn}>
                  <Text style={styles.settleBtnLabel}>Settle</Text>
                </Pressable>
              </View>
            ))}
          </View>
        )}
      </View>
    </KeyboardAvoidingView>
  );
}

function SplitOption({
  emoji,
  title,
  subtitle,
  color,
  active,
  onPress,
}: {
  emoji: string;
  title: string;
  subtitle: string;
  color: string;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={{
        flex: 1,
        padding: 12,
        borderRadius: 12,
        borderWidth: 1,
        borderColor: active ? `${color}80` : COLORS.cardBorder,
        backgroundColor: active ? `${color}1f` : "transparent",
        alignItems: "center",
      }}
    >
      <Text style={{ fontSize: 18, marginBottom: 2 }}>{emoji}</Text>
      <Text style={{ fontFamily: FONTS.sansMedium, fontSize: 13, color: active ? color : "#666" }}>{title}</Text>
      <Text style={{ fontFamily: FONTS.sans, fontSize: 10, color: active ? `${color}b3` : "#555", marginTop: 2 }}>
        {subtitle}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  tabBar: {
    flexDirection: "row",
    gap: 4,
    backgroundColor: COLORS.card,
    borderRadius: 12,
    padding: 4,
    marginBottom: 16,
  },
  tabBtn: {
    flex: 1,
    paddingVertical: 8,
    borderRadius: 9,
    alignItems: "center",
  },
  tabBtnActive: {
    backgroundColor: "rgba(255,255,255,0.1)",
  },
  tabLabel: {
    fontFamily: FONTS.sansMedium,
    fontSize: 13,
    color: COLORS.textFaint,
  },
  tabLabelActive: {
    color: "#fff",
  },
  amountInput: {
    flex: 1,
    fontFamily: FONTS.displayHeavy,
    fontSize: 32,
    color: "#fff",
    padding: 0,
  },
  descriptionInput: {
    backgroundColor: COLORS.card,
    borderWidth: 1,
    borderColor: COLORS.cardBorder,
    borderRadius: RADII.control,
    paddingHorizontal: 14,
    paddingVertical: 10,
    color: COLORS.textSoft,
    fontFamily: FONTS.sans,
    fontSize: 14,
  },
  categoryChip: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: RADII.pill,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.1)",
  },
  categoryChipActive: {
    borderColor: "rgba(255,107,107,0.6)",
    backgroundColor: "rgba(255,107,107,0.15)",
  },
  addBtn: {
    paddingVertical: 16,
    borderRadius: 14,
    backgroundColor: COLORS.coral,
    alignItems: "center",
  },
  addBtnDisabled: {
    backgroundColor: "rgba(255,255,255,0.06)",
  },
  addBtnLabel: {
    fontFamily: FONTS.display,
    fontSize: 15,
    color: "#fff",
    letterSpacing: 0.3,
  },
  emptyText: {
    textAlign: "center",
    color: COLORS.textGhost,
    paddingVertical: 40,
    fontSize: 14,
    fontFamily: FONTS.sans,
  },
  expenseRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    paddingHorizontal: 16,
  },
  expenseTitle: {
    fontFamily: FONTS.sansMedium,
    fontSize: 14,
    color: COLORS.text,
    marginBottom: 3,
  },
  expenseAmount: {
    fontFamily: FONTS.monoMedium,
    fontSize: 15,
  },
  expenseDate: {
    fontSize: 10,
    color: COLORS.textFaint,
    marginTop: 2,
    fontFamily: FONTS.sans,
  },
  settlePanel: {
    backgroundColor: COLORS.panel,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.1)",
    borderRadius: 20,
    paddingHorizontal: 20,
    paddingVertical: 16,
    marginTop: 12,
  },
  settleHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: 12,
  },
  settleHeaderLabel: {
    fontFamily: FONTS.mono,
    fontSize: 10,
    color: COLORS.textFaint,
    textTransform: "uppercase",
    letterSpacing: 1,
  },
  settleHeaderCount: {
    fontFamily: FONTS.mono,
    fontSize: 10,
    color: COLORS.textFaint,
  },
  allSquare: {
    textAlign: "center",
    color: COLORS.teal,
    fontFamily: FONTS.sansBold,
    fontSize: 14,
    paddingVertical: 6,
  },
  settleName: {
    fontFamily: FONTS.sansMedium,
    fontSize: 13,
    color: COLORS.textSoft,
  },
  settleAmount: {
    fontFamily: FONTS.monoMedium,
    fontSize: 15,
    color: COLORS.coral,
  },
  settleBtn: {
    borderWidth: 1,
    borderColor: "rgba(78,205,196,0.4)",
    borderRadius: RADII.pill,
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  settleBtnLabel: {
    fontFamily: FONTS.sansMedium,
    fontSize: 11,
    color: COLORS.teal,
  },
});
