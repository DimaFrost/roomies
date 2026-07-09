import React, { useState } from "react";
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { Card, SectionLabel } from "../components/Card";
import { useHousehold } from "../store";
import { COLORS, FONTS, RADII } from "../theme";

type Mode = "create" | "join";

export function OnboardingScreen() {
  const { createHousehold, joinHousehold } = useHousehold();

  const [mode, setMode] = useState<Mode>("create");
  const [flatName, setFlatName] = useState("");
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const canSubmit =
    name.trim().length > 0 && (mode === "create" ? flatName.trim().length > 0 : code.trim().length >= 6);

  async function handleSubmit() {
    if (!canSubmit || busy) return;
    setBusy(true);
    setError(null);
    const err =
      mode === "create"
        ? await createHousehold(flatName, name)
        : await joinHousehold(code, name);
    setBusy(false);
    if (err) setError(err);
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <ScrollView contentContainerStyle={styles.container} keyboardShouldPersistTaps="handled">
        <Text style={styles.wordmark}>
          room<Text style={{ color: COLORS.coral }}>ies</Text>
        </Text>
        <Text style={styles.tagline}>your flat, one app</Text>

        <View style={styles.modeBar}>
          {(["create", "join"] as Mode[]).map((m) => (
            <Pressable key={m} onPress={() => setMode(m)} style={[styles.modeBtn, mode === m && styles.modeBtnActive]}>
              <Text style={[styles.modeLabel, mode === m && { color: "#fff" }]}>
                {m === "create" ? "Start a flat" : "Join a flat"}
              </Text>
            </Pressable>
          ))}
        </View>

        <Card style={{ gap: 12, paddingVertical: 18 }}>
          {mode === "create" ? (
            <>
              <SectionLabel>Name your flat</SectionLabel>
              <TextInput
                placeholder="e.g. Sonnenallee 42"
                placeholderTextColor="#555"
                value={flatName}
                onChangeText={setFlatName}
                style={styles.input}
              />
            </>
          ) : (
            <>
              <SectionLabel>Invite code</SectionLabel>
              <TextInput
                placeholder="6-letter code from your flatmate"
                placeholderTextColor="#555"
                value={code}
                onChangeText={(t) => setCode(t.toUpperCase())}
                autoCapitalize="characters"
                autoCorrect={false}
                style={[styles.input, { fontFamily: FONTS.monoMedium, letterSpacing: 3 }]}
              />
            </>
          )}

          <SectionLabel>Your name</SectionLabel>
          <TextInput
            placeholder="What your flatmates call you"
            placeholderTextColor="#555"
            value={name}
            onChangeText={setName}
            style={styles.input}
          />

          {error && <Text style={styles.error}>{error}</Text>}

          <Pressable
            onPress={handleSubmit}
            disabled={!canSubmit || busy}
            style={[styles.submitBtn, (!canSubmit || busy) && { backgroundColor: "rgba(255,255,255,0.06)" }]}
          >
            <Text style={[styles.submitLabel, (!canSubmit || busy) && { color: "#444" }]}>
              {busy ? "Setting up…" : mode === "create" ? "Create Flat" : "Join Flat"}
            </Text>
          </Pressable>
        </Card>

        <Text style={styles.hint}>
          {mode === "create"
            ? "You'll get an invite code to share with your flatmates."
            : "Ask whoever set up the flat for the code — it's shown in the app header."}
        </Text>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flexGrow: 1,
    justifyContent: "center",
    paddingHorizontal: 24,
    paddingVertical: 40,
    width: "100%",
    maxWidth: 480,
    alignSelf: "center",
  },
  wordmark: {
    fontFamily: FONTS.displayHeavy,
    fontSize: 40,
    letterSpacing: -1,
    color: COLORS.text,
    textAlign: "center",
  },
  tagline: {
    fontFamily: FONTS.mono,
    fontSize: 12,
    color: "#666",
    textAlign: "center",
    marginTop: 4,
    marginBottom: 28,
  },
  modeBar: {
    flexDirection: "row",
    gap: 4,
    backgroundColor: COLORS.card,
    borderRadius: 12,
    padding: 4,
    marginBottom: 16,
  },
  modeBtn: {
    flex: 1,
    paddingVertical: 9,
    borderRadius: 9,
    alignItems: "center",
  },
  modeBtnActive: {
    backgroundColor: "rgba(255,255,255,0.1)",
  },
  modeLabel: {
    fontFamily: FONTS.sansMedium,
    fontSize: 13,
    color: COLORS.textFaint,
  },
  input: {
    backgroundColor: COLORS.card,
    borderWidth: 1,
    borderColor: COLORS.cardBorder,
    borderRadius: RADII.control,
    paddingHorizontal: 14,
    paddingVertical: 12,
    color: COLORS.textSoft,
    fontFamily: FONTS.sans,
    fontSize: 15,
  },
  error: {
    fontFamily: FONTS.sans,
    fontSize: 13,
    color: COLORS.coral,
  },
  submitBtn: {
    paddingVertical: 15,
    borderRadius: 14,
    backgroundColor: COLORS.coral,
    alignItems: "center",
    marginTop: 4,
  },
  submitLabel: {
    fontFamily: FONTS.display,
    fontSize: 15,
    color: "#fff",
    letterSpacing: 0.3,
  },
  hint: {
    fontFamily: FONTS.sans,
    fontSize: 12,
    color: COLORS.textFaint,
    textAlign: "center",
    marginTop: 16,
    lineHeight: 18,
  },
});
