import React, { useMemo, useState } from "react";
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
import { Avatar } from "../components/Avatar";
import { Card, SectionLabel } from "../components/Card";
import { PersonPicker } from "../components/PersonPicker";
import { confirmAction } from "../lib/confirm";
import { timeAgo } from "../lib/time";
import { useHousehold } from "../store";
import { COLORS, FONTS, RADII, personColor } from "../theme";
import { Ask } from "../types";

const QUICK_ASKS = [
  "🌱 Water my plants",
  "🛒 Pick something up",
  "🗑 Take out the trash",
  "🍳 Cook tonight",
  "📦 Accept a delivery",
  "🔑 Let someone in",
];

const ANYONE = "anyone";

export function AsksScreen() {
  const { state, addAsk, acceptAsk, completeAsk, deleteAsk } = useHousehold();
  const { people, asks } = state;

  const [composing, setComposing] = useState(false);
  const [title, setTitle] = useState("");
  const [note, setNote] = useState("");
  const [askedBy, setAskedBy] = useState(people[0]);
  const [target, setTarget] = useState<string>(ANYONE);

  const open = useMemo(() => asks.filter((a) => a.status === "open"), [asks]);
  const inProgress = useMemo(() => asks.filter((a) => a.status === "accepted"), [asks]);
  const done = useMemo(() => asks.filter((a) => a.status === "done").slice(0, 5), [asks]);

  const canPost = title.trim().length > 0;

  function selectAskedBy(p: string) {
    setAskedBy(p);
    if (target === p) setTarget(ANYONE);
  }

  function handlePost() {
    if (!canPost) return;
    addAsk({
      title: title.trim(),
      note: note.trim() || undefined,
      askedBy,
      assignedTo: target === ANYONE ? undefined : target,
    });
    setTitle("");
    setNote("");
    setTarget(ANYONE);
    setComposing(false);
  }

  function confirmDelete(ask: Ask) {
    confirmAction("Remove ask?", `"${ask.title}"`, "Remove", () => deleteAsk(ask.id), true);
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ gap: 12, paddingBottom: 24 }}
        keyboardShouldPersistTaps="handled"
      >
        {!composing ? (
          <Pressable onPress={() => setComposing(true)} style={styles.newAskBtn}>
            <Text style={styles.newAskBtnLabel}>+ Post an ask</Text>
            <Text style={styles.newAskBtnHint}>water the plants, grab milk, anything</Text>
          </Pressable>
        ) : (
          <Card style={{ gap: 12, paddingVertical: 16 }}>
            <SectionLabel>New ask</SectionLabel>
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6 }}>
              {QUICK_ASKS.map((q) => (
                <Pressable key={q} onPress={() => setTitle(q)} style={styles.quickChip}>
                  <Text style={{ fontSize: 12, fontFamily: FONTS.sans, color: "#888" }}>{q}</Text>
                </Pressable>
              ))}
            </View>
            <TextInput
              placeholder="What do you need?"
              placeholderTextColor="#555"
              value={title}
              onChangeText={setTitle}
              style={styles.input}
            />
            <TextInput
              placeholder="Details (optional)"
              placeholderTextColor="#555"
              value={note}
              onChangeText={setNote}
              style={styles.input}
            />

            <View>
              <Text style={styles.fieldLabel}>Who's asking?</Text>
              <PersonPicker options={people} people={people} selected={askedBy} onSelect={selectAskedBy} avatarSize={26} />
            </View>

            <View>
              <Text style={styles.fieldLabel}>Who should do it?</Text>
              <View style={{ flexDirection: "row", gap: 8 }}>
                <Pressable
                  onPress={() => setTarget(ANYONE)}
                  style={[styles.anyoneBtn, target === ANYONE && styles.anyoneBtnActive]}
                >
                  <Text style={{ fontSize: 16 }}>🙋</Text>
                  <Text
                    style={{
                      fontFamily: FONTS.sansMedium,
                      fontSize: 12,
                      color: target === ANYONE ? COLORS.yellow : "#666",
                    }}
                  >
                    Anyone
                  </Text>
                </Pressable>
                <View style={{ flex: 2 }}>
                  <PersonPicker
                    options={people.filter((p) => p !== askedBy)}
                    people={people}
                    selected={target === ANYONE ? undefined : target}
                    onSelect={setTarget}
                    avatarSize={22}
                  />
                </View>
              </View>
            </View>

            <View style={{ flexDirection: "row", gap: 8 }}>
              <Pressable onPress={() => setComposing(false)} style={styles.cancelBtn}>
                <Text style={{ fontFamily: FONTS.sansMedium, fontSize: 14, color: "#888" }}>Cancel</Text>
              </Pressable>
              <Pressable
                onPress={handlePost}
                disabled={!canPost}
                style={[styles.postBtn, !canPost && { backgroundColor: "rgba(255,255,255,0.06)" }]}
              >
                <Text style={[styles.postBtnLabel, !canPost && { color: "#444" }]}>Post Ask</Text>
              </Pressable>
            </View>
          </Card>
        )}

        {asks.length === 0 && !composing && (
          <Text style={styles.emptyText}>
            No asks yet.{"\n"}Need a favour? Post one and your flatmate will see it.
          </Text>
        )}

        {open.length > 0 && (
          <AskSection label={`Open (${open.length})`}>
            {open.map((ask) => (
              <AskCard key={ask.id} ask={ask} people={people} onLongPress={() => confirmDelete(ask)}>
                <View style={{ flexDirection: "row", gap: 8, marginTop: 10 }}>
                  {(ask.assignedTo ? [ask.assignedTo] : people.filter((p) => p !== ask.askedBy)).map((p) => (
                    <Pressable
                      key={p}
                      onPress={() => acceptAsk(ask.id, p)}
                      style={[styles.actionBtn, { borderColor: `${personColor(p, people)}66` }]}
                    >
                      <Text style={{ fontFamily: FONTS.sansMedium, fontSize: 12, color: personColor(p, people) }}>
                        {p}: I'm on it
                      </Text>
                    </Pressable>
                  ))}
                </View>
              </AskCard>
            ))}
          </AskSection>
        )}

        {inProgress.length > 0 && (
          <AskSection label={`In progress (${inProgress.length})`}>
            {inProgress.map((ask) => (
              <AskCard key={ask.id} ask={ask} people={people} onLongPress={() => confirmDelete(ask)}>
                <View style={{ flexDirection: "row", alignItems: "center", gap: 8, marginTop: 10 }}>
                  <Text style={{ fontFamily: FONTS.sans, fontSize: 12, color: COLORS.textDim, flex: 1 }}>
                    {ask.acceptedBy} is on it
                  </Text>
                  <Pressable
                    onPress={() => completeAsk(ask.id)}
                    style={[styles.actionBtn, { borderColor: "rgba(78,205,196,0.5)", backgroundColor: "rgba(78,205,196,0.1)" }]}
                  >
                    <Text style={{ fontFamily: FONTS.sansMedium, fontSize: 12, color: COLORS.teal }}>Done ✓</Text>
                  </Pressable>
                </View>
              </AskCard>
            ))}
          </AskSection>
        )}

        {done.length > 0 && (
          <AskSection label="Recently done">
            {done.map((ask) => (
              <AskCard key={ask.id} ask={ask} people={people} muted onLongPress={() => confirmDelete(ask)}>
                <Text style={{ fontFamily: FONTS.sans, fontSize: 11, color: COLORS.textFaint, marginTop: 6 }}>
                  ✓ done by {ask.acceptedBy ?? "someone"}
                  {ask.completedAt ? ` · ${timeAgo(ask.completedAt)}` : ""}
                </Text>
              </AskCard>
            ))}
          </AskSection>
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

function AskSection({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <View style={{ gap: 10 }}>
      <Text style={styles.sectionHeading}>{label}</Text>
      {children}
    </View>
  );
}

function AskCard({
  ask,
  people,
  muted,
  onLongPress,
  children,
}: {
  ask: Ask;
  people: string[];
  muted?: boolean;
  onLongPress: () => void;
  children?: React.ReactNode;
}) {
  return (
    <Pressable onLongPress={onLongPress}>
      <Card style={{ opacity: muted ? 0.55 : 1 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
          <Avatar name={ask.askedBy} people={people} size={32} />
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text numberOfLines={2} style={styles.askTitle}>
              {ask.title}
            </Text>
            <Text style={styles.askMeta}>
              {ask.askedBy} asked {ask.assignedTo ?? "anyone"} · {timeAgo(ask.createdAt)}
            </Text>
          </View>
        </View>
        {ask.note ? <Text style={styles.askNote}>{ask.note}</Text> : null}
        {children}
      </Card>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  newAskBtn: {
    borderWidth: 1,
    borderStyle: "dashed",
    borderColor: "rgba(255,230,109,0.35)",
    backgroundColor: "rgba(255,230,109,0.05)",
    borderRadius: RADII.card,
    paddingVertical: 18,
    alignItems: "center",
    gap: 2,
  },
  newAskBtnLabel: {
    fontFamily: FONTS.display,
    fontSize: 15,
    color: COLORS.yellow,
  },
  newAskBtnHint: {
    fontFamily: FONTS.sans,
    fontSize: 11,
    color: COLORS.textFaint,
  },
  quickChip: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: RADII.pill,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.1)",
  },
  input: {
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
  fieldLabel: {
    fontFamily: FONTS.sans,
    fontSize: 12,
    color: "#666",
    marginBottom: 8,
  },
  anyoneBtn: {
    flex: 1,
    borderWidth: 1,
    borderColor: COLORS.cardBorder,
    borderRadius: RADII.control,
    alignItems: "center",
    justifyContent: "center",
    gap: 4,
    paddingVertical: 8,
  },
  anyoneBtnActive: {
    borderColor: "rgba(255,230,109,0.5)",
    backgroundColor: "rgba(255,230,109,0.1)",
  },
  cancelBtn: {
    flex: 1,
    paddingVertical: 14,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: COLORS.cardBorder,
    alignItems: "center",
  },
  postBtn: {
    flex: 2,
    paddingVertical: 14,
    borderRadius: 14,
    backgroundColor: COLORS.yellow,
    alignItems: "center",
  },
  postBtnLabel: {
    fontFamily: FONTS.display,
    fontSize: 15,
    color: "#1a1a2e",
    letterSpacing: 0.3,
  },
  emptyText: {
    textAlign: "center",
    color: COLORS.textGhost,
    paddingVertical: 40,
    fontSize: 14,
    lineHeight: 22,
    fontFamily: FONTS.sans,
  },
  sectionHeading: {
    fontFamily: FONTS.mono,
    fontSize: 11,
    color: "#666",
    textTransform: "uppercase",
    letterSpacing: 1,
    marginTop: 6,
  },
  askTitle: {
    fontFamily: FONTS.sansMedium,
    fontSize: 14,
    color: COLORS.text,
    marginBottom: 2,
  },
  askMeta: {
    fontFamily: FONTS.mono,
    fontSize: 10,
    color: COLORS.textFaint,
  },
  askNote: {
    fontFamily: FONTS.sans,
    fontSize: 13,
    color: COLORS.textDim,
    marginTop: 8,
  },
  actionBtn: {
    borderWidth: 1,
    borderRadius: RADII.pill,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
});
