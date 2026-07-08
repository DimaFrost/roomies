export const COLORS = {
  bg: "#0f0f1a",
  panel: "rgba(20,20,36,0.96)",
  card: "rgba(255,255,255,0.04)",
  cardBorder: "rgba(255,255,255,0.08)",
  chipBorder: "rgba(255,255,255,0.12)",
  text: "#f0f0f0",
  textSoft: "#ddd",
  textDim: "#888",
  textFaint: "#555",
  textGhost: "#444",
  coral: "#FF6B6B",
  teal: "#4ECDC4",
  yellow: "#FFE66D",
};

// Stable palette for household members; assigned by join order.
const MEMBER_PALETTE = ["#FF6B6B", "#4ECDC4", "#FFE66D", "#A78BFA", "#6BCB77", "#F49AC2"];

export function personColor(name: string, people: string[]): string {
  const idx = people.indexOf(name);
  return MEMBER_PALETTE[(idx >= 0 ? idx : people.length) % MEMBER_PALETTE.length];
}

export const FONTS = {
  sans: "DMSans_400Regular",
  sansMedium: "DMSans_500Medium",
  sansBold: "DMSans_700Bold",
  mono: "DMMono_400Regular",
  monoMedium: "DMMono_500Medium",
  display: "Syne_700Bold",
  displayHeavy: "Syne_800ExtraBold",
};

export const RADII = { card: 16, control: 10, pill: 8 };
