import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// A "Switch to Desktop N" shortcut from System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
struct DesktopShortcut {
    /// The modifier bits macOS stores for a shortcut are the same as `CGEventFlags`.
    private static let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
    /// AppleSymbolicHotKeys IDs 118 to 126 are "Switch to Desktop 1" to "Switch to Desktop 9".
    private static let firstHotKeyID = 118
    /// Stored in place of a character for keys that don't type one, such as the arrow keys.
    private static let noCharacter = 65535
    /// Keys whose stored character doesn't say what they are. macOS adds fn to the arrow and function keys by itself, so
    /// these are written without it, as System Settings does.
    private static let namedKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    let desktopNumber: Int
    let character: Int
    let keyCode: Int64
    let modifiers: CGEventFlags

    /// Written like a menu shortcut, for example ⇧⌘1.
    var displayName: String {
        let namedKey = Self.namedKeys[Int(keyCode)]
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
        let typedKey = character == Self.noCharacter ? nil : UnicodeScalar(character).map { scalar in String(scalar).uppercased() }
        let key = namedKey ?? typedKey ?? "key \(keyCode)"

        return modifierSymbols + key
    }

    func matches(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventKeycode) == keyCode && event.flags.intersection(Self.modifierMask) == modifiers
    }

    /// Reads the file itself because CFPreferences would keep serving this process a cached copy.
    static func loadAll() -> [DesktopShortcut] {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")

        guard let data = try? Data(contentsOf: fileURL),
              let preferences = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let hotKeys = preferences["AppleSymbolicHotKeys"] as? [String: Any]
        else { return [] }

        return (1...9).compactMap { desktopNumber in
            guard let hotKey = hotKeys[String(firstHotKeyID + desktopNumber - 1)] as? [String: Any],
                  hotKey["enabled"] as? Bool == true,
                  let value = hotKey["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int],
                  parameters.count == 3
            else { return nil }

            return DesktopShortcut(
                desktopNumber: desktopNumber,
                character: parameters[0],
                keyCode: Int64(parameters[1]),
                modifiers: CGEventFlags(rawValue: UInt64(parameters[2])).intersection(modifierMask)
            )
        }
    }
}
