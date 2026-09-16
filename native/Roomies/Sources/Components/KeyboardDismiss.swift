import SwiftUI
import UIKit

/// Ways to put the keyboard away, since the iPhone keyboard has none of its own.
///
/// The hide-keyboard key people remember is an iPad-only key; on iPhone the software keyboard
/// offers no way to dismiss itself, so every app has to provide one. This app previously
/// provided none, which left the keyboard covering the screen with no obvious way out.
@MainActor
enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Installs one window-wide tap that dismisses the keyboard.
///
/// `cancelsTouchesInView = false` is what makes this safe to apply globally: the tap observes
/// without consuming, so buttons, pickers and text fields all still receive it. Without that
/// flag a gesture at window level swallows the first tap on every control in the app.
@MainActor
final class KeyboardDismissGesture: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissGesture()
    private var installed = false

    func install() {
        guard !installed else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let window else { return }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        installed = true
    }

    @objc private func handleTap() {
        Keyboard.dismiss()
    }

    /// Coexist with everything else rather than competing — scroll views, sheet drags and
    /// long-presses all keep their own recognisers.
    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    /// Ignore taps that land in a text field, so tapping one doesn't open the keyboard and
    /// immediately close it again. A window-wide dismisser without this makes every field in the
    /// app feel broken: the field takes focus on touch-up and this gesture fires on the same
    /// touch-up, so the two race over the same tap.
    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        MainActor.assumeIsolated {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
    }
}

extension View {
    /// Gives a screen every way out of the keyboard: a Done button above it, a drag down over
    /// any scrolling content, and (via the window gesture) a tap anywhere else.
    ///
    /// `scrollDismissesKeyboard` reads from the environment, so applying this at a screen's root
    /// covers every scroll view inside it.
    func keyboardDismissable() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { Keyboard.dismiss() }
                        .font(Fonts.display(15))
                        .foregroundColor(Theme.coral)
                }
            }
    }
}
