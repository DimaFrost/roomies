import React from "react";
import { Text, View } from "react-native";
import { FONTS, personColor } from "../theme";

interface Props {
  name: string;
  people: string[];
  size?: number;
}

export function Avatar({ name, people, size = 36 }: Props) {
  return (
    <View
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        backgroundColor: personColor(name, people),
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <Text style={{ fontFamily: FONTS.sansBold, fontSize: size * 0.42, color: "#1a1a2e" }}>
        {name[0]?.toUpperCase() ?? "?"}
      </Text>
    </View>
  );
}
