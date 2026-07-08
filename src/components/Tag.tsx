import React from "react";
import { Text, View } from "react-native";
import { COLORS, FONTS } from "../theme";

export function Tag({ label }: { label: string }) {
  return (
    <View
      style={{
        backgroundColor: "rgba(255,255,255,0.07)",
        borderWidth: 1,
        borderColor: COLORS.chipBorder,
        borderRadius: 6,
        paddingHorizontal: 8,
        paddingVertical: 2,
      }}
    >
      <Text style={{ fontFamily: FONTS.mono, fontSize: 11, color: "#aaa" }}>{label}</Text>
    </View>
  );
}
