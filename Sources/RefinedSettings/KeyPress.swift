import Carbon.HIToolbox
import CoreGraphics

/// Presses keyboard shortcuts as if from the keyboard, and writes them the way menus do.
enum KeyPress {
    /// The modifiers a shortcut can hold. Their bits are the same in `CGEventFlags` and `NSEvent.ModifierFlags`.
    static let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
    /// Keys whose character doesn't say what they are. macOS adds fn to the arrow and function keys by itself, so
    /// these are written without it, as System Settings does.
    private static let namedKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func post(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        for isKeyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isKeyDown)
            event?.flags = modifiers
            event?.post(tap: .cghidEventTap)
        }
    }

    /// For example ⇧⌘T. `character` is what the key types with no modifiers, if anything.
    static func displayName(keyCode: CGKeyCode, character: String?, modifiers: CGEventFlags) -> String {
        let namedKey = namedKeys[Int(keyCode)]
        let symbols: [(flag: CGEventFlags, symbol: String)] = [
            (.maskSecondaryFn, "fn "),
            (.maskControl, "⌃"),
            (.maskAlternate, "⌥"),
            (.maskShift, "⇧"),
            (.maskCommand, "⌘"),
        ]
        let modifierSymbols = symbols
            .filter { candidate in modifiers.contains(candidate.flag) && (candidate.flag != .maskSecondaryFn || namedKey == nil) }
            .map { candidate in candidate.symbol }
            .joined()
        let key = namedKey ?? character.map { typed in typed.uppercased() } ?? "key \(keyCode)"

        return modifierSymbols + key
    }
}
