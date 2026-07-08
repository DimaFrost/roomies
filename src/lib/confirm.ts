import { Alert, Platform } from "react-native";

/**
 * Confirmation prompt that works everywhere: native Alert on iOS/Android,
 * window.confirm on web (RN's Alert is a no-op there).
 */
export function confirmAction(
  title: string,
  message: string,
  confirmLabel: string,
  onConfirm: () => void,
  destructive = false
) {
  if (Platform.OS === "web") {
    if (typeof window !== "undefined" && window.confirm(`${title}\n\n${message}`)) onConfirm();
    return;
  }
  Alert.alert(title, message, [
    { text: "Cancel", style: "cancel" },
    { text: confirmLabel, style: destructive ? "destructive" : "default", onPress: onConfirm },
  ]);
}
