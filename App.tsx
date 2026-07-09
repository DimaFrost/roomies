import { DMMono_400Regular, DMMono_500Medium } from "@expo-google-fonts/dm-mono";
import { DMSans_400Regular, DMSans_500Medium, DMSans_700Bold } from "@expo-google-fonts/dm-sans";
import { Syne_700Bold, Syne_800ExtraBold } from "@expo-google-fonts/syne";
import { useFonts } from "expo-font";
import { StatusBar } from "expo-status-bar";
import React, { useMemo, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaProvider, useSafeAreaInsets } from "react-native-safe-area-context";
import { Avatar } from "./src/components/Avatar";
import { AsksScreen } from "./src/screens/AsksScreen";
import { ExpensesScreen } from "./src/screens/ExpensesScreen";
import { OnboardingScreen } from "./src/screens/OnboardingScreen";
import { HouseholdProvider, useHousehold } from "./src/store";
import { COLORS, FONTS } from "./src/theme";

type Tab = "split" | "asks";

const TABS: { key: Tab; emoji: string; label: string }[] = [
  { key: "split", emoji: "💶", label: "Split" },
  { key: "asks", emoji: "🤝", label: "Asks" },
];

function Shell() {
  const insets = useSafeAreaInsets();
  const { state, phase, flat, error, retry } = useHousehold();
  const [tab, setTab] = useState<Tab>("split");

  const totalSpend = useMemo(
    () => state.expenses.reduce((s, e) => s + e.amount, 0),
    [state.expenses]
  );
  const openAsks = useMemo(
    () => state.asks.filter((a) => a.status !== "done").length,
    [state.asks]
  );

  if (phase === "loading") {
    return <View style={{ flex: 1, backgroundColor: COLORS.bg }} />;
  }

  if (phase === "error") {
    return (
      <View style={styles.centered}>
        <Text style={styles.errorTitle}>Can't reach the flat ☁️</Text>
        <Text style={styles.errorDetail}>{error}</Text>
        <Pressable onPress={retry} style={styles.retryBtn}>
          <Text style={styles.retryLabel}>Try again</Text>
        </Pressable>
      </View>
    );
  }

  if (phase === "onboarding") {
    return (
      <View style={[styles.root, { paddingTop: insets.top }]}>
        <OnboardingScreen />
      </View>
    );
  }

  return (
    <View style={[styles.root, { paddingTop: insets.top + 16 }]}>
      <View style={styles.content}>
        {/* Header */}
        <View style={styles.header}>
          <View>
            <Text style={styles.wordmark}>
              room<Text style={{ color: COLORS.coral }}>ies</Text>
            </Text>
            <Text style={styles.subline}>
              {tab === "split"
                ? `${state.people.length} flatmate${state.people.length === 1 ? "" : "s"} · €${totalSpend.toFixed(2)} total`
                : `${state.people.length} flatmate${state.people.length === 1 ? "" : "s"} · ${openAsks} open ask${openAsks === 1 ? "" : "s"}`}
            </Text>
            {flat && (
              <Text style={styles.flatLine}>
                {flat.name} · invite {flat.inviteCode}
              </Text>
            )}
          </View>
          <View style={{ flexDirection: "row" }}>
            {state.people.map((p, i) => (
              <View key={p} style={{ marginLeft: i === 0 ? 0 : -10, zIndex: state.people.length - i }}>
                <Avatar name={p} people={state.people} size={32} />
              </View>
            ))}
          </View>
        </View>

        {/* Active screen */}
        <View style={{ flex: 1 }}>{tab === "split" ? <ExpensesScreen /> : <AsksScreen />}</View>
      </View>

      {/* Bottom tab bar */}
      <View style={[styles.tabBar, { paddingBottom: Math.max(insets.bottom, 12) }]}>
        {TABS.map(({ key, emoji, label }) => {
          const active = tab === key;
          const badge = key === "asks" && openAsks > 0;
          return (
            <Pressable key={key} onPress={() => setTab(key)} style={styles.tabItem}>
              <View>
                <Text style={{ fontSize: 20, opacity: active ? 1 : 0.4 }}>{emoji}</Text>
                {badge && (
                  <View style={styles.badge}>
                    <Text style={styles.badgeText}>{openAsks}</Text>
                  </View>
                )}
              </View>
              <Text style={[styles.tabItemLabel, active && { color: COLORS.text }]}>{label}</Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

export default function App() {
  const [fontsLoaded] = useFonts({
    DMSans_400Regular,
    DMSans_500Medium,
    DMSans_700Bold,
    DMMono_400Regular,
    DMMono_500Medium,
    Syne_700Bold,
    Syne_800ExtraBold,
  });

  if (!fontsLoaded) {
    return <View style={{ flex: 1, backgroundColor: COLORS.bg }} />;
  }

  return (
    <SafeAreaProvider>
      <HouseholdProvider>
        <StatusBar style="light" />
        <Shell />
      </HouseholdProvider>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: COLORS.bg,
  },
  content: {
    flex: 1,
    width: "100%",
    maxWidth: 480,
    alignSelf: "center",
    paddingHorizontal: 24,
  },
  header: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "flex-start",
    marginBottom: 20,
  },
  wordmark: {
    fontFamily: FONTS.displayHeavy,
    fontSize: 26,
    letterSpacing: -0.5,
    color: COLORS.text,
  },
  subline: {
    fontFamily: FONTS.mono,
    fontSize: 12,
    color: "#666",
    marginTop: 4,
  },
  flatLine: {
    fontFamily: FONTS.mono,
    fontSize: 11,
    color: COLORS.teal,
    marginTop: 2,
  },
  centered: {
    flex: 1,
    backgroundColor: COLORS.bg,
    alignItems: "center",
    justifyContent: "center",
    padding: 32,
    gap: 10,
  },
  errorTitle: {
    fontFamily: FONTS.display,
    fontSize: 17,
    color: COLORS.text,
  },
  errorDetail: {
    fontFamily: FONTS.sans,
    fontSize: 13,
    color: COLORS.textDim,
    textAlign: "center",
  },
  retryBtn: {
    marginTop: 8,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 12,
    backgroundColor: COLORS.coral,
  },
  retryLabel: {
    fontFamily: FONTS.display,
    fontSize: 14,
    color: "#fff",
  },
  tabBar: {
    flexDirection: "row",
    borderTopWidth: 1,
    borderTopColor: COLORS.cardBorder,
    backgroundColor: COLORS.panel,
    paddingTop: 10,
  },
  tabItem: {
    flex: 1,
    alignItems: "center",
    gap: 2,
  },
  tabItemLabel: {
    fontFamily: FONTS.sansMedium,
    fontSize: 11,
    color: COLORS.textFaint,
  },
  badge: {
    position: "absolute",
    top: -4,
    right: -10,
    minWidth: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: COLORS.coral,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 4,
  },
  badgeText: {
    fontFamily: FONTS.sansBold,
    fontSize: 10,
    color: "#1a1a2e",
  },
});
