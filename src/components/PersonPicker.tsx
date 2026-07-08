import React from "react";
import { Pressable, Text, View } from "react-native";
import { COLORS, FONTS, RADII, personColor } from "../theme";
import { Avatar } from "./Avatar";

interface Props {
  options: string[];
  people: string[];
  selected?: string;
  onSelect: (name: string) => void;
  avatarSize?: number;
}

/** Row of selectable flatmate buttons, colored per person. */
export function PersonPicker({ options, people, selected, onSelect, avatarSize = 28 }: Props) {
  return (
    <View style={{ flexDirection: "row", gap: 8 }}>
      {options.map((p) => {
        const active = selected === p;
        const color = personColor(p, people);
        return (
          <Pressable
            key={p}
            onPress={() => onSelect(p)}
            style={{
              flex: 1,
              paddingVertical: 8,
              paddingHorizontal: 4,
              borderRadius: RADII.control,
              borderWidth: 1,
              borderColor: active ? `${color}66` : COLORS.cardBorder,
              backgroundColor: active ? `${color}22` : "transparent",
              alignItems: "center",
              gap: 6,
            }}
          >
            <Avatar name={p} people={people} size={avatarSize} />
            <Text
              style={{
                fontFamily: FONTS.sansMedium,
                fontSize: 12,
                color: active ? color : "#666",
              }}
            >
              {p}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}
