import React from "react";
import { Text, View, ViewStyle } from "react-native";
import { COLORS, FONTS, RADII } from "../theme";

export function Card({ children, style }: { children: React.ReactNode; style?: ViewStyle }) {
  return (
    <View
      style={[
        {
          backgroundColor: COLORS.card,
          borderWidth: 1,
          borderColor: COLORS.cardBorder,
          borderRadius: RADII.card,
          paddingHorizontal: 18,
          paddingVertical: 14,
        },
        style,
      ]}
    >
      {children}
    </View>
  );
}

export function SectionLabel({ children }: { children: string }) {
  return (
    <Text
      style={{
        fontFamily: FONTS.mono,
        fontSize: 11,
        color: "#666",
        textTransform: "uppercase",
        letterSpacing: 1,
        marginBottom: 10,
      }}
    >
      {children}
    </Text>
  );
}
